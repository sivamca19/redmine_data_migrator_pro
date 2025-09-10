namespace :data_migration do
  desc 'Process pending data migrations'
  task :process => :environment do
    puts "Starting data migration processing at #{Time.current}"

    # Find migrations that are ready for processing
    pending_migrations = DataMigration.where(status: 'processing')
                                     .where('created_at > ?', 24.hours.ago) # Safety limit
                                     .order(:created_at)

    if pending_migrations.empty?
      puts "No pending migrations found"
      next
    end

    puts "Found #{pending_migrations.count} pending migration(s)"

    pending_migrations.each do |migration|
      puts "Processing migration ID: #{migration.id} (#{migration.filename})"

      begin
        processor = DataMigrationProcessor.new(migration)
        success = processor.process

        if success
          puts "✓ Migration #{migration.id} completed successfully"
          puts "  - Processed: #{processor.processed_count} rows"
          puts "  - Success: #{processor.success_count} rows"
          puts "  - Errors: #{processor.error_count} rows"
        else
          puts "✗ Migration #{migration.id} failed"
        end

      rescue => e
        puts "✗ Error processing migration #{migration.id}: #{e.message}"
        Rails.logger.error "Migration processing error: #{e.message}\n#{e.backtrace.join("\n")}"

        migration.update!(
          status: 'failed',
          error_summary: "Cron processing failed: #{e.message}",
          processing_log: (migration.processing_log || "") + "\nCron processing failed at #{Time.current}: #{e.message}"
        )
      end

      # Add delay between migrations to prevent system overload
      sleep 2
    end

    puts "Data migration processing completed at #{Time.current}"
  end

  desc 'Clean up old migration files and records'
  task :cleanup => :environment do
    puts "Starting cleanup of old migration data at #{Time.current}"

    # Clean up migrations older than 30 days
    old_migrations = DataMigration.where('created_at < ?', 30.days.ago)

    old_migrations.each do |migration|
      begin
        # Clean up stored files
        if migration.processing_options&.dig('stored_file_path').present?
          stored_file = migration.processing_options['stored_file_path']
          if File.exist?(stored_file)
            File.delete(stored_file)
            puts "Deleted file: #{stored_file}"
          end
        end

        # Delete migration record
        migration.destroy
        puts "Deleted migration record: #{migration.id}"

      rescue => e
        puts "Error cleaning up migration #{migration.id}: #{e.message}"
      end
    end

    puts "Cleanup completed at #{Time.current}"
  end

  desc 'Reset stuck migrations'
  task :reset_stuck => :environment do
    puts "Resetting stuck migrations at #{Time.current}"

    # Find migrations that have been processing for more than 2 hours
    stuck_migrations = DataMigration.where(status: 'processing')
                                   .where('updated_at < ?', 2.hours.ago)

    stuck_migrations.each do |migration|
      migration.update!(
        status: 'failed',
        error_summary: "Migration timed out - stuck in processing state",
        processing_log: (migration.processing_log || "") + "\nReset as stuck at #{Time.current}"
      )
      puts "Reset stuck migration: #{migration.id}"
    end

    puts "Reset #{stuck_migrations.count} stuck migration(s)"
  end

  desc 'Show migration status'
  task :status => :environment do
    puts "\n=== Data Migration Status ==="

    %w[uploaded processing completed failed cancelled].each do |status|
      count = DataMigration.where(status: status).count
      puts "#{status.capitalize}: #{count}"
    end

    # Show recent activity
    recent = DataMigration.where('created_at > ?', 24.hours.ago).order(:created_at)

    if recent.any?
      puts "\n=== Recent Activity (24h) ==="
      recent.each do |migration|
        puts "#{migration.created_at.strftime('%H:%M')} - ID:#{migration.id} - #{migration.status} - #{migration.filename}"
      end
    end

    # Show currently processing
    processing = DataMigration.where(status: 'processing')

    if processing.any?
      puts "\n=== Currently Processing ==="
      processing.each do |migration|
        progress = migration.processed_rows.to_i > 0 ?
          "(#{migration.processed_rows}/#{migration.total_rows} rows)" :
          "(#{migration.total_rows} total rows)"

        puts "ID:#{migration.id} - #{migration.filename} #{progress}"
      end
    end

    puts ""
  end
end