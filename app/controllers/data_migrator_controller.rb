# Main controller for Data Migrator Pro plugin
# Handles file upload, field mapping, processing, and migration management
# Supports: Jira, ClickUp, Asana, Trello, Monday.com, and Custom formats
#
# Key features:
# - File upload and analysis (CSV, XLS, XLSX)
# - Intelligent field mapping with auto-detection
# - Cron-based processing for large files
# - Migration rollback capabilities
# - Attachment download from external URLs
#
# Processing flow:
# 1. Upload file -> FileUploadService
# 2. Analyze headers -> FileAnalyzerService
# 3. Map fields -> FieldMappingService
# 4. Queue for cron processing -> CronMigrationService
# 5. Process data -> DataMigrationProcessor
class DataMigratorController < ApplicationController
  before_action :require_admin
  before_action :find_migration, except: [:index, :upload, :history, :clear_history]

  def index
    @migrations = DataMigration.includes(:user, :project, :external_asset_config)
                              .recent
                              .limit(20)
    @migration = DataMigration.new
    @external_configs = ExternalAssetConfig.active.order(:name)
  end

  def upload
    uploaded_file = params[:data_migration][:file]
    migration_data = migration_params.except(:file)
    upload_service = FileUploadService.new(migration_data, uploaded_file, User.current)
    result = upload_service.upload_and_analyze

    if result[:success]
      @migration = result[:migration]
      redirect_to data_migrator_path(@migration)
    else
      @migrations = DataMigration.includes(:user, :project, :external_asset_config)
                                .recent
                                .limit(20)
      @migration = DataMigration.new(migration_data)
      @migration.errors.add(:file, result[:errors].first)
      @external_configs = ExternalAssetConfig.active.order(:name)
      render :index
    end
  end

  def show
    if @migration.file_exists?
      # Load analysis from database, re-analyze if not available
      @analysis = @migration.get_analysis

      # If no analysis data, re-analyze the file
      if @analysis.blank? || @analysis[:headers].blank?
        analyzer = FileAnalyzerService.new(@migration.file_path, @migration.source_type)
        @analysis = analyzer.analyze
        @migration.store_analysis(@analysis)
      end

      @projects = Project.active.has_module(:issue_tracking)
      @trackers = Tracker.all
      @issue_statuses = IssueStatus.all
      @priorities = IssuePriority.all
    else
      Rails.logger.error "Migration file not found for migration #{@migration.id}"
      redirect_to data_migrator_index_path
    end
  rescue => e
    Rails.logger.error "Error loading migration data: #{e.message}"
    redirect_to data_migrator_index_path
  end

  def edit_mapping
    if @migration.file_exists?
      # Load analysis from database, re-analyze if not available
      @analysis = @migration.get_analysis

      # If no analysis data, re-analyze the file
      if @analysis.blank? || @analysis[:headers].blank?
        analyzer = FileAnalyzerService.new(@migration.file_path, @migration.source_type)
        @analysis = analyzer.analyze
        @migration.store_analysis(@analysis)
      end

      @projects = Project.active.has_module(:issue_tracking)
      @trackers = Tracker.all
      @issue_statuses = IssueStatus.all
      @priorities = IssuePriority.all
      @users = User.active.limit(100)

      # Load existing mapping if available
      @current_mapping = @migration.field_mapping.present? ? JSON.parse(@migration.field_mapping) : {}
      @current_options = @migration.processing_options.present? ? JSON.parse(@migration.processing_options) : {}
    else
      Rails.logger.error "Migration file not found for edit_mapping #{@migration.id}"
      redirect_to data_migrator_path(@migration)
    end
  rescue => e
    Rails.logger.error "Error loading migration data for edit: #{e.message}"
    redirect_to data_migrator_path(@migration)
  end

  def update_mapping
    if @migration.file_exists?
      if params[:field_mappings].present?
        mapping_service = FieldMappingService.new(@migration, params)
        field_mapping = mapping_service.build_field_mapping_from_form
        processing_options = processing_options_params

        @migration.update!(
          project_id: params[:project_id],
          field_mapping: field_mapping.to_json,
          processing_options: processing_options.to_json,
          processing_log: (@migration.processing_log || "") + "\nField mapping updated at #{Time.current}"
        )
      end

      if params[:start_processing] == '1'
        @migration.update!(
          status: 'processing',
          processing_log: (@migration.processing_log || "") + "\nProcessing queued for cron at #{Time.current}"
        )
      end

      redirect_to data_migrator_path(@migration)
    else
      Rails.logger.error "Migration file not found for update_mapping #{@migration.id}"
      redirect_to data_migrator_path(@migration)
    end
  rescue => e
    Rails.logger.error "Error updating mapping: #{e.message}"
    redirect_to edit_mapping_data_migrator_path(@migration)
  end

  def process_migration
    project = Project.find(params[:project_id])

    if @migration.file_exists?
      if @migration.field_mapping.blank?
        analyzer = FileAnalyzerService.new(@migration.file_path, @migration.source_type)
        custom_fields = analyzer.create_custom_fields_for_project(project.id)

        mapping_service = FieldMappingService.new(@migration, params)
        field_mapping = mapping_service.build_basic_field_mapping(custom_fields)

        @migration.update!(
          project: project,
          field_mapping: field_mapping.to_json,
          processing_options: processing_options_params.to_json
        )
      else
        @migration.update!(project: project) if @migration.project != project
      end

      @migration.update!(
        status: 'processing',
        processing_log: "Migration queued for cron processing at #{Time.current}"
      )

      redirect_to data_migrator_path(@migration)
    else
      Rails.logger.error "Migration file not found for process_migration #{@migration.id}"
      redirect_to data_migrator_path(@migration)
    end
  rescue => e
    Rails.logger.error "Error queuing migration: #{e.message}"
    redirect_to data_migrator_path(@migration)
  end

  def history
    @migrations = DataMigration.includes(:user, :project, :external_asset_config)
                              .order(created_at: :desc)
                              .limit(50)
  end

  def download_report
    if (@migration.completed? || @migration.failed?) && @migration.error_report.present?
      send_data @migration.error_report,
                filename: "migration_errors_#{@migration.id}_#{Date.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    else
      Rails.logger.error "No report available for migration #{@migration.id}"
      redirect_to data_migrator_path(@migration)
    end
  end

  def restart
    if @migration.can_restart?
      if @migration.restart!
        @migration.update!(processing_log: (@migration.processing_log || "") + "\nMigration restarted at #{Time.current}")
      else
        Rails.logger.error "Failed to restart migration #{@migration.id}"
      end
    else
      Rails.logger.error "Cannot restart migration #{@migration.id} - invalid state or missing file"
    end
    redirect_to data_migrator_path(@migration)
  end

  def rollback
    rollback_service = MigrationRollbackService.new(@migration)

    if rollback_service.perform_rollback
      Rails.logger.info "Migration #{@migration.id} rolled back successfully. Deleted #{rollback_service.deleted_count} issues."
    else
      Rails.logger.error "Cannot rollback migration #{@migration.id} - no imported issues found or rollback failed"
    end

    redirect_to data_migrator_path(@migration)
  end

  def destroy
    # Clean up stored files
    @migration.delete_file
    @migration.destroy
    flash[:notice] = l(:notice_migration_deleted)
    redirect_to data_migrator_index_path
  end

  private

  def find_migration
    @migration = DataMigration.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = l(:error_migration_not_found)
    redirect_to data_migrator_index_path
  end

  def migration_params
    params.require(:data_migration).permit(:description, :file, :external_asset_config_id)
  end

  def processing_options_params
    options = params.permit(:tracker_id, :status_id, :priority_id, :chunk_size, :project_id, field_mappings: {}).to_h
    options[:chunk_size] = (options[:chunk_size].presence || 100).to_i
    options[:tracker_id] = options[:tracker_id].to_i if options[:tracker_id].present?
    options[:status_id] = options[:status_id].to_i if options[:status_id].present?
    options[:priority_id] = options[:priority_id].to_i if options[:priority_id].present?
    # Remove field_mappings from processing options as they are handled separately
    options.delete(:field_mappings)
    options.delete(:project_id)
    options
  end
end