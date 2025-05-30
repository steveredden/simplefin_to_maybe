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
      version = get_latest_schema_migration
      if version >= 20250413141446
        Rails.logger.info "Detected schema migration version #{version}; Using new simplified schema!"
        @entries_table = "public.entries"
        @valuations_table = "public.valuations"
        @valuation_key = "Valuation"
        @transactions_table = "public.transactions"
        @transaction_key = "Transaction"
      else
        Rails.logger.info "Detected schema migration version #{version}; Using old Account:: schema!"
        @entries_table = "public.account_entries"
        @valuations_table = "public.account_valuations"
        @valuation_key = "Account::Valuation"
        @transactions_table = "public.account_transactions"
        @transaction_key = "Account::Transaction"
      end
    rescue PG::Error => e
      Rails.logger.error "Connection error: #{e.message}"
      @connected = false
      @error_message = e.message
    end
  end

  def connected?
    @connected
  end

  def get_latest_schema_migration
    execute("SELECT version FROM public.schema_migrations ORDER BY version DESC LIMIT 1")&.first&.dig("version")&.to_i
  end

  def valuation_key
    @valuation_key
  end

  def transaction_key
    @transaction_key
  end

  def get_families
    execute("SELECT id, name FROM public.families")
  end

  def get_accounts(family_id = nil)
    query = <<-SQL
      SELECT
        a.id,
        a.name,
        a.family_id,
        a.currency,
        a.accountable_type,
        a.subtype,
        l.interest_rate
      FROM public.accounts AS a
      LEFT OUTER JOIN public.loans AS l ON a.accountable_id = l.id
    SQL
  
    if family_id
      query += " WHERE family_id = $1"
      execute(query, [family_id])
    else
      execute(query)
    end
  end

  def get_account_by_id(account_id)
    query = <<-SQL
      SELECT *
      FROM public.accounts
      WHERE id = $1
    SQL

    execute(query, [account_id]).first
end
  
  def get_simplefin_transactions(account_id, start_date)
    query = <<-SQL
      SELECT plaid_id FROM #{@entries_table}
      WHERE account_id = $1
      AND plaid_id IS NOT NULL
      AND date >= (TO_TIMESTAMP($2)::DATE)
    SQL
  
    execute(query, [account_id, start_date])
  end

  def entry_exists?(account_id, date, type, name = nil)
    query = <<~SQL
      SELECT id FROM #{@entries_table}
      WHERE account_id = $1 AND date = (TO_TIMESTAMP($2)::DATE) AND entryable_type = $3
    SQL

    if name
      query += " AND name = $4 LIMIT 1"
      execute(query, [account_id, date, type, name]).first
    else
      query += " LIMIT 1"
      execute(query, [account_id, date, type]).first
    end
  end  

  def upsert_account_valuation(account_id, simplefin_account)
    valuation_uuid = SecureRandom.uuid
    amount = simplefin_account.dig("balance")
    currency = simplefin_account.dig("currency")
    date = simplefin_account.dig("balance-date")
  
    # Check if a row exists with the same account_id and date
    existing_entry = entry_exists?(account_id, date, @valuation_key)
  
    if existing_entry
      # Update existing row
        
      Rails.logger.info "Found existing valuation"

      valuation_uuid = existing_entry["id"]
      update_query = <<-SQL
        UPDATE #{@entries_table}
        SET amount = $1, updated_at = NOW()
        WHERE id = $2;
      SQL
      execute(update_query, [amount, valuation_uuid])

      # also update valuations timestamp
      valuation_update_query = <<-SQL
        UPDATE #{@valuations_table}
        SET updated_at = NOW()
        WHERE id = $1;
      SQL
      execute(valuation_update_query, [valuation_uuid])
    else
      # Insert new row

      Rails.logger.info "Adding a Balance Update..."

      insert_query = <<-SQL
        INSERT INTO #{@entries_table} (
          account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, (TO_TIMESTAMP($6)::DATE), 'Balance Update', NOW(), NOW()
        );
      SQL
      execute(insert_query, [account_id, @valuation_key, valuation_uuid, amount, currency, date])

      insert_valuation_query = <<-SQL
        INSERT INTO #{@valuations_table} (
          id, created_at, updated_at
        ) VALUES (
          $1, NOW(), NOW()
        );
      SQL
      execute(insert_valuation_query, [valuation_uuid])
    end
  end
  
  def new_transaction(account_id, amount, short_date, display_name, simplefin_txn_id, currency, one_time)
    transaction_uuid = SecureRandom.uuid
    adjusted_amount = BigDecimal(amount.to_s) * -1
    excluded = (one_time == true)
  
    # Insert the entries entry
    query = <<-SQL
      INSERT INTO #{@entries_table} (
        account_id, entryable_type, entryable_id, amount, currency, date, name, created_at, updated_at, plaid_id, excluded
      ) VALUES (
        $1, $2, $3, $4, $5, (TO_TIMESTAMP($6)::DATE), $7, NOW(), NOW(), $8, $9
      );
    SQL
    execute(query, [account_id, @transaction_key, transaction_uuid, adjusted_amount, currency, short_date, display_name, simplefin_txn_id, excluded])
  
    # Insert the transaction entry
    query = <<-SQL
      INSERT INTO #{@transactions_table} (
        id, created_at, updated_at
      ) VALUES (
        $1, NOW(), NOW()
      );
    SQL
    execute(query, [transaction_uuid])
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
      raise e
    end
  end

end