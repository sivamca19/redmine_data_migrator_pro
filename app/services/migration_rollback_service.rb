class MigrationRollbackService
  attr_reader :migration, :deleted_count

  def initialize(migration)
    @migration = migration
    @deleted_count = 0
  end

  def perform_rollback
    return false unless can_rollback?

    begin
      delete_imported_issues
      reset_migration_state
      log_rollback_completion
      true
    rescue => e
      Rails.logger.error "Error during rollback of migration #{@migration.id}: #{e.message}"
      false
    end
  end

  def can_rollback?
    @migration.completed? && @migration.imported_issue_ids.present?
  end

  private

  def delete_imported_issues
    return unless @migration.imported_issue_ids.present?

    issue_ids = @migration.imported_issue_ids.split(',').map(&:to_i)

    issue_ids.each do |issue_id|
      delete_single_issue(issue_id)
    end
  end

  def delete_single_issue(issue_id)
    issue = Issue.find(issue_id)
    if issue.destroy
      @deleted_count += 1
      Rails.logger.info "Deleted issue #{issue_id} during migration rollback"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Issue #{issue_id} not found during rollback (may have been deleted already)"
  rescue => e
    Rails.logger.error "Error deleting issue #{issue_id} during rollback: #{e.message}"
  end

  def reset_migration_state
    @migration.update!(
      status: 'uploaded',
      processed_rows: 0,
      success_rows: 0,
      error_rows: 0,
      error_summary: nil,
      error_report: nil,
      imported_issue_ids: nil,
      processed_at: nil,
      processing_log: build_rollback_log
    )
  end

  def build_rollback_log
    current_log = @migration.processing_log || ""
    "#{current_log}\n--- ROLLED BACK AT #{Time.current} - Deleted #{@deleted_count} issues ---"
  end

  def log_rollback_completion
    Rails.logger.info "Migration #{@migration.id} rolled back successfully. Deleted #{@deleted_count} issues."
  end
end