# Delayed Job adapter for background processing
module JobProcessors
  class DelayedJobAdapter < BaseAdapter
    class << self
      def queue_migration(migration_id)
        return unless delayed_job_available?

        migration = DataMigration.find(migration_id)
        migration.update!(
          status: 'processing',
          processing_log: (migration.processing_log || "") + "\nQueued for Delayed Job processing at #{Time.current}"
        )

        DataMigrationJob.delay(queue: 'data_migration').perform(migration_id)
        log_job_queued('Migration', migration_id)
      end

      def queue_cleanup
        return unless delayed_job_available?

        DataMigrationCleanupJob.delay(queue: 'data_migration_cleanup').perform
        log_job_queued('Cleanup')
      end

      def status_info
        unless delayed_job_available?
          return {
            processor: 'Delayed Job',
            status: 'unavailable',
            details: 'delayed_job gem not installed'
          }
        end

        {
          processor: 'Delayed Job',
          description: 'Database-backed job queue',
          status: 'ready',
          details: job_statistics,
          pending_migrations: DataMigration.where(status: 'processing').count
        }
      end

      private

      def delayed_job_available?
        defined?(Delayed::Job)
      end

      def job_statistics
        return 'Statistics unavailable' unless delayed_job_available?

        total_jobs = Delayed::Job.count rescue 0
        failed_jobs = Delayed::Job.where('failed_at IS NOT NULL').count rescue 0

        "#{total_jobs} total jobs, #{failed_jobs} failed"
      end
    end
  end

  # Job classes for Delayed Job
  class DataMigrationJob
    def self.perform(migration_id)
      migration = DataMigration.find(migration_id)
      processor = DataMigrationProcessor.new(migration)
      processor.process
    rescue StandardError => e
      Rails.logger.error "Delayed Job migration processing failed for #{migration_id}: #{e.message}"
      raise
    end
  end

  class DataMigrationCleanupJob
    def self.perform
      cleanup_days = Setting.plugin_redmine_data_migrator_pro&.dig('cleanup_days')&.to_i || 30
      old_migrations = DataMigration.where('created_at < ?', cleanup_days.days.ago)
                                   .where(status: ['completed', 'failed'])

      old_migrations.each do |migration|
        migration.delete_file if migration.file_exists?
        migration.destroy
      end

      Rails.logger.info "Cleaned up #{old_migrations.count} old migrations via Delayed Job"
    rescue StandardError => e
      Rails.logger.error "Delayed Job cleanup failed: #{e.message}"
      raise
    end
  end
end