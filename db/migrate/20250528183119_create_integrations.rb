class CreateIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :integrations, id: :uuid do |t|
      t.string :name
      t.text :description
      t.jsonb :credentials

      t.timestamps
    end
  end
end
