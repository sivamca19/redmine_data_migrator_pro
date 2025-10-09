class DataMigration < ActiveRecord::Base
  SUPPORTED_SOURCE_TYPES = %w[jira clickup asana trello monday custom].freeze
  SUPPORTED_FILE_EXTENSIONS = %w[.csv .xls .xlsx].freeze

  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :external_asset_config, optional: true

  validates :source_type, presence: true, inclusion: { in: SUPPORTED_SOURCE_TYPES }
  validates :filename, presence: true
  validates :user, presence: true
  validates :file_path, presence: true
  validate :supported_file_format

  enum status: {
    uploaded: 0,
    processing: 1,
    completed: 2,
    failed: 3,
    cancelled: 4
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where.not(status: 'cancelled') }
  scope :by_source_type, ->(type) { where(source_type: type) if type.present? }

  def can_process?
    uploaded? && File.exist?(file_path.to_s)
  end

  def update_status!(new_status)
    update!(status: new_status, processed_at: Time.current)
  end

  def file_extension
    return nil unless filename.present?
    File.extname(filename).downcase
  end

  def supported_format?
    SUPPORTED_FILE_EXTENSIONS.include?(file_extension)
  end

  def file_size_mb
    return 0 unless file_size.present?
    (file_size / 1.megabyte.to_f).round(2)
  end

  def processing_duration
    return nil unless processed_at.present?
    ((processed_at - updated_at) / 1.minute).round(2)
  end

  def success_rate
    return 0 if total_rows.to_i == 0
    ((total_rows - error_rows.to_i) / total_rows.to_f * 100).round(2)
  end

  def file_exists?
    file_path.present? && File.exist?(file_path)
  end

  def delete_file
    File.delete(file_path) if file_exists?
  end

  def can_restart?
    (failed? || completed?) && file_exists?
  end

  def can_edit_mapping?
    (uploaded? || failed? || completed?) && file_exists?
  end

  def can_rollback?
    completed? && imported_issue_ids.present?
  end

  def restart!
    if can_restart?
      update!(
        status: 'processing',
        processed_rows: 0,
        success_rows: 0,
        error_rows: 0,
        error_summary: nil,
        error_report: nil,
        processed_at: nil,
        processing_log: (processing_log || "") + "\n--- RESTARTED AT #{Time.current} ---"
      )
      true
    else
      false
    end
  end

  def get_analysis
    return default_analysis_structure if analysis_data.blank?

    begin
      parsed = JSON.parse(analysis_data).with_indifferent_access
      ensure_analysis_structure(parsed)
    rescue JSON::ParserError
      Rails.logger.error "Failed to parse analysis data for migration #{id}"
      default_analysis_structure
    end
  end

  def store_analysis(analysis_hash)
    update!(analysis_data: analysis_hash.to_json)
  end

  def has_field_mapping?
    field_mapping.present?
  end

  def parsed_field_mapping
    return {} unless has_field_mapping?
    JSON.parse(field_mapping)
  rescue JSON::ParserError
    Rails.logger.error "Failed to parse field mapping for migration #{id}"
    {}
  end

  def parsed_processing_options
    return {} unless processing_options.present?
    JSON.parse(processing_options)
  rescue JSON::ParserError
    Rails.logger.error "Failed to parse processing options for migration #{id}"
    {}
  end

  def add_to_processing_log(message)
    current_log = processing_log || ""
    update!(processing_log: "#{current_log}\n#{Time.current}: #{message}")
  end

  private

  def supported_file_format
    return unless filename.present?

    unless supported_format?
      errors.add(:filename, "must be one of: #{SUPPORTED_FILE_EXTENSIONS.join(', ')}")
    end
  end

  def default_analysis_structure
    {
      headers: [],
      sample_data: [],
      standard_fields: {},
      custom_fields: [],
      field_suggestions: {}
    }
  end

  def ensure_analysis_structure(parsed)
    parsed[:headers] ||= []
    parsed[:sample_data] ||= []
    parsed[:standard_fields] ||= {}
    parsed[:custom_fields] ||= []
    parsed[:field_suggestions] ||= {}
    parsed
  end
end