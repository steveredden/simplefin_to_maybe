# app/lib/zillow_client.rb

require 'json'
require 'net/http'
require 'uri'

class ZillowClient
  BASE_URL = "https://api.bridgedataoutput.com/api/v2/zestimates_v2"  # zillow API base URL

  def initialize(server_token)
    @server_token = server_token
  end

  # Method to fetch valuation
  def get_property_valuation(address)
    query_params = {
      "access_token" => @server_token,
      "address" => address
    }
    invoke_request("/zestimates", query_params)
  end

  private

  def invoke_request(endpoint, query_params = {})
    uri = URI.parse("#{BASE_URL}#{endpoint}")
    uri.query = URI.encode_www_form(query_params) unless query_params.empty?

    Rails.logger.info "Invoking HTTP GET on '#{uri}'"

    # Perform HTTP request with header authentication
    request = Net::HTTP::Get.new(uri)
    request["accept"] = 'application/json'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 30) do |http|
      http.request(request)
    end

    handle_response(response)

  rescue StandardError => e
    Rails.logger.error("HTTP Request failed: #{e.message}")
    {
      status_code: nil,
      response: nil,
      success: false,
      error_message: e.message
    }
  end

  # Handles API responses and errors, returns structured data
  def handle_response(response)
    parsed_body = JSON.parse(response.body) rescue nil
    success = response.code.to_i == 200

    unless success
      Rails.logger.error("Zillow API Error: #{response.code} - #{parsed_body}")
    end

    # Return a structured hash with status code, response body, and success flag
    {
      status_code: response.code.to_i,
      response: parsed_body,
      success: success
    }
  end
end
