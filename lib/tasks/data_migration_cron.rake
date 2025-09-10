namespace :data_migration do
  desc 'Process pending data migrations (run via cron)'
  task process_pending: :environment do
    begin
      Rails.logger.info 'Starting cron job: Processing pending data migrations'
      CronMigrationService.process_pending_migrations
      Rails.logger.info 'Completed cron job: Processing pending data migrations'
    rescue => e
      Rails.logger.error "Cron job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  desc 'Clean up old completed/failed migrations (run via cron)'
  task cleanup_old: :environment do
    begin
      Rails.logger.info 'Starting cron job: Cleaning up old migrations'
      CronMigrationService.cleanup_old_migrations
      Rails.logger.info 'Completed cron job: Cleaning up old migrations'
    rescue => e
      Rails.logger.error "Cleanup cron job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  desc 'Process a specific migration by ID'
  task :process_single, [:migration_id] => :environment do |t, args|
    migration_id = args[:migration_id]
    
    if migration_id.blank?
      puts 'Please provide a migration ID: rake data_migration:process_single[123]'
      exit 1
    end

    begin
      migration = DataMigration.find(migration_id)
      puts "Processing migration #{migration_id}..."
      
      success = CronMigrationService.process_single_migration(migration)
      
      if success
        puts "Migration #{migration_id} completed successfully"
      else
        puts "Migration #{migration_id} failed"
        exit 1
      end
    rescue ActiveRecord::RecordNotFound
      puts "Migration with ID #{migration_id} not found"
      exit 1
    rescue => e
      puts "Error processing migration #{migration_id}: #{e.message}"
      exit 1
    end
  end

  desc 'Show status of all recent migrations'
  task status: :environment do
    migrations = DataMigration.order(created_at: :desc).limit(10)
    
    puts "\nRecent Data Migrations:"
    puts "ID".ljust(5) + "Status".ljust(12) + "Source".ljust(10) + "File".ljust(30) + "Created"
    puts "-" * 80
    
    migrations.each do |migration|
      puts migration.id.to_s.ljust(5) +
           migration.status.ljust(12) +
           migration.source_type.ljust(10) +
           (migration.filename || 'N/A')[0, 29].ljust(30) +
           migration.created_at.strftime('%Y-%m-%d %H:%M')
    end
    
    puts "\nPending migrations: #{DataMigration.where(status: 'processing').count}"
    puts "Failed migrations: #{DataMigration.where(status: 'failed').count}"
  end
end