require 'csv'
require 'roo'

class FileAnalyzerService
  STANDARD_FIELDS = %w[
    subject description status priority assignee reporter tracker
    created updated due_date parent_task versions application attachment comment
  ].freeze

  SAMPLE_DATA_LIMIT = 2
  MAX_SAMPLE_TEXT_LENGTH = 50

  attr_reader :file_path, :source_type, :headers, :sample_data

  def initialize(file_path, source_type = 'jira')
    @file_path = file_path
    @source_type = source_type.downcase
    @headers = []
    @sample_data = []
  end

  def analyze
    extract_headers_and_sample

    {
      headers: @headers,
      total_columns: @headers.length,
      sample_data: truncated_sample_data,
      standard_fields: map_standard_fields,
      custom_fields: identify_custom_fields,
      field_suggestions: suggest_field_mapping
    }
  end

  def create_custom_fields_for_project(project_id)
    project = Project.find(project_id)
    custom_field_creator = CustomFieldCreatorService.new(project)

    identify_custom_fields.map do |field_info|
      custom_field_creator.find_or_create_field(field_info)
    end
  end

  private

  def extract_headers_and_sample
    case File.extname(@file_path).downcase
    when '.csv'
      extract_from_csv
    when '.xls', '.xlsx'
      extract_from_excel
    else
      raise "Unsupported file format"
    end
  end

  def extract_from_csv
    CSV.foreach(@file_path, headers: true).with_index do |row, index|
      if index == 0
        @headers = row.headers.map(&:to_s)
      end
      @sample_data << row.to_h if index < SAMPLE_DATA_LIMIT
      break if index >= SAMPLE_DATA_LIMIT
    end
  end

  def extract_from_excel
    spreadsheet = Roo::Spreadsheet.open(@file_path)
    sheet = spreadsheet.sheet(0)

    # Get headers and clean them
    @headers = sheet.row(1).map { |h| h.to_s.strip }

    # Log attachment columns found
    attachment_headers = @headers.select { |h| h.downcase.include?('attachment') || h.downcase.include?('file') || h.downcase.include?('url') }
    puts "FileAnalyzer detected attachment columns: #{attachment_headers.join(', ')}" if attachment_headers.any?

    (2..(SAMPLE_DATA_LIMIT + 1)).each do |row_num|
      break if row_num > sheet.last_row
      row_data = {}
      @headers.each_with_index do |header, col_index|
        cell_value = sheet.cell(row_num, col_index + 1)

        # Handle different cell types properly
        if cell_value.nil?
          row_data[header] = nil
        elsif cell_value.is_a?(DateTime) || cell_value.is_a?(Date)
          row_data[header] = cell_value.to_s.truncate(50)
        elsif cell_value.is_a?(Float) && cell_value == cell_value.to_i
          # Convert float that's actually an integer
          row_data[header] = cell_value.to_i.to_s.truncate(50)
        else
          row_data[header] = cell_value.to_s.strip.truncate(50)
        end
      end
      @sample_data << row_data
    end
  end

  def map_standard_fields
    mapped = {}
    field_mapping = get_field_mapping_for_source

    @headers.each do |header|
      normalized_header = normalize_header(header)
      if field_mapping[normalized_header]
        mapped[header] = {
          redmine_field: field_mapping[normalized_header],
          type: 'standard'
        }
      end
    end

    mapped
  end

  def identify_custom_fields
    standard_mapped = map_standard_fields.keys
    custom_headers = @headers - standard_mapped

    custom_headers.map do |header|
      {
        original_header: header,
        name: sanitize_field_name(header),
        suggested_type: suggest_field_type(header),
        sample_values: get_sample_values_for_header(header).map { |v| v.to_s.truncate(30) }
      }
    end
  end

  def suggest_field_mapping
    suggestions = {}

    @headers.each do |header|
      normalized = normalize_header(header)

      # Suggest based on common patterns
      if normalized.include?('date') || normalized.include?('time')
        suggestions[header] = 'date'
      elsif normalized.include?('url') || normalized.include?('link')
        suggestions[header] = 'link'
      elsif normalized.include?('attachment')
        suggestions[header] = 'attachment'
      elsif normalized.include?('comment')
        suggestions[header] = 'text'
      elsif header.downcase.include?('priority')
        suggestions[header] = 'string'  # Use string for now, avoid validation issues
      elsif header.downcase.include?('status')
        suggestions[header] = 'string'  # Use string for now, avoid validation issues
      else
        suggestions[header] = 'string'
      end
    end

    suggestions
  end

  def get_field_mapping_for_source
    field_mapping_service.get_mapping
  end

  def normalize_header(header)
    header.to_s.downcase.strip.gsub(/[^a-z0-9\s]/, ' ').squeeze(' ')
  end

  def sanitize_field_name(header)
    # Convert header to proper field name
    header.to_s.gsub(/[^a-zA-Z0-9\s]/, ' ')
           .split.map(&:capitalize).join(' ')
           .strip
  end

  def suggest_field_type(header)
    sample_values = get_sample_values_for_header(header)
    normalized = normalize_header(header)

    return 'date' if normalized.include?('date') || normalized.include?('time')
    return 'link' if normalized.include?('url') || normalized.include?('link')
    return 'text' if normalized.include?('description') || normalized.include?('comment')

    # Analyze sample values
    if sample_values.any? { |v| v.is_a?(Date) || v.is_a?(DateTime) }
      'date'
    elsif sample_values.all? { |v| v.to_s.length > 100 }
      'text'
    elsif sample_values.all? { |v| v.to_s.match?(/^\d+$/) }
      'int'
    elsif sample_values.all? { |v| v.to_s.match?(/^\d*\.?\d+$/) }
      'float'
    else
      'string'
    end
  end

  def get_sample_values_for_header(header)
    @sample_data.map { |row| row[header] }.compact.first(SAMPLE_DATA_LIMIT)
  end

  private

  def truncated_sample_data
    @sample_data.first(SAMPLE_DATA_LIMIT).map do |row|
      row.transform_values { |v| v.to_s.truncate(MAX_SAMPLE_TEXT_LENGTH) }
    end
  end

  def field_mapping_service
    @field_mapping_service ||= SourceFieldMappingService.new(@source_type)
  end
end