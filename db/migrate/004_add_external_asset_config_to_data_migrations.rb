class AddExternalAssetConfigToDataMigrations < ActiveRecord::Migration[6.1]
  def change
    add_column :data_migrations, :external_asset_config_id, :integer
  end
end