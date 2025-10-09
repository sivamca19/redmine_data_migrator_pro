# Consistent error handling service for data migration operations
class ErrorHandlerService
  class << self
    def handle_with_logging(operation_name, logger: Rails.logger)
      yield
    rescue StandardError => e
      log_error(operation_name, e, logger)
      raise
    end

    def handle_migration_error(migration, operation_name, error)
      error_message = "#{operation_name} failed: #{error.message}"

      migration.update!(
        status: 'failed',
        error_summary: error_message,
        processing_log: build_error_log(migration, operation_name, error)
      )

      Rails.logger.error "Migration #{migration.id} - #{error_message}"
      Rails.logger.error error.backtrace.join("\n") if error.backtrace

      false
    end

    def handle_file_operation_error(file_path, operation, error)
      cleanup_file(file_path) if file_path && File.exist?(file_path)
      Rails.logger.error "File #{operation} error: #{error.message}"
      raise
    end

    def safe_file_operation(file_path)
      yield
    rescue StandardError => e
      handle_file_operation_error(file_path, 'operation', e)
    end

    def validation_error_messages(model)
      return [] unless model.respond_to?(:errors) && model.errors.any?

      model.errors.full_messages
    end

    private

    def log_error(operation, error, logger)
      logger.error "#{operation} failed: #{error.message}"
      logger.error error.backtrace.join("\n") if error.backtrace
    end

    def build_error_log(migration, operation, error)
      current_log = migration.processing_log || ""
      "#{current_log}\n#{Time.current}: #{operation} failed - #{error.message}"
    end

    def cleanup_file(file_path)
      File.delete(file_path)
      Rails.logger.info "Cleaned up file: #{file_path}"
    rescue StandardError => cleanup_error
      Rails.logger.warn "Failed to cleanup file #{file_path}: #{cleanup_error.message}"
    end
  end
end