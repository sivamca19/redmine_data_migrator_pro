require 'csv'
require 'roo'

class FileAnalyzerService
  STANDARD_FIELDS = %w[
    subject description status priority assignee reporter tracker
    created updated due_date parent_task versions application attachment comment
  ].freeze

  BASE_FIELD_MAPPING = {
    'id' => 'external_id',
    'subject' => 'subject',
    'description' => 'description',
    'status' => 'status',
    'priority' => 'priority',
    'assignee' => 'assignee',
    'reporter' => 'reporter',
    'tracker' => 'tracker',
    'created' => 'created_on',
    'updated' => 'updated_on',
    'due date' => 'due_date',
    'parent task' => 'parent_issue',
    'attachment' => 'attachment',
    'attachments' => 'attachment',
    'comment' => 'comment',
    'comments' => 'comment'
  }.freeze

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
      sample_data: @sample_data.first(2).map { |row|
        # Limit sample data size to prevent session overflow
        row.transform_values { |v| v.to_s.truncate(50) }
      },
      standard_fields: map_standard_fields,
      custom_fields: identify_custom_fields,
      field_suggestions: suggest_field_mapping
    }
  end

  def create_custom_fields_for_project(project_id)
    custom_fields = identify_custom_fields
    project = Project.find(project_id)
    created_fields = []

    custom_fields.each do |field_info|
      field_name = field_info[:name]
      field_type = field_info[:suggested_type]

      # Check if custom field already exists
      existing_field = CustomField.where(
        name: field_name,
        type: 'IssueCustomField'
      ).first

      unless existing_field
        # Prepare custom field attributes
        cf_attributes = {
          name: field_name,
          field_format: field_type,
          is_required: false,
          is_for_all: false,
          is_filter: true,
          searchable: true,
          editable: true,
          visible: true
        }

        # Add possible values for list-type fields
        if %w[list enumeration].include?(field_type)
          cf_attributes[:possible_values] = ['Option 1', 'Option 2', 'Option 3']
        end

        custom_field = IssueCustomField.create!(cf_attributes)

        # Enable for specific trackers if needed
        custom_field.trackers = project.trackers
        custom_field.save!

        created_fields << {
          id: custom_field.id,
          name: custom_field.name,
          format: custom_field.field_format,
          original_header: field_info[:original_header]
        }
      else
        created_fields << {
          id: existing_field.id,
          name: existing_field.name,
          format: existing_field.field_format,
          original_header: field_info[:original_header],
          existing: true
        }
      end
    end

    created_fields
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
      @sample_data << row.to_h if index < 2  # Reduce to 2 samples
      break if index >= 2
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

    (2..3).each do |row_num|  # Get 2 sample rows
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
    case @source_type
    when 'jira'
      BASE_FIELD_MAPPING.merge({
        'jira id' => 'external_id'
      })
    when 'clickup'
      BASE_FIELD_MAPPING.merge({
        'task id' => 'external_id',
        'task name' => 'subject',
        'list' => 'project',
        'folder' => 'category',
        'space' => 'version',
        'assignees' => 'assignee',
        'tags' => 'category'
      })
    when 'asana'
      BASE_FIELD_MAPPING.merge({
        'task id' => 'external_id',
        'task name' => 'subject',
        'project' => 'project',
        'section' => 'category',
        'completed' => 'status',
        'completed at' => 'closed_on',
        'assignee' => 'assignee',
        'tags' => 'category'
      })
    when 'trello'
      BASE_FIELD_MAPPING.merge({
        'card id' => 'external_id',
        'card name' => 'subject',
        'list name' => 'status',
        'board name' => 'project',
        'labels' => 'category',
        'members' => 'assignee',
        'date created' => 'created_on',
        'date last activity' => 'updated_on'
      })
    when 'monday'
      BASE_FIELD_MAPPING.merge({
        'item id' => 'external_id',
        'item name' => 'subject',
        'group' => 'category',
        'board' => 'project',
        'person' => 'assignee',
        'timeline' => 'due_date',
        'creation log' => 'created_on'
      })
    else
      BASE_FIELD_MAPPING
    end
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
    @sample_data.map { |row| row[header] }.compact.first(2)
  end
end