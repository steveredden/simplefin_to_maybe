# app/lib/maybe_client.rb

require 'bigdecimal'
require 'pg'
require 'securerandom'

class MaybeClient

  attr_reader :error_message

  def initialize(host, port, dbname, user, password)
    Rails.logger.info "Testing connect to PG: #{user}:#{password}@#{host}:#{port} -- #{dbname}"

    begin
      @connection = PG.connect(
        host: host,
        port: port.to_i,
        dbname: dbname,
        user: user,
        password: password
      )
      @connected = true
    rescue PG::Error => e
      Rails.logger.error "Connection error: #{e.message}"
      @connected = false
      @error_message = e.message
    end
  end

  def connected?
    @connected
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
        a.currency,
        a.accountable_type,
        a.subtype,
        pa.plaid_id
      FROM public.accounts AS a
      LEFT OUTER JOIN public.plaid_accounts AS pa
        ON a.plaid_account_id = pa.id
      WHERE a.family_id = $1;
    SQL
  
    execute(query, [family_id])
  end

  def get_account(account_id)
  
    query = <<-SQL
      SELECT
        a.id,
        a.name,
        a.family_id,
        a.currency,
        a.accountable_type,
        a.subtype,
        pa.plaid_id
      FROM public.accounts AS a
      LEFT OUTER JOIN public.plaid_accounts AS pa
        ON a.plaid_account_id = pa.id
      WHERE a.id = $1
      LIMIT 1;
    SQL
  
    execute(query, [account_id])&.first
  end
  
  def get_simplefin_transactions(account_id, start_date)
    query = <<-SQL
      SELECT plaid_id FROM public.account_entries
      WHERE account_id = $1
      AND plaid_id IS NOT NULL
      AND date >= (TO_TIMESTAMP($2)::DATE)
    SQL
  
    execute(query, [account_id, start_date])
  end

  def upsert_account_valuation(account_id, simplefin_account)
    valuation_uuid = SecureRandom.uuid
    amount = simplefin_account.dig("balance")
    currency = simplefin_account.dig("currency")
    date = simplefin_account.dig("balance-date")
  
    # Check if a row exists with the same account_id and date
    select_query = <<-SQL
      SELECT id FROM public.account_entries 
      WHERE account_id = $1 AND date = (TO_TIMESTAMP($2)::DATE) AND entryable_type = 'Account::Valuation' LIMIT 1;
    SQL
    existing_entry = execute(select_query, [account_id, date]).first
  
    if existing_entry
      # Update existing row
        
      Rails.logger.info "Found existing valuation"

      valuation_uuid = existing_entry["id"]
      update_query = <<-SQL
        UPDATE public.account_entries 
        SET amount = $1, updated_at = NOW()
        WHERE id = $2;
      SQL
      execute(update_query, [amount, valuation_uuid])

      # also update account_valuations timestamp
      valuation_update_query = <<-SQL
        UPDATE public.account_valuations
        SET updated_at = NOW()
        WHERE id = $1;
      SQL
      execute(valuation_update_query, [valuation_uuid])
    else
      # Insert new row

      Rails.logger.info "Adding a Balance Update..."

      insert_query = <<-SQL
        INSERT INTO public.account_entries (
          account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at
        ) VALUES (
          $1, 'Account::Valuation', $2, $3, $4, (TO_TIMESTAMP($5)::DATE), 'Balance Update', NOW(), NOW()
        );
      SQL
      execute(insert_query, [account_id, valuation_uuid, amount, currency, date])

      insert_valuation_query = <<-SQL
        INSERT INTO public.account_valuations (
          id, created_at, updated_at
        ) VALUES (
          $1, NOW(), NOW()
        );
      SQL
      execute(insert_valuation_query, [valuation_uuid])
    end
  end
  
  def new_transaction(account_id, simplefin_transaction_record, currency)
    amount = simplefin_transaction_record.dig("amount")
    short_date = simplefin_transaction_record.dig("posted")
    display_name = simplefin_transaction_record.dig("description")
    simplefin_txn_id = simplefin_transaction_record.dig("id")

    transaction_uuid = SecureRandom.uuid
    adjusted_amount = BigDecimal(amount.to_s) * -1
  
    # Insert the account_entries entry
    query = <<-SQL
      INSERT INTO public.account_entries(
        account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at, plaid_id
      ) VALUES (
        $1, 'Account::Transaction', $2, $3, $4, (TO_TIMESTAMP($5)::DATE), $6, NOW(), NOW(), $7
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

  def new_plaid_account(maybe_account, simplefin_account)
    # extract maybe information
    family_id = maybe_account.dig("family_id")
    account_id = maybe_account.dig("id")

    # extra simplefin information
    simplefin_org_uri = simplefin_account.dig("org", "url")
    simplefin_org_id = simplefin_account.dig("org", "id")
  
    # Insert the plaid_items entry
    plaid_items_uuid = SecureRandom.uuid
    query = <<-SQL
      INSERT INTO public.plaid_items(id, family_id, created_at, updated_at, institution_url, institution_id) 
      VALUES ($1, $2, NOW(), NOW(), $3, $4);
    SQL
    execute(query, [plaid_items_uuid, family_id, simplefin_org_uri, simplefin_org_id])
  
    # Insert the plaid_accounts entry
    plaid_account_uuid = SecureRandom.uuid
    query = <<-SQL
      INSERT INTO public.plaid_accounts(id, plaid_item_id, created_at, updated_at) 
      VALUES ($1, $2, NOW(), NOW());
    SQL
    execute(query, [plaid_account_uuid, plaid_items_uuid])
  
    # Update the accounts entry to point to the plaid_accounts.id
    query = <<-SQL
      UPDATE public.accounts 
      SET plaid_account_id = $1 
      WHERE id = $2;
    SQL
    execute(query, [plaid_account_uuid, account_id])
  end

  def close
    @connection.close if @connection
  end

  private

  def execute(query, params = [])
    Rails.logger.info "Executing Query: #{query}"
    Rails.logger.info "With Parameters: #{params.inspect}"
    begin
      result = @connection.exec_params(query, params)
      result.to_a
    rescue PG::Error => e
      Rails.logger.error "Query execution error: #{e.message}"
      nil
    end
  end

end