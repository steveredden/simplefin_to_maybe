#lib/simplefil_to_maybe/simplefin_client.rb

require 'colorize'
require 'json'
require 'net/http'
require 'uri'

require_relative "utils"

module SimpleFINToMaybe
  class SimpleFINClient
    BASE_URL = "https://beta-bridge.simplefin.org/simplefin"  # SimpleFIN API base URL

    def initialize(username: ENV['SIMPLEFIN_USERNAME'], password: ENV['SIMPLEFIN_PASSWORD'])
      @username = username
      @password = password
    end

    # Helper method to make HTTP requests with basic authentication
    def invoke_request(endpoint, query_params = {})
      uri = URI.parse("#{BASE_URL}#{endpoint}")
      uri.query = URI.encode_www_form(query_params) unless query_params.empty?

      #puts "Requesting: #{uri}"

      # Perform HTTP request with basic authentication
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(@username, @password)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      handle_response(response)
    end

    # Method to fetch all accounts
    def get_all_accounts
      query_params = { "balances-only" => 1 }
      response = invoke_request("/accounts", query_params)
      return response.dig("accounts") || []
    end

    # Method to fetch all transactions for a specific account within a date range
    def get_single_account(account_id, start_date = get_first_of_month(epoch: true), end_date = get_epoch_of_tomorrow())
      query_params = {
        "start-date" => start_date,
        "end-date" => end_date,
        "account" => URI.encode_www_form_component(account_id)
      }
      response = invoke_request("/accounts", query_params)
      return response.dig("accounts", 0) || []
    end

    private

    # Handles API responses and errors
    def handle_response(response)
      case response.code.to_i
      when 200
        output = JSON.parse(response.body)
        output.dig("errors").each do |warnings|
          puts " - #{warnings}".colorize(:yellow)  #simplefin warnings
        end
        return output
      else
        raise "Error: #{response.code} - #{response.body}"
      end
    end
  end
end

def enrich_transaction_vs_trade(simplefin_account)
  holdings = simplefin_account.dig("holdings") || []
  transactions = simplefin_account.dig("transactions") || []

  return { trades: [], txs: [], redos: [] } unless holdings.is_a?(Array) && transactions.is_a?(Array)

  trades = []
  txs = []
  redos = []

  transactions.each do |tx|
    next unless tx.is_a?(Hash) && tx["description"] && tx["posted"]

    description = tx["description"].downcase

    # Match holdings based on description
    normalized_tx_desc = description
      .gsub(/^(buy|sell|dividend reinvest|reinvest)\s*\-\s*/i, '')
      .gsub(/\s+/, ' ')  #replace multiple spaces with a single space
      .strip
      .downcase

    holding = holdings.find do |h|
      h.is_a?(Hash) && h["description"] && normalized_tx_desc.include?(h["description"].downcase)
    end

    price = nil
    quantity = nil
    estimated_price = nil
    estimated_quantity = nil

    complete_trade = false

    if holding && tx["amount"].to_f.abs == holding["cost_basis"].to_f.abs
      price = holding["cost_basis"].to_f.abs / holding["shares"].to_f
      quantity = holding["shares"]
      complete_trade = true
    elsif (match = description.match(/reinvest at \$?(\d+\.\d+)\b/))
      price = match[1].to_f
      quantity = (tx["amount"].to_f.abs / price).round(4)
      complete_trade = true
    else
      if holding
        estimated_quantity = (holding["market_value"].to_f / holding["shares"].to_f) * (tx["amount"].to_f.positive? ? -1 : 1)
        estimated_price = estimated_quantity ? tx["amount"].to_f.abs / estimated_quantity : nil
      end
    end

    if description.include?("fee")
      txs << tx
    elsif description.include?("dividend") && (description.include?("payment") || tx["amount"].to_f > 0)   #a positive dividend is probably a deposit
      txs << tx
    elsif description.include?("dividend") && (description.include?("reinvest") || tx["amount"].to_f < 0)  #a negative divident is probably a reinvestment
      trades << {
        "id" => tx["id"],
        "posted" => tx["posted"],
        "ticker" => holding ? holding["symbol"] : nil,
        "amount" => tx["amount"],
        "description" => tx["description"],
        "quantity" => quantity,
        "price" => price
      }
    elsif complete_trade # Ensure we only add to `trades` if a matching holding exists
      trades << {
        "id" => tx["id"],
        "posted" => tx["posted"],
        "ticker" => holding["symbol"],
        "amount" => tx["amount"],
        "description" => tx["description"],
        "quantity" => quantity,
        "price" => price
      }
    else
      redos << {
        "id" => tx["id"],
        "posted" => tx["posted"],
        "ticker" => holding ? holding["symbol"] : nil,
        "amount" => tx["amount"],
        "description" => tx["description"],
        "quantity" => quantity,
        "price" => price
      }
    end
  end

  {
    "trades" => trades,
    "transactions" => txs,
    "redos" => redos
  }
end