class AddAnalysisDataToDataMigrations < ActiveRecord::Migration[6.1]
  def change
    add_column :data_migrations, :analysis_data, :text
  end
end