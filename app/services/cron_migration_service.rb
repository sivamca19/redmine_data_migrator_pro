# Service for processing data migrations via cron jobs
# Handles batch processing and cleanup of migration records
class CronMigrationService
  def self.process_pending_migrations
    migrations = DataMigration.where(status: 'processing')
                             .where('created_at > ?', 24.hours.ago)
                             .order(:created_at)

    Rails.logger.info "Processing #{migrations.count} pending migrations via cron"

    migrations.each do |migration|
      process_single_migration(migration)
    end
  end

  def self.process_single_migration(migration)
    Rails.logger.info "Starting cron processing for migration #{migration.id}"

    processor = DataMigrationProcessor.new(migration)
    success = processor.process

    if success
      Rails.logger.info "Migration #{migration.id} completed successfully via cron"
    else
      Rails.logger.error "Migration #{migration.id} failed during cron processing"
    end

    success
  rescue StandardError => e
    ErrorHandlerService.handle_migration_error(migration, 'Cron processing', e)
  end

  def self.cleanup_old_migrations
    old_migrations = DataMigration.where('created_at < ?', 30.days.ago)
                                 .where(status: ['completed', 'failed'])

    Rails.logger.info "Cleaning up #{old_migrations.count} old migrations"

    old_migrations.each do |migration|
      begin
        migration.delete_file if migration.file_exists?
        migration.destroy
        Rails.logger.info "Cleaned up old migration #{migration.id}"
      rescue StandardError => e
        Rails.logger.error "Error cleaning up migration #{migration.id}: #{e.message}"
      end
    end
  end
end