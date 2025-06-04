class CreateIntegrationQueries < ActiveRecord::Migration[7.1]
  def change
    create_table :integration_queries, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, null: false, foreign_key: true
      t.string :name
      t.jsonb :query_params
      t.jsonb :response_data
      t.datetime :last_executed_at

      t.timestamps
    end
  end
end
