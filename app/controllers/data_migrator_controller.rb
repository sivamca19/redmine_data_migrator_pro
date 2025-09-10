class DataMigratorController < ApplicationController
  before_action :require_admin
  before_action :find_migration, except: [:index, :upload, :history, :clear_history]

  def index
    @migrations = DataMigration.includes(:user, :project)
                              .recent
                              .limit(20)
    @migration = DataMigration.new
  end

  def upload
    uploaded_file = params[:data_migration][:file]

    if uploaded_file.present?
      # Store file permanently
      storage_dir = Rails.root.join('files', 'data_migrations')
      FileUtils.mkdir_p(storage_dir) unless Dir.exist?(storage_dir)

      filename = "#{Time.current.to_i}_#{uploaded_file.original_filename}"
      file_path = storage_dir.join(filename)

      # Save uploaded file
      File.open(file_path, 'wb') do |f|
        f.write(uploaded_file.read)
      end

      # Create migration record
      @migration = DataMigration.new(migration_params)
      @migration.user = User.current
      @migration.filename = uploaded_file.original_filename
      @migration.file_path = file_path.to_s
      @migration.file_size = File.size(file_path)

      if @migration.save
        # Analyze the uploaded file
        analyzer = FileAnalyzerService.new(file_path.to_s, @migration.source_type)
        analysis = analyzer.analyze

        @migration.update!(
          detected_headers: analysis[:headers].to_json,
          total_rows: count_total_rows(file_path.to_s),
          processing_log: "File uploaded and analyzed successfully at #{Time.current}"
        )

        # Store analysis data separately
        @migration.store_analysis(analysis)

        # Store success message in database instead of session
        @migration.update!(processing_log: (@migration.processing_log || "") + "\nFile uploaded successfully at #{Time.current}")
        redirect_to data_migrator_path(@migration)
      else
        File.delete(file_path) if File.exist?(file_path)
        @migrations = DataMigration.recent.limit(20)
        render :index
      end
    else
      @migrations = DataMigration.recent.limit(20)
      @migration = DataMigration.new
      @migration.errors.add(:file, "Please select a file to upload")
      render :index
    end
  rescue => e
    File.delete(file_path) if defined?(file_path) && File.exist?(file_path)
    Rails.logger.error "File upload error: #{e.message}"
    redirect_to data_migrator_index_path
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
      # Only update mapping if we have field mapping data (not from "Start Processing" button)
      if params[:field_mappings].present?
        # Save the updated field mapping
        field_mapping = build_field_mapping_from_form(params)
        processing_options = processing_options_params

        @migration.update!(
          project_id: params[:project_id],
          field_mapping: field_mapping.to_json,
          processing_options: processing_options.to_json,
          processing_log: (@migration.processing_log || "") + "\nField mapping updated at #{Time.current}"
        )
      end

      # If user requested to start processing immediately
      if params[:start_processing] == '1'
        @migration.update!(
          status: 'processing',
          processing_log: (@migration.processing_log || "") + "\nProcessing started at #{Time.current}"
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
      # Use existing field mapping or create new one
      if @migration.field_mapping.blank?
        # Create custom fields based on file headers
        analyzer = FileAnalyzerService.new(@migration.file_path, @migration.source_type)

        # Create/update custom fields for the project
        custom_fields = analyzer.create_custom_fields_for_project(project.id)

        # Save the field mapping
        field_mapping = build_field_mapping(params, custom_fields)

        @migration.update!(
          project: project,
          field_mapping: field_mapping.to_json,
          processing_options: processing_options_params.to_json
        )
      else
        # Update project if different
        @migration.update!(project: project) if @migration.project != project
      end

      @migration.update!(
        status: 'processing',
        processing_log: "Migration queued for cron processing at #{Time.current}"
      )

      @migration.update!(processing_log: (@migration.processing_log || "") + "\nMigration queued for processing at #{Time.current}")
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
    @migrations = DataMigration.includes(:user, :project)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(25)
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
    if @migration.can_rollback?
      begin
        deleted_count = perform_rollback(@migration)

        # Reset migration to uploaded state
        @migration.update!(
          status: 'uploaded',
          processed_rows: 0,
          success_rows: 0,
          error_rows: 0,
          error_summary: nil,
          error_report: nil,
          imported_issue_ids: nil,
          processed_at: nil,
          processing_log: (@migration.processing_log || "") + "\n--- ROLLED BACK AT #{Time.current} - Deleted #{deleted_count} issues ---"
        )

        Rails.logger.info "Migration #{@migration.id} rolled back successfully. Deleted #{deleted_count} issues."
        redirect_to data_migrator_path(@migration)
      rescue => e
        Rails.logger.error "Error during rollback of migration #{@migration.id}: #{e.message}"
        redirect_to data_migrator_path(@migration)
      end
    else
      Rails.logger.error "Cannot rollback migration #{@migration.id} - no imported issues found"
      redirect_to data_migrator_path(@migration)
    end
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
    params.require(:data_migration).permit(:source_type, :description)
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


  def count_total_rows(file_path)
    case File.extname(file_path).downcase
    when '.csv'
      count = 0
      CSV.foreach(file_path, headers: true) do |row|
        # Count only rows with some actual data
        if row.to_h.values.any?(&:present?)
          count += 1
        end
      end
      count
    when '.xls', '.xlsx'
      spreadsheet = Roo::Spreadsheet.open(file_path)
      sheet = spreadsheet.sheet(0)
      headers = sheet.row(1)

      data_row_count = 0

      # Instead of using sheet.last_row (which includes empty formatted cells),
      # iterate through potential rows and stop when we find consecutive empty rows
      row_num = 2
      consecutive_empty_rows = 0
      max_consecutive_empty = 5  # Stop after 5 consecutive empty rows

      while consecutive_empty_rows < max_consecutive_empty
        # Check if row has any actual data across all columns
        has_data = false

        (1..headers.count).each do |col_index|
          cell_value = sheet.cell(row_num, col_index)
          if cell_value.present? && cell_value.to_s.strip.present?
            has_data = true
            break
          end
        end

        if has_data
          data_row_count += 1
          consecutive_empty_rows = 0  # Reset counter
        else
          consecutive_empty_rows += 1
        end

        row_num += 1

        # Safety check to prevent infinite loops
        break if row_num > 10000
      end

      Rails.logger.info "Excel file row count: #{data_row_count} actual data rows found"
      data_row_count
    else
      0
    end
  rescue => e
    Rails.logger.error "Error counting rows: #{e.message}"
    0
  end

  def build_field_mapping(params, custom_fields)
    mapping = {}

    # Standard field mappings from form
    %w[subject description status priority assignee tracker].each do |field|
      header_param = "#{field}_mapping"
      if params[header_param].present?
        mapping[params[header_param]] = {
          type: 'standard',
          field: field
        }
      end
    end

    # Custom field mappings - automatically map all detected custom fields
    custom_fields.each do |cf|
      mapping[cf[:original_header]] = {
        type: 'custom',
        field_id: cf[:id],
        field_name: cf[:name],
        field_format: cf[:format]
      }
    end

    mapping
  end

  def build_field_mapping_from_form(params)
    mapping = {}

    # Get field mappings with proper parameter permission
    field_mappings = params.permit(field_mappings: {})[:field_mappings] || {}

    # Process field mappings from the edit form
    if field_mappings.present?
      field_mappings.each do |header, mapping_data|
        next if mapping_data[:type].blank?

        case mapping_data[:type]
        when 'auto'
          # Handle auto-detect mapping
          if mapping_data[:field].present?
            # Handle attachment fields specially - don't create custom fields but store mapping for AttachmentDownloadService
            if mapping_data[:field] == 'attachment' || header.downcase.include?('attachment')
              puts "Storing attachment field mapping for download service: #{header} -> #{mapping_data[:field]}"
              mapping[header] = {
                type: 'attachment',
                field: 'attachment'
              }
              next
            end

            # Standard field detected
            mapping[header] = {
              type: 'auto',
              manual_type: mapping_data[:manual_type],
              field: mapping_data[:field],
              field_id: mapping_data[:field_id]
            }
          elsif mapping_data[:custom_field_name].present?
            # Skip attachment fields - don't create custom fields for them
            if header.downcase.include?('attachment')
              puts "Skipping custom field creation for attachment column in controller: #{header}"
              next
            end

            # Create or find custom field
            field_name = mapping_data[:custom_field_name]
            field_format = mapping_data[:custom_field_format] || 'string'

            # Find existing or create new custom field
            custom_field = CustomField.where(name: field_name, type: 'IssueCustomField').first
            unless custom_field
              # Prepare custom field attributes
              cf_attributes = {
                name: field_name,
                field_format: field_format,
                is_required: false,
                is_for_all: false,
                is_filter: true,
                searchable: true,
                editable: true,
                visible: true
              }

              # Add possible values for list-type fields
              if %w[list enumeration].include?(field_format)
                cf_attributes[:possible_values] = ['Option 1', 'Option 2', 'Option 3']
              end

              custom_field = IssueCustomField.create!(cf_attributes)
              puts "Created custom field: #{field_name} (#{field_format})"
            else
              puts "Found existing custom field: #{field_name}"
            end

            # Ensure custom field is assigned to project and trackers (both new and existing)
            if @migration.project
              # Add project if not already assigned
              unless custom_field.projects.include?(@migration.project)
                custom_field.projects << @migration.project
                puts "Assigned custom field '#{field_name}' to project '#{@migration.project.name}'"
              end

              # Add trackers if not already assigned
              missing_trackers = @migration.project.trackers - custom_field.trackers
              if missing_trackers.any?
                custom_field.trackers += missing_trackers
                puts "Assigned custom field '#{field_name}' to trackers: #{missing_trackers.map(&:name).join(', ')}"
              end

              custom_field.save!
            end

            mapping[header] = {
              type: 'custom',
              field_id: custom_field.id,
              field_name: custom_field.name,
              field_format: custom_field.field_format
            }
          end
        when 'manual'
          # Handle manual mapping
          manual_type = mapping_data[:manual_type] || 'standard'
          if manual_type == 'standard' && mapping_data[:field].present?
            # Handle attachment fields specially
            if mapping_data[:field] == 'attachment' || header.downcase.include?('attachment')
              puts "Storing manual attachment field mapping for download service: #{header} -> #{mapping_data[:field]}"
              mapping[header] = {
                type: 'attachment',
                field: 'attachment'
              }
              next
            end

            mapping[header] = {
              type: 'manual',
              field: mapping_data[:field]
            }
          elsif manual_type == 'custom' && mapping_data[:field_id].present?
            custom_field = CustomField.find_by(id: mapping_data[:field_id])
            if custom_field
              # Ensure existing custom field is assigned to project and trackers
              if @migration.project
                unless custom_field.projects.include?(@migration.project)
                  custom_field.projects << @migration.project
                  puts "Assigned existing custom field '#{custom_field.name}' to project '#{@migration.project.name}'"
                end

                missing_trackers = @migration.project.trackers - custom_field.trackers
                if missing_trackers.any?
                  custom_field.trackers += missing_trackers
                  puts "Assigned existing custom field '#{custom_field.name}' to trackers: #{missing_trackers.map(&:name).join(', ')}"
                end

                custom_field.save!
              end

              mapping[header] = {
                type: 'custom',
                field_id: custom_field.id,
                field_name: custom_field.name,
                field_format: custom_field.field_format
              }
            end
          end
        when 'standard'
          next if mapping_data[:field].blank?

          # Handle attachment fields specially
          if mapping_data[:field] == 'attachment' || header.downcase.include?('attachment')
            puts "Storing standard attachment field mapping for download service: #{header} -> #{mapping_data[:field]}"
            mapping[header] = {
              type: 'attachment',
              field: 'attachment'
            }
            next
          end

          mapping[header] = {
            type: 'standard',
            field: mapping_data[:field]
          }
        when 'custom'
          next if mapping_data[:field_id].blank?
          custom_field = CustomField.find_by(id: mapping_data[:field_id])
          if custom_field
            # Ensure existing custom field is assigned to project and trackers
            if @migration.project
              unless custom_field.projects.include?(@migration.project)
                custom_field.projects << @migration.project
                puts "Assigned existing custom field '#{custom_field.name}' to project '#{@migration.project.name}'"
              end

              missing_trackers = @migration.project.trackers - custom_field.trackers
              if missing_trackers.any?
                custom_field.trackers += missing_trackers
                puts "Assigned existing custom field '#{custom_field.name}' to trackers: #{missing_trackers.map(&:name).join(', ')}"
              end

              custom_field.save!
            end

            mapping[header] = {
              type: 'custom',
              field_id: custom_field.id,
              field_name: custom_field.name,
              field_format: custom_field.field_format
            }
          end
        when 'ignore'
          mapping[header] = {
            type: 'ignore'
          }
        end
      end
    end

    mapping
  end

  def perform_rollback(migration)
    return 0 unless migration.imported_issue_ids.present?

    issue_ids = migration.imported_issue_ids.split(',').map(&:to_i)
    deleted_count = 0

    issue_ids.each do |issue_id|
      begin
        issue = Issue.find(issue_id)
        if issue.destroy
          deleted_count += 1
          Rails.logger.info "Deleted issue #{issue_id} during migration rollback"
        end
      rescue ActiveRecord::RecordNotFound
        Rails.logger.warn "Issue #{issue_id} not found during rollback (may have been deleted already)"
      rescue => e
        Rails.logger.error "Error deleting issue #{issue_id} during rollback: #{e.message}"
      end
    end

    deleted_count
  end
end