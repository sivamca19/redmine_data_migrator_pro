# Active Job adapter for background processing
module JobProcessors
  class ActiveJobAdapter < BaseAdapter
    class << self
      def queue_migration(migration_id)
        return unless active_job_available?

        migration = DataMigration.find(migration_id)
        migration.update!(
          status: 'processing',
          processing_log: (migration.processing_log || "") + "\nQueued for Active Job processing at #{Time.current}"
        )

        DataMigrationJob.perform_later(migration_id)
        log_job_queued('Migration', migration_id)
      end

      def queue_cleanup
        return unless active_job_available?

        DataMigrationCleanupJob.perform_later
        log_job_queued('Cleanup')
      end

      def status_info
        unless active_job_available?
          return {
            processor: 'Active Job',
            status: 'unavailable',
            details: 'ActiveJob not available (requires Rails 4.2+)'
          }
        end

        {
          processor: 'Active Job',
          description: 'Rails built-in job framework',
          status: 'ready',
          details: active_job_details,
          pending_migrations: DataMigration.where(status: 'processing').count
        }
      end

      private

      def active_job_available?
        defined?(ActiveJob)
      end

      def active_job_details
        return 'Details unavailable' unless active_job_available?

        adapter_name = ActiveJob::Base.queue_adapter.class.name.demodulize rescue 'Unknown'
        "Using #{adapter_name} adapter"
      end
    end
  end

  # Job classes for Active Job
  if defined?(ActiveJob)
    class DataMigrationJob < ActiveJob::Base
      queue_as :data_migration

      def perform(migration_id)
        migration = DataMigration.find(migration_id)
        processor = DataMigrationProcessor.new(migration)
        processor.process
      rescue StandardError => e
        Rails.logger.error "Active Job migration processing failed for #{migration_id}: #{e.message}"
        raise
      end
    end

    class DataMigrationCleanupJob < ActiveJob::Base
      queue_as :data_migration_cleanup

      def perform
        cleanup_days = Setting.plugin_redmine_data_migrator_pro&.dig('cleanup_days')&.to_i || 30
        old_migrations = DataMigration.where('created_at < ?', cleanup_days.days.ago)
                                     .where(status: ['completed', 'failed'])

        count = 0
        old_migrations.each do |migration|
          migration.delete_file if migration.file_exists?
          migration.destroy
          count += 1
        end

        Rails.logger.info "Cleaned up #{count} old migrations via Active Job"
      rescue StandardError => e
        Rails.logger.error "Active Job cleanup failed: #{e.message}"
        raise
      end
    end
  end
end