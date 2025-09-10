class CreateExternalAssetConfigs < ActiveRecord::Migration[6.1]
  def change
    create_table :external_asset_configs do |t|
      t.string :name, null: false
      t.string :system_type, null: false
      t.integer :project_id, null: true
      t.string :base_url, null: false
      t.text :encrypted_credentials
      t.string :status, default: 'active'
      t.text :description
      t.text :additional_settings

      t.timestamps null: false
    end

    add_index :external_asset_configs, :name, unique: true
    add_index :external_asset_configs, :system_type
    add_index :external_asset_configs, :status
    add_index :external_asset_configs, [:system_type, :project_id]
  end
end