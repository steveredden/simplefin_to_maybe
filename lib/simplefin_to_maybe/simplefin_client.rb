#lib/simplefil_to_maybe/simplefin_client.rb

require 'net/http'
require 'json'
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
        output.dig("errors").each do |errorLine|
          puts errorLine
        end
        return output
      else
        raise "Error: #{response.code} - #{response.body}"
      end
    end
  end
end
