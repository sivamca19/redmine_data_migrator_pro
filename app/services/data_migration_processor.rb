require 'csv'
require 'roo'

class DataMigrationProcessor
  attr_reader :migration, :errors, :processed_count, :success_count, :error_count

  def initialize(migration)
    @migration = migration
    @errors = []
    @processed_count = 0
    @success_count = 0
    @error_count = 0
    @skipped_count = 0
    @skipped_rows = []
    @custom_fields_cache = {}
    @imported_issue_ids = []

    # Parse JSON strings if they exist
    @field_mapping = migration.field_mapping.present? ? JSON.parse(migration.field_mapping) : {}
    @processing_options = migration.processing_options.present? ? JSON.parse(migration.processing_options) : {}
    @chunk_size = @processing_options['chunk_size'] || 100
  end

  def process
    return false unless migration.processing?
    return false unless migration.file_exists?

    begin
      migration.update!(
        processing_log: "Starting migration processing at #{Time.current}",
        processed_rows: 0,
        success_rows: 0,
        error_rows: 0
      )
      p "im in process"
      # Ensure custom fields exist before processing
      ensure_custom_fields_exist

      # Process file based on extension
      case migration.file_extension
      when '.csv'
        process_csv_file(migration.file_path)
      when '.xls', '.xlsx'
        process_excel_file(migration.file_path)
      end

      # Determine final status based on results
      final_status = determine_final_status

      migration.update!(
        status: final_status,
        processed_rows: processed_count,
        success_rows: success_count,
        error_rows: error_count,
        error_report: generate_error_report,
        error_summary: generate_error_summary,
        imported_issue_ids: @imported_issue_ids.join(','),
        processed_at: Time.current,
        processing_log: migration.processing_log.to_s + "\n#{final_status.capitalize} at #{Time.current}. Total: #{migration.total_rows}, Processed: #{processed_count}, Success: #{success_count}, Errors: #{error_count}, Skipped: #{@skipped_count}\n#{generate_skipped_summary}"
      )

      true
    rescue => e
      migration.update!(
        status: 'failed',
        error_summary: "Processing failed: #{e.message}",
        processing_log: migration.processing_log.to_s + "\nFailed at #{Time.current}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      )
      false
    end
  end

  private

  def process_csv_file(file_path)
    current_row = 1 # Start from 1 (header is row 1, data starts from 2)

    CSV.foreach(file_path, headers: true).with_index do |row, index|
      current_row = index + 2 # Actual row number in file

      begin
        # Merge duplicate columns for CSV as well
        merged_row_data = merge_duplicate_columns(row.to_h, current_row)

        # Check if row should be skipped
        skip_reason = should_skip_row?(merged_row_data, current_row)
        if skip_reason
          record_skipped_row(current_row, merged_row_data, skip_reason)
          next
        end

        process_single_row(merged_row_data, current_row)
        @processed_count += 1
        @success_count += 1

        # Update progress every chunk
        if @processed_count % @chunk_size == 0
          update_migration_progress
        end

      rescue => e
        @error_count += 1
        @processed_count += 1
        record_row_error(current_row, merged_row_data || row.to_h, e.message)

        # Log error but continue processing
        Rails.logger.error "Row #{current_row} processing failed: #{e.message}"
      end
    end

    # Final progress update
    update_migration_progress
  end

  def process_excel_file(file_path)
    spreadsheet = Roo::Spreadsheet.open(file_path)
    sheet = spreadsheet.sheet(0)

    # Get headers and clean them
    headers = sheet.row(1).map { |h| h.to_s.strip }
    puts "Excel file headers: #{headers.join(', ')}"

    # Find attachment columns for logging
    attachment_headers = headers.select { |h| h.downcase.include?('attachment') || h.downcase.include?('file') || h.downcase.include?('url') }
    puts "Detected potential attachment columns: #{attachment_headers.join(', ')}" if attachment_headers.any?

    # Use improved row iteration logic that stops at empty rows
    row_num = 2
    consecutive_empty_rows = 0
    max_consecutive_empty = 5  # Stop after 5 consecutive empty rows

    while consecutive_empty_rows < max_consecutive_empty
      # First check if this row has any data
      has_data = false
      (1..headers.count).each do |col_index|
        cell_value = sheet.cell(row_num, col_index)
        if cell_value.present? && cell_value.to_s.strip.present?
          has_data = true
          break
        end
      end

      # If no data, increment empty counter and continue
      unless has_data
        consecutive_empty_rows += 1
        row_num += 1
        next
      end

      # Reset empty counter since we found data
      consecutive_empty_rows = 0
      begin
        row_data = {}

        # Track all values for each unique header name
        header_values = {}

        headers.each_with_index do |header, col_index|
          cell_value = sheet.cell(row_num, col_index + 1)

          # Handle different cell types properly
          processed_value = nil
          if cell_value.nil?
            processed_value = nil
          elsif cell_value.is_a?(DateTime) || cell_value.is_a?(Date)
            processed_value = cell_value.to_s
          elsif cell_value.is_a?(Float) && cell_value == cell_value.to_i
            # Convert float that's actually an integer
            processed_value = cell_value.to_i.to_s
          else
            processed_value = cell_value.to_s.strip
          end

          # Skip empty values
          next if processed_value.blank?

          # Group all values by header name
          header_key = header.to_s.strip
          header_values[header_key] ||= []
          header_values[header_key] << processed_value
        end

        # Merge all duplicate columns based on their type
        header_values.each do |header, values|
          next if values.empty?

          if values.count == 1
            # Single value, use as-is
            row_data[header] = values.first
          else
            # Multiple values, merge based on field type
            merged_value = merge_values_by_type(header, values)
            row_data[header] = merged_value
            puts "Merged #{values.count} values for '#{header}' in row #{row_num}: #{merged_value[0, 100]}#{'...' if merged_value.length > 100}"
          end
        end

        # Check if row should be skipped
        skip_reason = should_skip_row?(row_data, row_num)
        if skip_reason
          record_skipped_row(row_num, row_data, skip_reason)
          # Move to next row even for skipped rows
          row_num += 1
          # Safety check to prevent infinite loops
          break if row_num > 10000
          next
        end

        process_single_row(row_data, row_num)
        @processed_count += 1
        @success_count += 1

        # Update progress every chunk
        if @processed_count % @chunk_size == 0
          update_migration_progress
        end

      rescue => e
        @error_count += 1
        @processed_count += 1
        record_row_error(row_num, row_data || {}, e.message)

        # Log error but continue processing
        Rails.logger.error "Row #{row_num} processing failed: #{e.message}"

        # Move to next row even for error rows
        row_num += 1
        # Safety check to prevent infinite loops
        break if row_num > 10000
        next
      end

      # Move to next row
      row_num += 1

      # Safety check to prevent infinite loops
      break if row_num > 10000
    end

    # Final progress update
    update_migration_progress
  end

  def process_single_row(row_data, row_number)
    # Create issue attributes hash
    issue_attributes = build_issue_attributes(row_data, row_number)

    # Create the issue
    issue = Issue.new(issue_attributes)
    issue.project = migration.project

    # Set author to migration user
    issue.author = migration.user

    # Prepare custom field values before validation
    custom_field_values = prepare_custom_field_values(issue, row_data, row_number)

    puts "Setting custom field values for issue: #{custom_field_values.inspect}"
    issue.custom_field_values = custom_field_values if custom_field_values.any?

    # Debug: Check if custom fields are properly set
    puts "Issue custom field values after setting: #{issue.custom_field_values.inspect}"

    # Validate and save
    unless issue.save
      error_msg = issue.errors.full_messages.join('; ')
      Rails.logger.error "Issue validation failed: #{error_msg}"
      Rails.logger.error "Issue custom field values at failure: #{issue.custom_field_values.inspect}"
      raise "Issue creation failed: #{error_msg}"
    end

    # Track the imported issue ID
    @imported_issue_ids << issue.id

    # Handle attachments after issue creation
    attachment_service = AttachmentDownloadService.new(issue, migration.user)
    attachment_service.process_attachments_from_row(row_data, @field_mapping, row_number)

    puts "Successfully created issue #{issue.id} from row #{row_number}"
  end

  def build_issue_attributes(row_data, row_number)
    attributes = {}

    puts "Processing row #{row_number} with data keys: #{row_data.keys.inspect}"
    puts "Field mapping keys: #{@field_mapping.keys.inspect}"

    # Process field mappings - handle both auto and manual types
    @field_mapping.each do |header, mapping|
      value = row_data[header]

      puts "Processing header '#{header}': value='#{value}', mapping=#{mapping.inspect}"

      next if value.blank?

      # Determine the target field based on mapping type
      target_field = nil
      mapping_type = mapping['type']

      case mapping_type
      when 'auto', 'manual', 'standard'
        # All these types can have standard field mappings
        target_field = mapping['field'] if mapping['field'].present?
      end

      puts "Target field for '#{header}': '#{target_field}'"

      next unless target_field.present?

      # Map the value based on target field
      case target_field
      when 'subject'
        attributes[:subject] = value.to_s.strip
        puts "Set subject: '#{attributes[:subject]}'"
      when 'description'
        attributes[:description] = value.to_s
        puts "Set description: '#{attributes[:description]}'"
      when 'status'
        attributes[:status_id] = find_or_create_status(value)
      when 'priority'
        attributes[:priority_id] = find_or_create_priority(value)
      when 'assignee'
        attributes[:assigned_to_id] = find_user_by_name(value)
      when 'tracker'
        attributes[:tracker_id] = find_or_create_tracker(value)
      when 'due_date'
        attributes[:due_date] = parse_date(value)
      when 'created_on'
        attributes[:created_on] = parse_datetime(value)
      when 'updated_on'
        # Don't set updated_on as it should be handled by Rails
      when 'external_id'
        # Store external ID for reference (not a direct issue attribute)
        attributes[:description] = (attributes[:description] || '') + "\n\nExternal ID: #{value}"
      when 'reporter'
        # Reporter maps to author, but we use migration user as author
        # Could store as description note instead
        attributes[:description] = (attributes[:description] || '') + "\n\nOriginal Reporter: #{value}"
      when 'parent_issue'
        # Handle parent issue relationship (complex, might need separate handling)
        puts "Parent issue mapping for #{header}: #{value}"
      when 'attachment'
        # Skip attachment processing in attributes, will be handled after issue creation
        puts "Attachment field detected for #{header}: #{value}"
      when 'comment'
        # Add comments to description with separator
        if attributes[:description].present?
          attributes[:description] += "\n\n--- Comments ---\n#{value}"
        else
          attributes[:description] = "--- Comments ---\n#{value}"
        end
        puts "Added comments to description for #{header}: #{value[0, 50]}..."
      end
    end

    puts "Attributes before defaults: #{attributes.inspect}"

    # Set defaults in priority order: sheet values -> configuration -> system defaults
    attributes[:subject] ||= "Imported issue from row #{row_number}"

    # Tracker: sheet value -> configuration -> project default -> system first
    attributes[:tracker_id] ||= get_configured_tracker_id || migration.project.trackers.first&.id || Tracker.first.id

    # Status: sheet value -> configuration -> system default
    attributes[:status_id] ||= get_configured_status_id || get_default_status_id

    # Priority: sheet value -> configuration -> system default
    attributes[:priority_id] ||= get_configured_priority_id || get_default_priority_id

    attributes
  end

  def prepare_custom_field_values(issue, row_data, row_number)
    custom_field_values = {}

    # Process mapped custom fields from sheet data
    @field_mapping.each do |header, mapping|
      value = row_data[header]
      next if value.blank?

      mapping_type = mapping['type']

      case mapping_type
      when 'custom'
        # Direct custom field mapping
        custom_field_id = mapping['field_id']
        formatted_value = format_custom_field_value(value, mapping['field_format'])
        custom_field_values[custom_field_id.to_s] = formatted_value

      when 'auto'
        # Auto-detect might create custom fields
        if mapping['custom_field_name'].present?
          # This is an auto-detected custom field
          field_name = mapping['custom_field_name']
          field_format = mapping['custom_field_format'] || 'string'

          # Find or create the custom field
          custom_field = find_or_create_custom_field(field_name, field_format)
          if custom_field
            formatted_value = format_custom_field_value(value, field_format)
            custom_field_values[custom_field.id.to_s] = formatted_value
          end
        end
      end
    end

    # Handle mandatory custom fields that are missing values
    populate_mandatory_custom_fields(custom_field_values, issue)

    custom_field_values
  end

  def ensure_custom_fields_exist
    p "@field_mapping.blank?@field_mapping.blank?@field_mapping.blank?: #{@field_mapping.blank?}"
    return if @field_mapping.blank?

    @field_mapping.each do |header, mapping|
      mapping_type = mapping['type']
      puts "Processing header '#{header}' with type '#{mapping_type}' and mapping: #{mapping.inspect}"
      puts "mapping_type111: #{mapping_type}"
      case mapping_type
      when 'custom'
        # Handle existing custom field mappings
        field_id = mapping['field_id']
        custom_field = CustomField.find_by(id: field_id)
        puts "Found custom field with ID #{field_id}: #{custom_field.inspect}"

        if custom_field.nil?
          # Create missing custom fieldProcessing headerProcessing header
          custom_field = create_custom_field_for_header(header, mapping)

          # Update mapping with new field ID
          @field_mapping[header]['field_id'] = custom_field.id
          migration.update!(field_mapping: @field_mapping.to_json)
        end

        @custom_fields_cache[field_id] = custom_field

      when 'auto'
        # Handle auto-detect custom fields
        if mapping['custom_field_name'].present?
          # Skip if this is an attachment field
          if mapping['field'] == 'attachment'
            puts "Skipping custom field creation for auto-detected attachment: #{header}"
            next
          end

          field_name = mapping['custom_field_name']
          field_format = mapping['custom_field_format'] || 'string'

          # Find or create the custom field
          custom_field = find_or_create_custom_field(field_name, field_format)

          # Update mapping with the actual field ID for future reference
          @field_mapping[header]['field_id'] = custom_field.id
          @custom_fields_cache[custom_field.id] = custom_field
        end

      when 'ignore'
        # Skip ignored columns
        next

      else
        # Handle unmapped columns - create custom fields automatically
        if mapping['field'].blank? && mapping['field_id'].blank?
          # Skip attachment fields - they don't need custom fields
          if mapping['field'] == 'attachment' || header.downcase.include?('attachment')
            puts "Skipping custom field creation for attachment column: #{header}"
            next
          end

          puts "Creating custom field for unmapped column: #{header}"

          # Auto-detect field format based on sample data
          field_format = detect_field_format_from_header(header)
          field_name = sanitize_field_name(header)

          # Create custom field
          custom_field = find_or_create_custom_field(field_name, field_format)

          # Update mapping to reference the new custom field
          @field_mapping[header] = {
            'type' => 'custom',
            'field_id' => custom_field.id,
            'field_name' => field_name,
            'field_format' => field_format
          }

          @custom_fields_cache[custom_field.id] = custom_field
        end
      end
    end

    # Save updated mapping if any changes were made
    migration.update!(field_mapping: @field_mapping.to_json)
  end

  def create_custom_field_for_header(header, mapping)
    field_name = mapping['field_name'] || sanitize_field_name(header)
    field_format = mapping['field_format'] || 'string'

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

    # Enable for project trackers and assign to project
    if migration.project
      custom_field.trackers = migration.project.trackers
      custom_field.projects << migration.project unless custom_field.projects.include?(migration.project)
      custom_field.save!
      puts "Assigned custom field '#{field_name}' to project '#{migration.project.name}' and trackers: #{migration.project.trackers.map(&:name).join(', ')}"
    end

    puts "Created custom field: #{field_name} (#{field_format})"
    custom_field
  end

  # Find or create a custom field by name and format (no session/cookie storage)
  def find_or_create_custom_field(field_name, field_format)
    # Find existing custom field
    custom_field = CustomField.where(name: field_name, type: 'IssueCustomField').first

    unless custom_field
      # Create new custom field
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
      puts "Auto-created custom field: #{field_name} (#{field_format})"
    else
      puts "Found existing custom field: #{field_name}"
    end

    # Ensure custom field is assigned to project and trackers (both new and existing)
    if migration.project
      # Add project if not already assigned
      unless custom_field.projects.include?(migration.project)
        custom_field.projects << migration.project
        puts "Assigned custom field '#{field_name}' to project '#{migration.project.name}'"
      end

      # Add trackers if not already assigned
      missing_trackers = migration.project.trackers - custom_field.trackers
      if missing_trackers.any?
        custom_field.trackers += missing_trackers
        puts "Assigned custom field '#{field_name}' to trackers: #{missing_trackers.map(&:name).join(', ')}"
      end

      custom_field.save!
    else
      puts "Warning: No project assigned to migration, custom field '#{field_name}' may not be visible"
    end

    custom_field
  end

  def find_or_create_status(status_name)
    return get_configured_status_id || get_default_status_id if status_name.blank?

    # Find existing status
    status = IssueStatus.find_by(name: status_name.to_s.strip)

    unless status
      # Create new status from CSV data
      is_closed = status_name.to_s.downcase.match?(/\b(done|closed|completed|resolved|finished)\b/)
      status = IssueStatus.create!(
        name: status_name.to_s.strip,
        is_closed: is_closed
      )
      puts "Created new status from CSV: #{status_name} (closed: #{is_closed})"
    end

    status.id
  end

  def find_or_create_priority(priority_name)
    return get_configured_priority_id || get_default_priority_id if priority_name.blank?

    # Find existing priority
    priority = IssuePriority.find_by(name: priority_name.to_s.strip)

    unless priority
      # Create new priority from CSV data
      priority = IssuePriority.create!(
        name: priority_name.to_s.strip,
        position: IssuePriority.count + 1
      )
      puts "Created new priority from CSV: #{priority_name}"
    end

    priority.id
  end

  def find_or_create_tracker(tracker_name)
    return get_configured_tracker_id || migration.project.trackers.first&.id if tracker_name.blank?

    # First check if tracker exists in this project
    existing_tracker = migration.project.trackers.find_by(name: tracker_name.to_s.strip)
    return existing_tracker.id if existing_tracker

    # Find global tracker
    tracker = Tracker.find_by(name: tracker_name.to_s.strip)

    unless tracker
      # Create new tracker from CSV data
      tracker = Tracker.create!(
        name: tracker_name.to_s.strip,
        default_status: IssueStatus.first || IssueStatus.create!(name: 'New', is_closed: false),
        core_fields: %w[assigned_to_id category_id fixed_version_id priority_id subject description]
      )
      puts "Created new tracker from CSV: #{tracker_name}"
    end

    # Ensure tracker is enabled for this project
    unless migration.project.trackers.include?(tracker)
      migration.project.trackers << tracker
      migration.project.save!
      puts "Enabled tracker '#{tracker_name}' for project '#{migration.project.name}'"
    end

    tracker.id
  end

  def find_user_by_name(user_name)
    return nil if user_name.blank?

    user_name_clean = user_name.to_s.strip

    # Try to find by login first (most reliable)
    user = User.active.find_by(login: user_name_clean)
    return user.id if user

    # Try to find by full name
    user = User.active.where("CONCAT(firstname, ' ', lastname) = ?", user_name_clean).first
    return user.id if user

    # Try to find by email using the email_addresses table join
    user = User.active.joins(:email_addresses).where("email_addresses.address = ?", user_name_clean).first
    return user.id if user

    # If still not found, try partial matches on name fields
    user = User.active.where("login LIKE ? OR firstname LIKE ? OR lastname LIKE ?",
                            "%#{user_name_clean}%", "%#{user_name_clean}%", "%#{user_name_clean}%").first

    user&.id
  end

  def parse_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    return value.to_date if value.is_a?(DateTime)

    Date.parse(value.to_s) rescue nil
  end

  def parse_datetime(value)
    return nil if value.blank?
    return value if value.is_a?(DateTime)
    return value.to_datetime if value.is_a?(Date)

    DateTime.parse(value.to_s) rescue nil
  end

  def format_custom_field_value(value, field_format)
    return value.to_s if value.blank?

    case field_format
    when 'date'
      parse_date(value)&.strftime('%Y-%m-%d')
    when 'bool'
      ['true', '1', 'yes', 'y'].include?(value.to_s.downcase) ? '1' : '0'
    when 'int'
      value.to_i.to_s
    when 'float'
      value.to_f.to_s
    else
      value.to_s
    end
  end

  def sanitize_field_name(header)
    header.to_s.gsub(/[^a-zA-Z0-9\s]/, ' ')
           .split.map(&:capitalize).join(' ')
           .strip
  end

  def record_row_error(row_number, row_data, error_message)
    @errors << {
      row: row_number,
      data: row_data,
      error: error_message,
      timestamp: Time.current
    }
  end

  def record_skipped_row(row_number, row_data, skip_reason)
    @skipped_count += 1
    @skipped_rows << {
      row: row_number,
      data: row_data,
      reason: skip_reason,
      timestamp: Time.current
    }
    puts "Skipped row #{row_number}: #{skip_reason}"
  end

  def should_skip_row?(row_data, row_number)
    # Check if row is completely empty
    if row_data.blank? || row_data.values.compact.all?(&:blank?)
      return "Empty row - no data found"
    end

    # Only skip if subject is missing
    has_subject = row_data.any? { |k, v| k.to_s.downcase.include?('subject') && v.present? }

    unless has_subject
      return "Missing subject field - required for issue creation"
    end

    # Row is valid
    nil
  end

  def update_migration_progress
    migration.update!(
      processed_rows: @processed_count,
      success_rows: @success_count,
      error_rows: @error_count,
      processing_log: migration.processing_log + "\nProgress update: #{@processed_count}/#{migration.total_rows} rows processed"
    )
  end

  def generate_error_report
    return nil if @errors.empty?

    CSV.generate do |csv|
      csv << ['Row Number', 'Error Message', 'Row Data', 'Timestamp']

      @errors.each do |error|
        csv << [
          error[:row],
          error[:error],
          error[:data].to_json,
          error[:timestamp].strftime('%Y-%m-%d %H:%M:%S')
        ]
      end
    end
  end

  def generate_error_summary
    return "No errors" if @errors.empty?

    error_types = @errors.group_by { |e| e[:error].split(':').first }.transform_values(&:count)

    summary = "Total errors: #{@error_count}\n"
    summary += "Error breakdown:\n"
    error_types.each { |type, count| summary += "- #{type}: #{count}\n" }

    summary
  end

  def generate_skipped_summary
    return "No rows skipped" if @skipped_rows.empty?

    skip_reasons = @skipped_rows.group_by { |s| s[:reason] }.transform_values(&:count)

    summary = "Skipped rows breakdown:\n"
    skip_reasons.each { |reason, count| summary += "- #{reason}: #{count} rows\n" }

    if @skipped_rows.any?
      summary += "Skipped row numbers: #{@skipped_rows.map { |s| s[:row] }.join(', ')}"
    end

    summary
  end

  # Determine final migration status based on processing results
  def determine_final_status
    total_rows = migration.total_rows

    if @processed_count == 0
      # No rows processed at all
      'failed'
    elsif @success_count == 0 && @error_count > 0
      # All rows failed
      'failed'
    elsif @error_count == 0
      # All rows succeeded
      'completed'
    elsif @success_count > 0 && @error_count > 0
      # Mixed results - some succeeded, some failed
      if (@success_count.to_f / @processed_count) >= 0.5
        # More than 50% success rate = completed with errors
        'completed'
      else
        # Less than 50% success rate = mostly failed
        'failed'
      end
    else
      # Default fallback
      'completed'
    end
  end

  # Configuration helper methods
  def get_configured_tracker_id
    tracker_id = @processing_options['tracker_id']
    tracker_id.present? && tracker_id.to_i > 0 ? tracker_id.to_i : nil
  end

  def get_configured_status_id
    status_id = @processing_options['status_id']
    status_id.present? && status_id.to_i > 0 ? status_id.to_i : nil
  end

  def get_configured_priority_id
    priority_id = @processing_options['priority_id']
    priority_id.present? && priority_id.to_i > 0 ? priority_id.to_i : nil
  end

  # Default value helper methods
  def get_default_status_id
    # IssueStatus doesn't have a default method, use first available
    IssueStatus.first&.id
  end

  def get_default_priority_id
    # Try default priority, if nil use first available, if none exist create one
    default_priority = IssuePriority.default
    return default_priority.id if default_priority

    first_priority = IssuePriority.first
    return first_priority.id if first_priority

    # If no priorities exist, create a default one
    puts "No priorities found, creating default 'Normal' priority"
    normal_priority = IssuePriority.create!(
      name: 'Normal',
      position: 1,
      is_default: true
    )
    normal_priority.id
  end

  # Populate mandatory custom fields with default values
  def populate_mandatory_custom_fields(custom_field_values, issue)
    begin
      # Get all custom fields for this project and tracker
      project_custom_fields = issue.project.all_issue_custom_fields
      tracker_custom_fields = issue.tracker.custom_fields

      # Find intersection - custom fields available for this issue
      available_custom_fields = project_custom_fields & tracker_custom_fields

      puts "Found #{available_custom_fields.count} custom fields for project #{issue.project.name}, tracker #{issue.tracker.name}"

      available_custom_fields.each do |custom_field|
        puts "Processing custom field: #{custom_field.name} (ID: #{custom_field.id}, required: #{custom_field.is_required?}, format: #{custom_field.field_format})"

        if custom_field.name.downcase.include?('range')
          puts "RANGE FIELD DETAILS: min_length=#{custom_field.try(:min_length)}, max_length=#{custom_field.try(:max_length)}, regexp=#{custom_field.try(:regexp)}"
        end

        next unless custom_field.is_required?

        if custom_field_values[custom_field.id.to_s].present?
          puts "Custom field '#{custom_field.name}' already has value: #{custom_field_values[custom_field.id.to_s]}"
          next
        end

        # Generate default value based on field type
        default_value = generate_default_custom_field_value(custom_field)
        if default_value
          custom_field_values[custom_field.id.to_s] = default_value
          puts "Set default value '#{default_value}' (length: #{default_value.length}) for mandatory custom field '#{custom_field.name}' (ID: #{custom_field.id})"
        else
          Rails.logger.warn "Could not generate default value for mandatory custom field '#{custom_field.name}'"
        end
      end

      puts "Final custom field values: #{custom_field_values}"
    rescue => e
      Rails.logger.error "Error populating mandatory custom fields: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  # Generate appropriate default values for different custom field types
  def generate_default_custom_field_value(custom_field)
    base_value = case custom_field.field_format
    when 'string'
      generate_string_default(custom_field)
    when 'text'
      generate_text_default(custom_field)
    when 'int'
      generate_int_default(custom_field)
    when 'float'
      generate_float_default(custom_field)
    when 'date'
      Date.current.strftime('%Y-%m-%d')
    when 'bool'
      '0' # false
    when 'list'
      # Use first possible value if available
      custom_field.possible_values.first || generate_string_default(custom_field, 'Option')
    when 'enumeration'
      # Use first enumeration value
      custom_field.enumerations.first&.name || generate_string_default(custom_field, 'Default')
    when 'user'
      # Use current user (migration user)
      migration.user.id.to_s
    when 'version'
      # Use project's latest version or create a default one
      migration.project.versions.first&.id&.to_s || 'N/A'
    when 'link'
      'https://example.com/imported-data'
    else
      generate_string_default(custom_field, 'Default')
    end

    puts "Generated value '#{base_value}' for custom field '#{custom_field.name}' (format: #{custom_field.field_format})"
    base_value
  end

  private

  # Generate string value that satisfies length and format requirements
  def generate_string_default(custom_field, prefix = 'Imported')
    base_name = custom_field.name.gsub(/[^a-zA-Z0-9\s]/, '').strip
    base_value = "#{prefix} - #{base_name}"

    # Check minimum length requirement
    if custom_field.min_length && custom_field.min_length > 0
      required_length = custom_field.min_length
      if base_value.length < required_length
        # Pad with meaningful text to meet minimum length
        padding_needed = required_length - base_value.length
        padding = " - Auto-generated during data migration"

        # If still not enough, repeat the padding or add more text
        while base_value.length + padding.length < required_length
          padding += " - Default value"
        end

        base_value += padding
        base_value = base_value[0, required_length] if custom_field.max_length && base_value.length > custom_field.max_length
      end
    end

    # Check maximum length requirement
    if custom_field.max_length && custom_field.max_length > 0 && base_value.length > custom_field.max_length
      base_value = base_value[0, custom_field.max_length]
    end

    # Check regex pattern if exists
    if custom_field.regexp.present?
      begin
        regex = Regexp.new(custom_field.regexp)
        unless base_value.match?(regex)
          # Try some common patterns
          case custom_field.regexp
          when /email/i
            base_value = "imported.data@example.com"
          when /phone/i, /mobile/i
            base_value = "+1-555-0123"
          when /url/i, /http/i
            base_value = "https://example.com"
          when /\d+/
            # Requires numbers
            base_value = "#{base_value} 1234567890"[0, custom_field.max_length || 50]
          else
            # Generic pattern-safe value
            base_value = "DefaultValue123"
            base_value = base_value.ljust(custom_field.min_length || 10, '0') if custom_field.min_length
          end
        end
      rescue RegexpError
        puts "Invalid regexp for custom field #{custom_field.name}: #{custom_field.regexp}"
      end
    end

    base_value
  end

  # Generate text value for text fields
  def generate_text_default(custom_field)
    base_text = "This value was auto-generated during data migration for mandatory field: #{custom_field.name}."

    if custom_field.min_length && custom_field.min_length > base_text.length
      additional_text = " The original data source did not contain a value for this required field, so this default was created to satisfy validation requirements."
      base_text += additional_text

      # If still not long enough, add more descriptive text
      while base_text.length < custom_field.min_length
        base_text += " Additional padding text to meet minimum length requirements."
      end
    end

    if custom_field.max_length && custom_field.max_length > 0 && base_text.length > custom_field.max_length
      base_text = base_text[0, custom_field.max_length - 3] + "..."
    end

    base_text
  end

  # Generate integer value within valid range
  def generate_int_default(custom_field)
    # Check for minimum length requirements (e.g. Range field needs 10 digits)
    base_value = 1

    # Some common field names that might need specific values
    case custom_field.name.downcase
    when /priority/i
      base_value = 1
    when /count/i, /quantity/i
      base_value = 1
    when /percentage/i, /percent/i
      base_value = 0
    when /year/i
      base_value = Date.current.year
    when /range/i
      # Range often needs larger numbers
      base_value = 1000000000  # 10 digits
    else
      base_value = 1
    end

    # Check if the field has minimum length requirements by trying different methods
    min_length = nil

    # Try different ways to get minimum length (Redmine versions vary)
    if custom_field.respond_to?(:min_length)
      min_length = custom_field.min_length
    elsif custom_field.respond_to?(:format) && custom_field.format.respond_to?(:min_length)
      min_length = custom_field.format.min_length
    elsif custom_field.class.method_defined?(:min_length)
      min_length = custom_field.min_length rescue nil
    end

    if min_length && min_length > 0
      required_digits = min_length
      current_digits = base_value.to_s.length

      if current_digits < required_digits
        # Generate a number with the required number of digits
        # Start with 1 followed by zeros to meet minimum length
        base_value = ('1' + '0' * (required_digits - 1)).to_i
        puts "Adjusted integer to #{required_digits} digits for min_length requirement"
      end
    end

    puts "Generated integer #{base_value} (#{base_value.to_s.length} digits) for field '#{custom_field.name}'"
    base_value.to_s
  end

  # Generate float value
  def generate_float_default(custom_field)
    case custom_field.name.downcase
    when /percentage/i, /percent/i
      '0.0'
    when /rate/i
      '1.0'
    when /price/i, /cost/i, /amount/i
      '0.00'
    else
      '1.0'
    end
  end

  # Merge duplicate columns comprehensively
  def merge_duplicate_columns(row_data, row_number)
    # Group all values by header name
    header_values = {}

    row_data.each do |header, value|
      next if value.blank?

      header_key = header.to_s.strip
      header_values[header_key] ||= []
      header_values[header_key] << value.to_s.strip
    end

    # Merge all duplicate columns based on their type
    merged_data = {}
    header_values.each do |header, values|
      next if values.empty?

      if values.count == 1
        # Single value, use as-is
        merged_data[header] = values.first
      else
        # Multiple values, merge based on field type
        merged_value = merge_values_by_type(header, values)
        merged_data[header] = merged_value
        puts "CSV: Merged #{values.count} values for '#{header}' in row #{row_number}: #{merged_value[0, 100]}#{'...' if merged_value.length > 100}"
      end
    end

    merged_data
  end

  # Merge values based on field type/content
  def merge_values_by_type(header, values)
    header_lower = header.to_s.downcase

    # Clean values first
    clean_values = values.map(&:strip).reject(&:blank?)
    return '' if clean_values.empty?
    return clean_values.first if clean_values.count == 1

    case header_lower
    when 'attachment', 'attachments'
      # Comma-separated for URLs
      clean_values.join(', ')
    when 'comment', 'comments', 'note', 'notes'
      # Double newlines for readability
      clean_values.join("\n\n")
    when 'description', 'summary'
      # Double newlines for readability
      clean_values.join("\n\n")
    when 'reviewer', 'reviewers', 'assignee', 'assignees'
      # Comma-separated for names
      clean_values.join(', ')
    when 'tag', 'tags', 'label', 'labels', 'category', 'categories'
      # Comma-separated for tags
      clean_values.join(', ')
    when /email|mail/
      # Comma-separated for emails
      clean_values.join(', ')
    when /url|link/
      # Space-separated for URLs
      clean_values.join(' ')
    when /date/
      # Use the latest date
      clean_values.last
    when /id|number/
      # Use the first ID
      clean_values.first
    else
      # Default: pipe-separated to clearly show multiple values
      clean_values.join(' | ')
    end
  end

  # Detect field format based on header name patterns
  def detect_field_format_from_header(header)
    header_lower = header.to_s.downcase

    case header_lower
    when /date|created|updated|due|delivery|completion/
      'date'
    when /attachment|file|document/
      'link'  # Treat attachments as links for URL storage
    when /url|link/
      'link'
    when /description|comment|note|detail/
      'text'
    when /count|quantity|hours|version|id/
      'int'
    when /percentage|percent|rate|price|cost|amount/
      'float'
    when /status|priority|type|category/
      'string'  # Could be 'list' but string is safer for validation
    else
      'string'  # Default safe option
    end
  end
end