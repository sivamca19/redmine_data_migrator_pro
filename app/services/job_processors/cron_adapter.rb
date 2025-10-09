# Cron-based job processor adapter - uses existing cron system
module JobProcessors
  class CronAdapter < BaseAdapter
    class << self
      def queue_migration(migration_id)
        migration = DataMigration.find(migration_id)
        migration.update!(
          status: 'processing',
          processing_log: (migration.processing_log || "") + "\nQueued for cron processing at #{Time.current}"
        )

        log_job_queued('Migration', migration_id)
      end

      def queue_cleanup
        # Cleanup is handled by cron job, no immediate action needed
        log_job_queued('Cleanup')
      end

      def status_info
        {
          processor: 'Cron',
          description: 'Jobs processed via cron scheduler',
          status: 'ready',
          details: 'Ensure cron jobs are configured properly',
          pending_migrations: DataMigration.where(status: 'processing').count
        }
      end

      def process_pending_migrations
        CronMigrationService.process_pending_migrations
      end

      def cleanup_old_migrations
        CronMigrationService.cleanup_old_migrations
      end
    end
  end
end