# Base adapter for background job processors
module JobProcessors
  class BaseAdapter
    class << self
      def queue_migration(migration_id)
        raise NotImplementedError, 'Subclass must implement queue_migration'
      end

      def queue_cleanup
        raise NotImplementedError, 'Subclass must implement queue_cleanup'
      end

      def status_info
        raise NotImplementedError, 'Subclass must implement status_info'
      end

      protected

      def current_settings
        Setting.plugin_redmine_data_migrator_pro || {}
      end

      def log_job_queued(job_type, migration_id = nil)
        if migration_id
          Rails.logger.info "#{job_type} job queued for migration #{migration_id} via #{processor_name}"
        else
          Rails.logger.info "#{job_type} job queued via #{processor_name}"
        end
      end

      def processor_name
        self.name.demodulize.gsub('Adapter', '')
      end
    end
  end
end