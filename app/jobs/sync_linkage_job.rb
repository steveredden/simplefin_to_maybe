# app/jobs/sync_linkage_job.rb

class SyncLinkageJob < ApplicationJob
  queue_as :default

  def perform(linkage)

    linkage.update(sync_status: :running)
    
    maybe_account = Account.find_by(id: linkage.maybe_account_id)
    simplefin_account = Account.find_by(id: linkage.simplefin_account_id)

    @maybe_client = MaybeClientService.connect
    if @maybe_client.nil?
      linkage.update(sync_status: :error, last_sync: Time.current)
      @maybe_client.close
      return
    end

    username = Setting.find_by(key: 'simplefin_username')&.value
    password = Setting.find_by(key: 'simplefin_password')&.value

    if username.blank? || password.blank?
      Rails.logger.warn "Missing SimpleFIN username or password!"
      linkage.update(sync_status: :error, last_sync: Time.current)
      @maybe_client.close
      return
    else
      simplefin_client = SimplefinClient.new(username, password)
    end

    lookback_days = Setting.find_by(key: 'lookback_days')&.value.to_i
    lookback_days = 7 if lookback_days.zero?  # Fallback to 7 if the value is nil or non-numeric
    start_date = (Time.now - (lookback_days * 24 * 60 * 60)).to_i

    if maybe_account.accountable_type == "Investment"
      simplefin_response = simplefin_client.get_transactions(simplefin_account.identifier, start_date)

      if simplefin_response[:success]
        simplefin_transactions = simplefin_response[:response].dig("accounts").first&.dig("transactions") || []
        simplefin_current_holdings = simplefin_response[:response].dig("accounts").first&.dig("holdings") || []
        transactions_in_maybe = @maybe_client.get_simplefin_transactions(maybe_account.identifier, start_date)


        # Filter out transactions that are already in transactions_in_maybe based on plaid_id
        filtered_simplefin_transactions = simplefin_transactions.reject do |txn|
          transactions_in_maybe.any? { |m| m.dig("plaid_id") == txn.dig("id") }
        end

        # Process all transactions  txn, maybe_account_id, transactions_in_maybe, simplefin_holdings
        trade_transactions = filtered_simplefin_transactions.map { |txn| process_trade(txn, maybe_account.identifier, transactions_in_maybe, simplefin_current_holdings) }.compact
        non_trade_transactions = filtered_simplefin_transactions.map { |txn| process_non_trade(txn) }.compact

        Rails.logger.info "TRADES: #{trade_transactions.inspect}"
        Rails.logger.info "TRANSACTIONS: #{non_trade_transactions.inspect}"

        trade_transactions.each do |trade_tx|
          simplefin_transaction = trade_tx.dig("simplefin_transaction")
          security_id = trade_tx.dig("security_id")
          ticker = trade_tx.dig("ticker")
          change = trade_tx.dig("change")
          @maybe_client.new_trade(maybe_account.identifier, simplefin_transaction, security_id, ticker, change, simplefin_account.currency)
        end

        non_trade_transactions.each do |norm_tx|
          simplefin_transaction = norm_tx.dig("simplefin_transaction")
          @maybe_client.new_transaction(maybe_account.identifier, simplefin_transaction, simplefin_account.currency)
        end

        #lastly, update balance
        simplefin_account_with_balance = simplefin_response[:response].dig("accounts").first
        @maybe_client.upsert_account_valuation(maybe_account.identifier, simplefin_account_with_balance)
      end
    else  #CreditCard,Despository,Loan
      simplefin_response = simplefin_client.get_transactions(simplefin_account.identifier, start_date)
      
      if simplefin_response[:success]
        simplefin_transactions = simplefin_response[:response].dig("accounts").first&.dig("transactions") || []
        transactions_in_maybe = @maybe_client.get_simplefin_transactions(maybe_account.identifier, start_date)
        
        # Early return if transactions are the same
        if simplefin_transactions.length == transactions_in_maybe.length
          linkage.update(sync_status: :complete, last_sync: Time.current)
          return
        end
    
        simplefin_transactions.each do |simplefin_transaction|
    
          # If this transaction hasn't been synced yet, create a new transaction in Maybe
          unless transactions_in_maybe.any? { |t| t["plaid_id"] == simplefin_transaction.dig("id") }
            @maybe_client.new_transaction(maybe_account.identifier, simplefin_transaction, simplefin_account.currency)
          end
        end
      else
        Rails.logger.error("Failed to fetch transactions from SimpleFin API")
        linkage.update(sync_status: :error, last_sync: Time.current)
      end
    end
   
    linkage.update(sync_status: :complete, last_sync: Time.current)
    @maybe_client.close
  end

    # Helper function to estimate shares
  def estimate_shares(amount, price)
    (amount.abs / price).round(2) if price && price > 0
  end

  # Function to handle dividend reinvestment as buy transactions
  def process_trade(txn, maybe_account_id, transactions_in_maybe, simplefin_holdings)
    description = txn.dig("description")&.gsub(/\s+/, ' ')
    if description.include?("DIVIDEND REINVEST") && txn.dig("amount").to_f < 0
      action = "BUY" # Treat dividend reinvestments as buys
      security_name = description.split('-')[1].strip  # 2nd object in the split
    elsif description =~ /(BUY|SELL) - (.+)/
      action, security_name = $1, $2
    else
      return nil
    end

    # Match symbol from simplefin_holdings or maybe_holdings
    holding = simplefin_holdings.find { |h| h.dig("description").include?(security_name) }
    return nil if holding.nil?

    symbol = holding&.dig("symbol")
    maybe_holding = @maybe_client.get_account_holdings_by_ticker(maybe_account_id, txn.dig("posted"), symbol ).first

    security_id = @maybe_client.find_or_create_security(symbol, security_name)
    price = maybe_holding&.dig("price") || holding.dig("cost_basis")
    quantity = maybe_holding.nil? ? holding.dig("shares") : estimate_shares(txn["amount"].to_f, price.to_f)

    if symbol && quantity
      {
        "simplefin_transaction" => txn,
        "security_id" => security_id,
        "ticker" => symbol,
        "change" => (action == "BUY" ? quantity : -quantity).to_f
      }
    end
  end

  # Function to process interest payment and management fees
  def process_non_trade(txn)
    description = txn.dig("description")&.gsub(/\s+/, ' ')
    if description.include?("INTEREST PAYMENT") && txn.dig("amount").to_f > 0
      {
        "simplefin_transaction" => txn
      }
    elsif description.include?("MANAGEMENT FEE") && txn.dig("amount").to_f < 0
      {
        "simplefin_transaction" => txn
      }
    elsif description.include?("DIVIDEND") && txn.dig("amount").to_f > 0
      {
        "simplefin_transaction" => txn
      }
    else
      return nil
    end
  end
end
  