class AddExternalAssetConfigToDataMigrations < ActiveRecord::Migration[6.1]
  def change
    add_reference :data_migrations, :external_asset_config, null: true, foreign_key: true
    add_index :data_migrations, :external_asset_config_id
  end
end