class CreateDataMigrations < ActiveRecord::Migration[6.1]
  def change
    create_table :data_migrations do |t|
      t.integer :user_id, null: false
      t.integer :project_id, null: true
      t.string :source_type, null: false
      t.string :filename
      t.string :file_path
      t.integer :file_size
      t.text :description
      t.integer :status, default: 0
      t.integer :total_rows, default: 0
      t.integer :processed_rows, default: 0
      t.integer :success_rows, default: 0
      t.integer :error_rows, default: 0
      t.text :error_summary
      t.text :error_report
      t.text :detected_headers
      t.text :field_mapping
      t.text :processing_options
      t.text :imported_issue_ids
      t.datetime :processed_at
      t.text :processing_log

      t.timestamps
    end

    add_index :data_migrations, [:user_id, :created_at]
    add_index :data_migrations, :status
    add_index :data_migrations, :source_type
  end
end