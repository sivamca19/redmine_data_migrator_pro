class CustomFieldCreatorService
  DEFAULT_LIST_OPTIONS = ['Option 1', 'Option 2', 'Option 3'].freeze

  def initialize(project)
    @project = project
  end

  def find_or_create_field(field_info)
    existing_field = find_existing_field(field_info[:name])

    if existing_field
      build_field_response(existing_field, field_info, true)
    else
      new_field = create_new_field(field_info)
      build_field_response(new_field, field_info, false)
    end
  end

  private

  def find_existing_field(field_name)
    CustomField.where(
      name: field_name,
      type: 'IssueCustomField'
    ).first
  end

  def create_new_field(field_info)
    field_name = field_info[:name]
    field_type = field_info[:suggested_type]

    cf_attributes = build_field_attributes(field_name, field_type)
    custom_field = IssueCustomField.create!(cf_attributes)

    assign_to_project_trackers(custom_field)
    custom_field
  end

  def build_field_attributes(field_name, field_type)
    attributes = {
      name: field_name,
      field_format: field_type,
      is_required: false,
      is_for_all: false,
      is_filter: true,
      searchable: true,
      editable: true,
      visible: true
    }

    if %w[list enumeration].include?(field_type)
      attributes[:possible_values] = DEFAULT_LIST_OPTIONS
    end

    attributes
  end

  def assign_to_project_trackers(custom_field)
    custom_field.trackers = @project.trackers
    custom_field.save!
  end

  def build_field_response(custom_field, field_info, existing)
    {
      id: custom_field.id,
      name: custom_field.name,
      format: custom_field.field_format,
      original_header: field_info[:original_header],
      existing: existing
    }
  end
end