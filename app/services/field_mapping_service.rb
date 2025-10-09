class FieldMappingService
  SUPPORTED_STANDARD_FIELDS = %w[subject description status priority assignee tracker due_date created_on updated_on external_id reporter parent_issue attachment comment].freeze
  ATTACHMENT_MAPPING_TYPES = %w[attachment].freeze

  def initialize(migration, params = {})
    @migration = migration
    @params = params
  end

  def build_field_mapping_from_form
    return {} unless @params[:field_mappings].present?

    mapping = {}
    field_mappings = @params.permit(field_mappings: {})[:field_mappings] || {}

    field_mappings.each do |header, mapping_data|
      next if mapping_data[:type].blank?

      mapping[header] = process_mapping_by_type(header, mapping_data)
    end

    mapping.compact
  end

  def build_basic_field_mapping(custom_fields)
    mapping = {}

    SUPPORTED_STANDARD_FIELDS.each do |field|
      header_param = "#{field}_mapping"
      if @params[header_param].present?
        mapping[@params[header_param]] = {
          type: 'standard',
          field: field
        }
      end
    end

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

  private

  def process_mapping_by_type(header, mapping_data)
    case mapping_data[:type]
    when 'auto'
      process_auto_mapping(header, mapping_data)
    when 'manual'
      process_manual_mapping(header, mapping_data)
    when 'standard'
      process_standard_mapping(header, mapping_data)
    when 'custom'
      process_custom_mapping(header, mapping_data)
    when 'ignore'
      { type: 'ignore' }
    end
  end

  def process_auto_mapping(header, mapping_data)
    if mapping_data[:field].present?
      if attachment_field?(mapping_data[:field]) || attachment_header?(header)
        return create_attachment_mapping
      end

      return {
        type: 'auto',
        manual_type: mapping_data[:manual_type],
        field: mapping_data[:field],
        field_id: mapping_data[:field_id]
      }
    elsif mapping_data[:custom_field_name].present?
      return nil if attachment_header?(header)
      return create_custom_field_mapping(mapping_data)
    end
  end

  def process_manual_mapping(header, mapping_data)
    manual_type = mapping_data[:manual_type] || 'standard'

    if manual_type == 'standard' && mapping_data[:field].present?
      if attachment_field?(mapping_data[:field]) || attachment_header?(header)
        return create_attachment_mapping
      end

      return {
        type: 'manual',
        field: mapping_data[:field]
      }
    elsif manual_type == 'custom' && mapping_data[:field_id].present?
      return process_existing_custom_field(mapping_data[:field_id])
    end
  end

  def process_standard_mapping(header, mapping_data)
    return nil if mapping_data[:field].blank?

    if attachment_field?(mapping_data[:field]) || attachment_header?(header)
      return create_attachment_mapping
    end

    {
      type: 'standard',
      field: mapping_data[:field]
    }
  end

  def process_custom_mapping(header, mapping_data)
    return nil if mapping_data[:field_id].blank?
    process_existing_custom_field(mapping_data[:field_id])
  end

  def process_existing_custom_field(field_id)
    custom_field = CustomField.find_by(id: field_id)
    return nil unless custom_field

    assign_custom_field_to_project(custom_field)

    {
      type: 'custom',
      field_id: custom_field.id,
      field_name: custom_field.name,
      field_format: custom_field.field_format
    }
  end

  def create_custom_field_mapping(mapping_data)
    field_name = mapping_data[:custom_field_name]
    field_format = mapping_data[:custom_field_format] || 'string'

    custom_field = find_or_create_custom_field(field_name, field_format)
    assign_custom_field_to_project(custom_field)

    {
      type: 'custom',
      field_id: custom_field.id,
      field_name: custom_field.name,
      field_format: custom_field.field_format
    }
  end

  def find_or_create_custom_field(field_name, field_format)
    existing_field = CustomField.where(name: field_name, type: 'IssueCustomField').first
    return existing_field if existing_field

    create_custom_field(field_name, field_format)
  end

  def create_custom_field(field_name, field_format)
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

    if %w[list enumeration].include?(field_format)
      cf_attributes[:possible_values] = ['Option 1', 'Option 2', 'Option 3']
    end

    IssueCustomField.create!(cf_attributes)
  end

  def assign_custom_field_to_project(custom_field)
    return unless @migration.project

    unless custom_field.projects.include?(@migration.project)
      custom_field.projects << @migration.project
    end

    missing_trackers = @migration.project.trackers - custom_field.trackers
    if missing_trackers.any?
      custom_field.trackers += missing_trackers
    end

    custom_field.save!
  end

  def create_attachment_mapping
    {
      type: 'attachment',
      field: 'attachment'
    }
  end

  def attachment_field?(field)
    ATTACHMENT_MAPPING_TYPES.include?(field)
  end

  def attachment_header?(header)
    header.to_s.downcase.include?('attachment')
  end
end