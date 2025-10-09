# Main service for managing background job processing across different adapters
class BackgroundJobService
  SUPPORTED_PROCESSORS = %w[cron delayed_job sidekiq active_job].freeze

  class << self
    def current_processor
      Setting.plugin_redmine_data_migrator_pro&.dig('job_processor') || 'cron'
    end

    def queue_migration(migration_id)
      adapter.queue_migration(migration_id)
    rescue StandardError => e
      Rails.logger.error "Failed to queue migration #{migration_id}: #{e.message}"
      fallback_to_cron(migration_id)
    end

    def queue_cleanup
      adapter.queue_cleanup
    rescue StandardError => e
      Rails.logger.error "Failed to queue cleanup: #{e.message}"
      # Cleanup can be handled by cron fallback
    end

    def processor_status
      adapter.status_info
    rescue StandardError => e
      {
        processor: current_processor,
        status: 'error',
        details: "Error getting status: #{e.message}"
      }
    end

    def available_processors
      processors = []

      SUPPORTED_PROCESSORS.each do |processor_type|
        case processor_type
        when 'cron'
          processors << {
            key: 'cron',
            name: 'Cron Jobs',
            description: 'Traditional cron-based processing',
            available: true
          }
        when 'delayed_job'
          processors << {
            key: 'delayed_job',
            name: 'Delayed Job',
            description: 'Database-backed job queue',
            available: defined?(Delayed::Job)
          }
        when 'sidekiq'
          processors << {
            key: 'sidekiq',
            name: 'Sidekiq',
            description: 'Redis-backed job queue',
            available: defined?(Sidekiq)
          }
        when 'active_job'
          processors << {
            key: 'active_job',
            name: 'Active Job',
            description: 'Rails built-in job framework',
            available: defined?(ActiveJob)
          }
        end
      end

      processors
    end

    def supported_processor?(processor_type)
      SUPPORTED_PROCESSORS.include?(processor_type.to_s)
    end

    def validate_processor_configuration
      processor = current_processor

      case processor
      when 'delayed_job'
        return { valid: false, error: 'delayed_job gem not installed' } unless defined?(Delayed::Job)
      when 'sidekiq'
        return { valid: false, error: 'sidekiq gem not installed' } unless defined?(Sidekiq)
      when 'active_job'
        return { valid: false, error: 'ActiveJob not available' } unless defined?(ActiveJob)
      end

      { valid: true, processor: processor }
    end

    private

    def adapter
      case current_processor
      when 'cron'
        JobProcessors::CronAdapter
      when 'delayed_job'
        JobProcessors::DelayedJobAdapter
      when 'sidekiq'
        JobProcessors::SidekiqAdapter
      when 'active_job'
        JobProcessors::ActiveJobAdapter
      else
        Rails.logger.warn "Unknown processor '#{current_processor}', falling back to cron"
        JobProcessors::CronAdapter
      end
    end

    def fallback_to_cron(migration_id)
      Rails.logger.warn "Falling back to cron processing for migration #{migration_id}"
      JobProcessors::CronAdapter.queue_migration(migration_id)
    end
  end
end