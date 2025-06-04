class Integration < ApplicationRecord
    has_many :integration_queries, dependent: :destroy
end
