require 'fileutils'

# Service for handling file upload and analysis operations
# Supports: Jira, ClickUp, Asana, Trello, Monday.com, and Custom formats
class FileUploadService
  SUPPORTED_SOURCE_TYPES = %w[jira clickup asana trello monday custom].freeze

  attr_reader :errors, :migration

  def initialize(migration_params, uploaded_file, user)
    @migration_params = migration_params
    @uploaded_file = uploaded_file
    @user = user
    @errors = []
  end

  def upload_and_analyze
    return failure('Please select a file to upload') unless @uploaded_file.present?
    return failure('External asset configuration required') unless @migration_params[:external_asset_config_id].present?

    set_source_type_from_config
    return failure('Invalid external asset configuration') unless valid_source_type?

    create_migration_record
    store_uploaded_file
    analyze_file
    update_migration_with_analysis

    success
  rescue StandardError => e
    ErrorHandlerService.handle_file_operation_error(@file_path, 'upload', e)
    failure("Upload failed: #{e.message}")
  end

  private

  def set_source_type_from_config
    if @migration_params[:external_asset_config_id].present?
      config = ExternalAssetConfig.find(@migration_params[:external_asset_config_id])
      @migration_params[:source_type] = config.system_type
    end
  rescue ActiveRecord::RecordNotFound
    @migration_params[:source_type] = nil
  end

  def valid_source_type?
    @migration_params[:source_type].present? && SUPPORTED_SOURCE_TYPES.include?(@migration_params[:source_type])
  end

  def create_migration_record
    @migration = DataMigration.new(@migration_params)
    @migration.user = @user
    @migration.filename = @uploaded_file.original_filename
    @migration.file_size = @uploaded_file.size
  end

  def store_uploaded_file
    storage_dir = Rails.root.join('files', 'data_migrations')
    FileUtils.mkdir_p(storage_dir) unless Dir.exist?(storage_dir)

    filename = "#{Time.current.to_i}_#{@uploaded_file.original_filename}"
    @file_path = storage_dir.join(filename)

    File.open(@file_path, 'wb') do |f|
      f.write(@uploaded_file.read)
    end

    @migration.file_path = @file_path.to_s
    @migration.file_size = File.size(@file_path)
    @migration.save!
  end

  def analyze_file
    analyzer = FileAnalyzerService.new(@file_path.to_s, @migration.source_type)
    @analysis = analyzer.analyze
  end

  def update_migration_with_analysis
    @migration.update!(
      detected_headers: @analysis[:headers].to_json,
      total_rows: count_total_rows,
      processing_log: "File uploaded and analyzed successfully at #{Time.current}"
    )

    @migration.store_analysis(@analysis)
  end

  def count_total_rows
    FileRowCountService.new(@file_path.to_s).count
  end

  def cleanup_file
    return unless defined?(@file_path) && @file_path

    ErrorHandlerService.safe_file_operation(@file_path) do
      File.delete(@file_path) if File.exist?(@file_path)
    end
  end

  def success
    { success: true, migration: @migration }
  end

  def failure(message)
    @errors << message
    { success: false, errors: @errors }
  end
end