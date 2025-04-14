# app/controllers/settings_controller.rb
require 'net/http'
require 'uri'

class SettingsController < ApplicationController
  before_action :set_setting, only: [:update]

  # Display all settings
  def index
    @settings = Setting.all
    @good_jobs = GoodJob::Job.all
  end

  # Update setting in the database
  def update
    if @setting.update(setting_params)
      render json: { success: true, value: @setting.value }
    else
      render json: { success: false, errors: @setting.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def test_simplefin

    username = Setting.find_by(key: 'simplefin_username')&.value
    password = Setting.find_by(key: 'simplefin_password')&.value

    if username.blank? || password.blank?
      Rails.logger.warn "Missing SimpleFIN username or password!"
      render plain: "Username or password not set."
    else
      simplefin_client = SimplefinClient.new(username, password)
      Rails.logger.info "Starting SimpleFIN retrieval of /accounts"
      response = simplefin_client.get_accounts
  
      if response[:success]
        Rails.logger.info "Succesfully retrieved SimpleFIN"
        output = ["\nSuccess!"]
        response[:response].dig("errors")&.each do |warning|
          output << "  Warning: #{warning}"
        end
        found_simplefin_accounts = response[:response].dig("accounts") || []
        cache_accounts(found_simplefin_accounts, "simplefin")
        remove_nonexistant_accounts(found_simplefin_accounts, "simplefin")
        render json: { output: output.join("\n"), account_count: found_simplefin_accounts.length }
      else
        output = ["\nError during retrieval: [#{response[:status_code]}]"]
        response[:response].dig("errors")&.each do |warning|
          output << "  #{warning}"
        end
        output = output.join(" ")
        Rails.logger.error output
        render json: { output: output, account_count: 0 }
      end
    end
  end

  def test_maybe
    maybe_client = MaybeClientService.connect

    if maybe_client
      output = ["\nSuccess!"]
      found_maybe_accounts = maybe_client.get_accounts() || []
      maybe_client.close
      cache_accounts(found_maybe_accounts, "maybe")
      remove_nonexistant_accounts(found_maybe_accounts, "maybe")
      render json: { output: output.join("\n"), account_count: found_maybe_accounts.length }
    else
      maybe_client.close
      render json: { output: maybe_client.error_message, account_count: 0 }
    end
  end

  def add_institution_icons

    simplefin_client, maybe_client = init_sf_and_maybe

    return if simplefin_client.nil? or maybe_client.nil?

    Linkage.all.each do |link|
      simplefin_response = simplefin_client.get_account(Account.find_by(id: link.simplefin_account_id).identifier)
      if simplefin_response[:success]
        simplefin_account = simplefin_response.dig(:response, "accounts", 0)
        maybe_account = maybe_client.get_account(Account.find_by(id: link.maybe_account_id).identifier)
        Rails.logger.info maybe_account.inspect
        if maybe_account['plaid_id'].nil?
          maybe_client.new_plaid_account(maybe_account, simplefin_account)
        end
      end
    end
  end

  def remove_institution_icons
    maybe_client = MaybeClientService.connect
    if maybe_client
      Linkage.all.each do |link|
        maybe_account = maybe_client.get_account(Account.find_by(id: link.maybe_account_id).identifier)
      end
    end
  end

  private

  def init_sf_and_maybe
    username = Setting.find_by(key: 'simplefin_username')&.value
    password = Setting.find_by(key: 'simplefin_password')&.value

    if username.blank? || password.blank?
      Rails.logger.warn "Missing SimpleFIN username or password!"
      render plain: "Username or password not set."
      return nil, nil
    end

    simplefin_client = SimplefinClient.new(username, password)

    maybe_client = MaybeClientService.connect
    if !maybe_client
      maybe_client.close
      return nil, nil
    end

    return simplefin_client, maybe_client
  end

  def cache_accounts(accounts, account_type)

    allowed_maybe_types = ["Depository", "CreditCard", "Loan", "Investment"]

    accounts.each do |account_data|
      if account_type == "simplefin"
        identifier = account_data.dig("id")
        display_name = "#{account_data.dig("org", "name")} - #{account_data.dig("name")}"
        accountable_type = nil
        family_id = nil
        currency = account_data.dig("currency")
      elsif account_type == "maybe"
        accountable_type = account_data.dig("accountable_type")
        next unless allowed_maybe_types.include?(accountable_type.to_s)
        identifier = account_data.dig("id")
        display_name = account_data.dig("name")
        family_id = account_data.dig("family_id")
        currency = account_data.dig("currency")
      else
        raise ArgumentError, "Invalid account_type: #{account_type}"
      end
      Account.find_or_create_by(account_type: account_type, identifier: identifier) do |account|
        account.display_name = display_name
        account.accountable_type = accountable_type if accountable_type
        account.maybe_family_id = family_id if family_id
        account.currency = currency if currency
      end
    end
  end

  def remove_nonexistant_accounts(accounts, account_type)
    account_ids = accounts.map { |account| account.dig("id") }
    Account.where(account_type: account_type).where.not(identifier: account_ids)
      .reject(&:in_use?).each(&:destroy)
  end

  def set_setting
    # Find the setting by its key
    @setting = Setting.find_by(key: params[:id])  # Assuming `id` refers to the setting key
    if @setting.nil?
      render json: { success: false, error: 'Setting not found' }, status: :not_found
    end
  end

  # Strong parameters for updating setting
  def setting_params
    params.require(:setting).permit(:value)
  end
end
