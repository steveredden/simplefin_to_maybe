# app/lib/rentcast_client.rb

require 'json'
require 'net/http'
require 'uri'

class RentcastClient
  BASE_URL = "https://api.rentcast.io/v1/avm"  # rentcast.io API base URL

  def initialize(api_token)
    @api_token = api_token
  end

  # Method to fetch valuation
  def get_property_valuation(address, property_type, bedrooms, bathrooms, square_footage, comp_count)
    query_params = {
      "address" => URI.encode_www_form_component(address),
      "propertyType" => URI.encode_www_form_component(property_type),
      "bedrooms" => bedrooms,
      "bathrooms" => bathrooms,
      "squareFootage" => square_footage,
      "comp_count" => comp_count
    }
    invoke_request("/value", query_params)
  end

  private

  def invoke_request(endpoint, query_params = {})
    uri = URI.parse("#{BASE_URL}#{endpoint}")
    uri.query = URI.encode_www_form(query_params) unless query_params.empty?

    Rails.logger.info "Invoking HTTP GET on '#{uri}'"

    # Perform HTTP request with header authentication
    request = Net::HTTP::Get.new(uri)
    request["accept"] = 'application/json'
    request["X-Api-Key"] = @api_token

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
      Rails.logger.error("Rentcast API Error: #{response.code} - #{parsed_body}")
    end

    # Return a structured hash with status code, response body, and success flag
    {
      status_code: response.code.to_i,
      response: parsed_body,
      success: success
    }
  end
end
