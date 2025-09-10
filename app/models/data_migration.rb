class DataMigration < ActiveRecord::Base
  belongs_to :user
  belongs_to :project, optional: true

  validates :source_type, presence: true, inclusion: { in: %w[jira clickup asana trello monday custom] }
  validates :filename, presence: true
  validates :user, presence: true
  validates :file_path, presence: true

  enum status: {
    uploaded: 0,
    processing: 1,
    completed: 2,
    failed: 3,
    cancelled: 4
  }

  scope :recent, -> { order(created_at: :desc) }

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
    %w[.csv .xls .xlsx].include?(file_extension)
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
    true || (uploaded? || failed? || completed?) && file_exists?
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

  # Get parsed analysis data
  def get_analysis
    return { headers: [], sample_data: [], standard_fields: {}, custom_fields: [], field_suggestions: {} } if analysis_data.blank?

    begin
      parsed = JSON.parse(analysis_data).with_indifferent_access
      # Ensure required keys exist
      parsed[:headers] ||= []
      parsed[:sample_data] ||= []
      parsed[:standard_fields] ||= {}
      parsed[:custom_fields] ||= []
      parsed[:field_suggestions] ||= {}
      parsed
    rescue JSON::ParserError
      { headers: [], sample_data: [], standard_fields: {}, custom_fields: [], field_suggestions: {} }
    end
  end

  # Store analysis data
  def store_analysis(analysis_hash)
    update!(analysis_data: analysis_hash.to_json)
  end
end