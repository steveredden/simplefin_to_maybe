#!/usr/bin/env ruby
require 'dotenv/load'
require_relative "../lib/simplefin_to_maybe"

Dotenv.load(File.expand_path('../.env', __dir__))

puts ""
puts "Welcome to SimpleFINToMaybe CLI!"
puts ""

# init a MaybeClient and get accounts for the family
puts "Connecting to Maybe PostgreSQL..."
maybe_client = SimpleFINToMaybe::MaybeClient.new

family = make_selection(maybe_client.get_families, "name", "Please select your Maybe family instance:")
family_id = family.dig("id")
return if family_id.nil?

maybe_accounts = maybe_client.get_accounts(family_id)
puts "Found #{maybe_accounts.length} Maybe account(s)!"

# init a SimpleFINClient and get all accounts
puts "Connecting to SimpleFIN Bridge..."
simplefin_client = SimpleFINToMaybe::SimpleFINClient.new

simplefin_accounts = simplefin_client.get_all_accounts
puts "Found #{simplefin_accounts.length} SimpleFIN account(s)!"

# loop through all simplefin accounts
if simplefin_accounts.is_a?(Array)
  simplefin_accounts.each do |simplefin_account|

    simplefin_account_uuid = simplefin_account.dig("id")
    simplefin_name = simplefin_account.dig("name")
    simplefin_display_name = "#{simplefin_account.dig("org", "name")}: #{simplefin_name}"

    puts "---"
    puts "Evaluating SimpleFIN account #{simplefin_display_name} (#{simplefin_account_uuid})"

    # check if we've already associated the SimpleFIN account with a Maybe account
    maybe_account = maybe_accounts.find { |account| account["simplefin_account_id"] == simplefin_account_uuid }
    
    # if not, create a new simplefin account in Maybe and associate it with the Maybe account
    if maybe_account.nil?
      
      unmatched_maybe_accounts = maybe_accounts.select { |account| account["simplefin_account_id"].nil? }
      if unmatched_maybe_accounts.empty?
        puts "All Maybe accounts have an associated SimpleFIN account; Create new accounts in Maybe to continue!"
        break
      end

      puts "No associated Maybe account found! Please associate this SimpleFIN account to one of the following Maybe accounts..."
      account_row = make_selection(unmatched_maybe_accounts, "name", "Please select a Maybe account to associate '#{simplefin_display_name}':")

      next if account_row.nil?  # skip iteration if we didn't make an association
        maybe_account_id = maybe_client.new_simplefin_account(account_row, simplefin_account)
        maybe_accounts = maybe_client.get_accounts(family_id)  # update accounts so the unmatched_maybe_accounts reflects new associations
    else
      maybe_account_id = maybe_account.dig("id")
      puts "Found associated Maybe account: #{maybe_account.dig("name")} (#{maybe_account_id})"
    end
  
    # get all simplefin transactions for the calendar month
    puts "Gathering transactions since #{get_first_of_month()}..."
    start_date_epoch = get_first_of_month(epoch: true)
    simplefin_transactions = simplefin_client.get_all_transactions(simplefin_account_uuid, start_date_epoch)
    puts "Found #{simplefin_transactions.length} SimpleFIN transaction(s)!"

    # get all transactions we've already sync'd into maybe
    start_date_mmddYY = get_first_of_month()
    existing_maybe_transactions = maybe_client.get_simplefin_tx_entries(maybe_account_id, start_date_mmddYY)
    puts "Found #{existing_maybe_transactions.length} Maybe transaction(s) for this account!"

    # loop through all simplefin transactions
    if simplefin_transactions.length != existing_maybe_transactions.length  # if they're the same, skip
      if simplefin_transactions.is_a?(Array)
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
puts "Finished synchronization!"
