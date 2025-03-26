#!/usr/bin/env ruby
require 'dotenv/load'
require_relative "../lib/simplefin_to_maybe"

Dotenv.load(File.expand_path('../.env', __dir__))

puts ""
puts "Welcome to the SimpleFIN to Maybe transaction synchronizer!"
puts ""

# init a MaybeClient and get accounts for the family
puts "Connecting to Maybe PostgreSQL..."
maybe_client = SimpleFINToMaybe::MaybeClient.new

family = make_selection(maybe_client.get_families, "name", "Please select your Maybe family instance:", auto_select_single: true)
family_id = family.dig("id")
return if family_id.nil?
puts "Connected to family #{family.dig("name")} (#{family_id})"

maybe_accounts = maybe_client.get_accounts(family_id)

# v0.0.1 restriction:  Only handle strictly transaction-based types (no holdings/trades)
allowed_types = ["Depository", "CreditCard", "Loan", "Investment"]
maybe_accounts = maybe_accounts.select { |account| allowed_types.include?(account.dig("accountable_type")) }

puts "Found #{maybe_accounts.length} Maybe account(s)!"
return if 0 == maybe_accounts.length

# init a SimpleFINClient and get all accounts
puts ""
puts "Connecting to SimpleFIN Bridge..."
simplefin_client = SimpleFINToMaybe::SimpleFINClient.new

simplefin_accounts = simplefin_client.get_all_accounts

skip_accounts = (ENV['EXCLUDED_SIMPLEFIN_ACCOUNT_IDS'] || "").split(",")
simplefin_accounts = simplefin_accounts.reject { |account| skip_accounts.include?(account.dig("id").to_s) }

puts "Found #{simplefin_accounts.length} SimpleFIN account(s)!"
return if 0 == simplefin_accounts.length
puts "Beginning account enumeration..."

# loop through all simplefin accounts
if simplefin_accounts.is_a?(Array)
  simplefin_accounts.each do |simplefin_account|

    simplefin_account_uuid = simplefin_account.dig("id")
    simplefin_id = simplefin_account_uuid.to_s.sub(/^ACT-/, "")
    simplefin_name = simplefin_account.dig("name")
    simplefin_display_name = "#{simplefin_account.dig("org", "name")}: #{simplefin_name}"

    puts ""
    puts "---"
    puts "Evaluating SimpleFIN account #{simplefin_display_name} (#{simplefin_account_uuid})"

    # check if we've already associated the SimpleFIN account with a Maybe account
    maybe_account = maybe_accounts.find { |account| account["import_id"] == simplefin_id }
    
    # if not, create a new simplefin account in Maybe and associate it with the Maybe account
    if maybe_account.nil?
      
      unmatched_maybe_accounts = maybe_accounts.select { |account| account["import_id"].nil? }
      if unmatched_maybe_accounts.empty?
        puts ""
        puts "All Maybe accounts have an associated SimpleFIN account; Create new accounts in Maybe to continue. Quitting!"
        break
      end

      puts "No associated Maybe account found! Please associate this SimpleFIN account to one of the following Maybe accounts..."
      account_row = make_selection(unmatched_maybe_accounts, "name", "Please select a Maybe account to associate '#{simplefin_display_name}':")

      next if account_row.nil?  # skip iteration if we didn't make an association

      maybe_account_id = maybe_client.new_simplefin_import(account_row, simplefin_id)
      maybe_accounts = maybe_client.get_accounts(family_id)  # update accounts so the unmatched_maybe_accounts reflects new associations
      maybe_account = account_row
    else
      maybe_account_id = maybe_account.dig("id")
      puts "Found associated Maybe account: #{maybe_account.dig("name")} (#{maybe_account_id})"
    end

    # for investment accounts, only update balance (simplefin trade / holdings still WIP)
    if maybe_account["accountable_type"] == "Investment"
        maybe_client.upsert_account_valuation(maybe_account_id, simplefin_account)
      next
    end

    # get all simplefin transactions for the calendar month
    puts ""
    puts "Gathering transactions since #{get_lookback_date()}..."
    start_date_epoch = get_lookback_date(epoch: true)
    simplefin_transactions = simplefin_client.get_all_transactions(simplefin_account_uuid, start_date_epoch)
    puts "Found #{simplefin_transactions.length} SimpleFIN transaction(s)!"

    # get all transactions we've already sync'd into maybe
    start_date_mmddYY = get_lookback_date(tz: "UTC")
    existing_maybe_transactions = maybe_client.get_simplefin_transactions(maybe_account_id, start_date_mmddYY)
    puts "Found #{existing_maybe_transactions.length} Maybe transaction(s) for this account!"

    # loop through all simplefin transactions
    if simplefin_transactions.length == existing_maybe_transactions.length  # if they're the same, skip
      puts "Skipping to next account..."
    else
      if simplefin_transactions.is_a?(Array)
        puts "Inserting transaction(s)..."
        simplefin_transactions.each do |simplefin_transaction|
          transaction_id = simplefin_transaction.dig("id")

          # if this transaction hasn't been synced yet, create a new transaction in Maybe
          if existing_maybe_transactions.none? { |t| t["plaid_id"] == transaction_id }
            amount = simplefin_transaction.dig("amount")
            short_date = convert_timestamp_to_mmddyyyy(simplefin_transaction.dig("posted"))
            display_name = simplefin_transaction.dig("description")
            maybe_client.new_transaction(maybe_account_id, amount, short_date, display_name, transaction_id)
          end
        end
      end
    end
  end
end

# Close connection
maybe_client.close
puts ""
puts "Finished synchronization!"
