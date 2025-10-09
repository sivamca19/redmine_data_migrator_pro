# Sidekiq adapter for background processing
module JobProcessors
  class SidekiqAdapter < BaseAdapter
    class << self
      def queue_migration(migration_id)
        return unless sidekiq_available?

        migration = DataMigration.find(migration_id)
        migration.update!(
          status: 'processing',
          processing_log: (migration.processing_log || "") + "\nQueued for Sidekiq processing at #{Time.current}"
        )

        DataMigrationWorker.perform_async(migration_id)
        log_job_queued('Migration', migration_id)
      end

      def queue_cleanup
        return unless sidekiq_available?

        DataMigrationCleanupWorker.perform_async
        log_job_queued('Cleanup')
      end

      def status_info
        unless sidekiq_available?
          return {
            processor: 'Sidekiq',
            status: 'unavailable',
            details: 'sidekiq gem not installed'
          }
        end

        {
          processor: 'Sidekiq',
          description: 'Redis-backed job queue',
          status: 'ready',
          details: sidekiq_statistics,
          pending_migrations: DataMigration.where(status: 'processing').count
        }
      end

      private

      def sidekiq_available?
        defined?(Sidekiq)
      end

      def sidekiq_statistics
        return 'Statistics unavailable' unless sidekiq_available?

        stats = Sidekiq::Stats.new rescue nil
        return 'Redis connection error' unless stats

        "#{stats.enqueued} enqueued, #{stats.processed} processed, #{stats.failed} failed"
      end
    end
  end

  # Worker classes for Sidekiq
  if defined?(Sidekiq)
    class DataMigrationWorker
      include Sidekiq::Worker

      sidekiq_options queue: 'data_migration', retry: 3

      def perform(migration_id)
        migration = DataMigration.find(migration_id)
        processor = DataMigrationProcessor.new(migration)
        processor.process
      rescue StandardError => e
        Rails.logger.error "Sidekiq migration processing failed for #{migration_id}: #{e.message}"
        raise
      end
    end

    class DataMigrationCleanupWorker
      include Sidekiq::Worker

      sidekiq_options queue: 'data_migration_cleanup', retry: 2

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

        Rails.logger.info "Cleaned up #{count} old migrations via Sidekiq"
      rescue StandardError => e
        Rails.logger.error "Sidekiq cleanup failed: #{e.message}"
        raise
      end
    end
  end
end