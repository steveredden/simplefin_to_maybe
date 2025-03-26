#lib/simplefil_to_maybe/maybe_postgres_client.rb

require 'bigdecimal'
require 'pg'
require 'securerandom'

require_relative "utils"

module SimpleFINToMaybe
  class MaybeClient
    def initialize(host: ENV['DB_HOST'], port: ENV['DB_PORT'], dbname: ENV['DB_NAME'],
                   user: ENV['DB_USER'], password: ENV['DB_PASSWORD'])
      @connection = PG.connect(
        host: host,
        port: port.to_i,
        dbname: dbname,
        user: user,
        password: password
      )
    rescue PG::Error => e
      puts "Connection error: #{e.message}"
    end

    def get_families
      execute("SELECT id, name FROM public.families")
    end

    def get_accounts(family_id = nil)
      family_id ||= get_families.first&.dig("id")
      return [] if family_id.nil?
    
      query = <<-SQL
        SELECT
          a.id,
          a.name,
          a.family_id,
          a.accountable_type,
          a.subtype,
          a.plaid_account_id,
          a.import_id,
          pa.plaid_id AS simplefin_account_id
        FROM public.accounts AS a
        LEFT OUTER JOIN public.plaid_accounts AS pa
          ON a.plaid_account_id = pa.id
        WHERE a.family_id = $1;
      SQL
    
      execute(query, [family_id])
    end
    
    def get_simplefin_tx_entries(account_id, start_date = get_first_of_month())
      query = <<-SQL
        SELECT plaid_id FROM public.account_entries
        WHERE account_id = $1
        AND plaid_id IS NOT NULL
        AND date >= $2;
      SQL
    
      execute(query, [account_id, start_date])
    end

    def get_security(ticker)
      query = <<-SQL
        SELECT id, ticker
        FROM public.securities
        WHERE ticker = $1
      SQL

      return execute(query, [ticker])
    end

    def get_or_create_security(ticker)
      result = get_security(ticker)

      if result.any?
        return result[0]
      else

        insert_query = <<-SQL
          INSERT INTO public.securities (ticker, created_at, updated_at)
          VALUES ($1, NOW(), NOW())
          RETURNING *;
        SQL
        
        result = execute(insert_query, [ticker])
        return result[0]
      end
    end

    def get_security_price(ticker, dateYYYYmmdd)
      security_uuid = get_security(ticker)

      return nil if security_uuid.nil?

      query = <<-SQL
        SELECT price FROM public.security_prices
        WHERE security_id = $1 AND date = $2
      SQL

      return execute(query, [ticker, dateYYYYmmdd])
    end

    def get_account_holdings(account_id)
      query = <<-SQL
        SELECT DISTINCT ON (security_id)
          ah.security_id,
          s.ticker,
          s.name,
          ah.qty
        FROM public.account_holdings AS ah
        JOIN public.securities AS s
          ON ah.security_id = s.id
        WHERE ah.account_id = $1
      SQL

      execute(query, [account_id])
    end

    def match_other_transactions(transactions)
      if transactions.is_a?(Array)
        transactions.each do |tx|

        end
      end
    end

    #NOT USED ANYMORE... STUFFING INTO PLAID BREAKS TOO MANY THINGS!
    def new_simplefin_account(account_row, simplefin_account)
      # extract maybe information
      family_id = account_row.dig("family_id")
      account_id = account_row.dig("id")
      account_name = account_row.dig("name")
      account_type = account_row.dig("accountable_type")
      account_subtype = account_row.dig("subtype")

      # extra simplefin information
      simplefin_account_uuid = simplefin_account.dig("id")
      simplefin_org_uri = simplefin_account.dig("org", "url")
      simplefin_org_id = simplefin_account.dig("org", "id")
      currency = simplefin_account.dig("currency")
      current_balance = simplefin_account.dig("balance")
      available_balance = simplefin_account.dig("available-balance")
      last_synced_at = convert_epoch_to_pg_timestamp(simplefin_account.dig("balance-date"))

      # misc
      stuffed_products = '{"assets","balance","investments","liabilities","transactions"}'
    
      # Insert the plaid_items entry
      plaid_items_uuid = SecureRandom.uuid
      query = <<-SQL
        INSERT INTO public.plaid_items(id, family_id, plaid_id, name, created_at, updated_at, access_token, institution_url, institution_id, available_products, billed_products, last_synced_at) 
        VALUES ($1, $2, $3, $4, NOW(), NOW(), 'SimpleFIN', $5, $6, $7, $8, $9);
      SQL
      execute(query, [plaid_items_uuid, family_id, simplefin_account_uuid, account_name, simplefin_org_uri, simplefin_org_id, stuffed_products, stuffed_products, last_synced_at])
    
      # Insert the plaid_accounts entry
      plaid_account_uuid = SecureRandom.uuid
      query = <<-SQL
        INSERT INTO public.plaid_accounts(id, plaid_id, plaid_item_id, plaid_type, plaid_subtype, name, created_at, updated_at, current_balance, available_balance, currency) 
        VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW(), $7, $8, $9);
      SQL
      execute(query, [plaid_account_uuid, simplefin_account_uuid, plaid_items_uuid, account_type, account_subtype, account_name, current_balance, available_balance, currency])
    
      # Update the accounts entry to point to the plaid_accounts.id
      query = <<-SQL
        UPDATE public.accounts 
        SET plaid_account_id = $1 
        WHERE id = $2;
      SQL
      execute(query, [plaid_account_uuid, account_id])

      return account_id
    end

    def new_simplefin_import(account_row, simplefin_account_id)
      family_id = account_row.dig("family_id")
      account_id = account_row.dig("id")

      query = <<-SQL
        INSERT INTO public.imports(id, family_id, account_id, created_at, updated_at, type, status) 
        VALUES ($1, $2, $3, NOW(), NOW(), 'MintImport', 'importing');
      SQL
      execute(query, [simplefin_account_id, family_id, account_id])

      query = <<-SQL
        UPDATE public.accounts 
        SET import_id = $1 
        WHERE id = $2;
      SQL
      execute(query, [simplefin_account_id, account_id])

      return account_id
    end
    
    # client.new_transaction('5a6c6582-6ff0-48b9-9106-1e5cc02c094e', '11.1100', 'USD', '2025-03-11', 'transaction6', 'TRN-abc123')
    def new_transaction(account_id, amount, short_date, display_name, simplefin_txn_id, currency = "USD")
      transaction_uuid = SecureRandom.uuid
      adjusted_amount = BigDecimal(amount.to_s) * -1
    
      # Insert the account_entries entry
      query = <<-SQL
        INSERT INTO public.account_entries(
          account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at, plaid_id
        ) VALUES (
          $1, 'Account::Transaction', $2, $3, $4, $5, $6, NOW(), NOW(), $7
        );
      SQL
      execute(query, [account_id, transaction_uuid, adjusted_amount, currency, short_date, display_name, simplefin_txn_id])
    
      # Insert the account_transaction entry
      query = <<-SQL
        INSERT INTO public.account_transactions(
          id, created_at, updated_at
        ) VALUES (
          $1, NOW(), NOW()
        );
      SQL
      execute(query, [transaction_uuid])
    end

    def new_trade(account_id, ticker, amount, quantity, price, short_date, display_name, simplefin_txn_id, currency = "USD")
      trade_uuid = SecureRandom.uuid
      adjusted_amount = BigDecimal(amount.to_s) * -1
    
      # Insert the account_entries entry
      query = <<-SQL
        INSERT INTO public.account_entries(
          account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at, plaid_id
        ) VALUES (
          $1, 'Account::Trade', $2, $3, $4, $5, $6, NOW(), NOW(), $7
        );
      SQL
      execute(query, [account_id, trade_uuid, adjusted_amount, currency, short_date, display_name, simplefin_txn_id])

      security_id = get_or_create_security(ticker).dig("id")
    
      # Insert the account_transaction entry
      query = <<-SQL
        INSERT INTO public.account_trades(
          id, security_id, qty, price, created_at, updated_at, currency
        ) VALUES (
          $1, $2, $3, $4, NOW(), NOW(), $5
        );
      SQL
      execute(query, [trade_uuid, security_id, quantity, price, currency])
    end

    def close
      @connection.close if @connection
    end

    private
    
    def execute(query, params = [])
      begin
        result = @connection.exec_params(query, params)
        result.to_a
      rescue PG::Error => e
        puts "Query execution error: #{e.message}"
        nil
      end
    end

  end
end