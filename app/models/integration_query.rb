class IntegrationQuery < ApplicationRecord
  belongs_to :account
  belongs_to :integration
end
