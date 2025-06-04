json.extract! integration_query, :id, :account_id, :integration_id, :name, :query_params, :response_data, :last_executed_at, :created_at, :updated_at
json.url integration_query_url(integration_query, format: :json)
