require 'net/http'
require 'uri'
require 'tempfile'

class AttachmentDownloadService
  attr_reader :issue, :user, :errors, :external_config

  def initialize(issue, user, external_config = nil)
    @issue = issue
    @user = user
    @external_config = external_config
    @errors = []
  end

  # Process all attachment fields for an issue from row data
  def process_attachments_from_row(row_data, field_mapping, row_number)
    puts "DEBUG1111 - Row #{row_number} data keys: #{row_data.keys.inspect}"
    puts "DEBUG111 - Field mapping keys: #{field_mapping.keys.inspect}"
    puts "DEBUG - Field mapping content: #{field_mapping.inspect}"

    attachment_fields = find_attachment_fields(row_data, field_mapping)

    puts "Found111 #{attachment_fields.count} attachment field(s) for row #{row_number} #{attachment_fields.inspect}"

    return if attachment_fields.empty?

    puts "Found #{attachment_fields.count} attachment field(s) for row #{row_number}"

    attachment_fields.each_with_index do |attachment_info, field_index|
      begin
        # Handle multiple URLs in a single cell (separated by commas, newlines, or spaces)
        urls = extract_urls_from_text(attachment_info[:value])

        if urls.empty?
          puts "No valid URLs found in attachment field #{attachment_info[:header]}: #{attachment_info[:value]}"
          next
        end

        puts "Processing #{urls.count} URL(s) from field '#{attachment_info[:header]}'"

        urls.each_with_index do |url, url_index|
          # Create unique field name for multiple URLs
          field_name = attachment_info[:header]
          if urls.count > 1
            field_name += "_#{url_index + 1}"
          end

          download_and_attach_file(url, field_name, row_number)
        end

      rescue => e
        error_msg = "Failed to process attachment field #{attachment_info[:header]} (#{attachment_info[:value]}): #{e.message}"
        @errors << error_msg
        puts error_msg
        Rails.logger.error "Attachment processing error for issue #{@issue.id}: #{e.message}"
      end
    end
  end

  # Download a single file from URL and attach to the issue
  def download_and_attach_file(file_url, field_name = nil, row_number = nil)
    return false unless valid_url?(file_url)

    puts "Downloading attachment from: #{file_url}"

    uri = URI.parse(file_url)
    response = fetch_file(uri)

    # Handle redirects (common for Jira attachments)
    if response.code == '303' || response.code == '302' || response.code == '301'
      redirect_location = response['location']
      if redirect_location
        puts "Following redirect to: #{redirect_location}"
        redirect_uri = URI.parse(redirect_location)
        # For Atlassian media service, don't add authentication as it uses token in URL
        response = fetch_file_without_auth(redirect_uri)
      else
        error_msg = "Redirect response without location header: HTTP #{response.code}"
        @errors << error_msg
        puts error_msg
        return false
      end
    end

    unless response.code == '200'
      error_msg = case response.code
      when '401'
        "Failed to download attachment: HTTP 401 - Authentication required for #{uri.host}"
      when '403'
        "Failed to download attachment: HTTP 403 - Access forbidden for #{uri.host}. Check authentication credentials."
      when '404'
        "Failed to download attachment: HTTP 404 - File not found at #{file_url}"
      else
        "Failed to download attachment: HTTP #{response.code} - #{response.message}"
      end

      @errors << error_msg
      puts error_msg

      # For Jira 403 errors, provide specific guidance
      if response.code == '403' && uri.host.include?('atlassian.net')
        puts "For Jira Cloud attachments, you need to set environment variables:"
        puts "JIRA_EMAIL=your-email@domain.com"
        puts "JIRA_API_TOKEN=your-api-token"
        puts "Generate API token at: https://id.atlassian.com/manage-profile/security/api-tokens"
      end

      return false
    end

    filename = extract_filename(uri, field_name, row_number)
    content_type = response['content-type'] || 'application/octet-stream'

    create_attachment(response.body, filename, content_type)
  end

  private

  # Extract multiple URLs from text (handles comma, newline, space separated URLs)
  def extract_urls_from_text(text)
    return [] unless text.present?

    # Convert to string and split by common separators
    text_str = text.to_s.strip

    # Split by common separators (comma, semicolon, newline, tab, multiple spaces)
    potential_urls = text_str.split(/[,;\n\t\s]+/).map(&:strip).reject(&:blank?)

    # Filter only valid URLs
    valid_urls = potential_urls.select { |url| valid_url?(url) }

    # If no valid URLs found by splitting, check if the whole text is a URL
    if valid_urls.empty? && valid_url?(text_str)
      valid_urls = [text_str]
    end

    puts "Extracted #{valid_urls.count} valid URLs from: #{text_str[0, 100]}#{'...' if text_str.length > 100}"
    valid_urls
  end

  # Find attachment fields from field mapping and raw data
  def find_attachment_fields(row_data, field_mapping)
    attachment_fields = []

    # Check field mapping first
    field_mapping.each do |header, mapping|
      value = row_data[header]
      next if value.blank?

      mapping_type = mapping['type']
      target_field = mapping['field'] if mapping['field'].present?

      if mapping_type == 'attachment' || target_field == 'attachment'
        attachment_fields << { header: header, value: value }
      end
    end

    # Also check for any column with 'attachment' in name that contains URLs
    row_data.each do |header, value|
      next if value.blank?
      next if attachment_fields.any? { |af| af[:header] == header }

      if header.downcase.include?('attachment') && valid_url?(value)
        attachment_fields << { header: header, value: value }
      end
    end

    attachment_fields
  end

  # Validate if URL is properly formatted
  def valid_url?(url)
    return false unless url.present?
    return false unless url.match?(/^https?:\/\//)

    begin
      URI.parse(url)
      true
    rescue URI::InvalidURIError
      false
    end
  end

  # Fetch file from URL with timeout and error handling
  def fetch_file(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.read_timeout = 30 # 30 seconds timeout
      http.open_timeout = 10 # 10 seconds connection timeout

      # Create the request
      request = Net::HTTP::Get.new("#{uri.path}#{uri.query ? '?' + uri.query : ''}")

      # Add authentication for known services
      add_authentication(request, uri)

      http.request(request)
    end
  end

  # Fetch file from URL without authentication (for redirected URLs with tokens)
  def fetch_file_without_auth(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.read_timeout = 30 # 30 seconds timeout
      http.open_timeout = 10 # 10 seconds connection timeout

      # Create the request without authentication
      request = Net::HTTP::Get.new("#{uri.path}#{uri.query ? '?' + uri.query : ''}")
      puts "Making request without auth to: #{uri.host}"

      http.request(request)
    end
  end

  # Add authentication headers based on the URL
  def add_authentication(request, uri)
    host = uri.host.to_s.downcase

    # Try external config first if it matches the system type
    if @external_config
      case @external_config.system_type
      when 'jira'
        if host.match?(/atlassian\.net$/) || host.match?(/jira/)
          add_jira_auth(request, uri)
          return
        end
      when 'clickup'
        if host.match?(/clickup\.com$/)
          add_clickup_auth(request, uri)
          return
        end
      when 'asana'
        if host.match?(/asana\.com$/)
          add_asana_auth(request, uri)
          return
        end
      when 'trello'
        if host.match?(/trello\.com$/)
          add_trello_auth(request, uri)
          return
        end
      when 'monday'
        if host.match?(/monday\.com$/)
          add_monday_auth(request, uri)
          return
        end
      end
    end

    # Default authentication based on host
    case host
    when /atlassian\.net$/, /jira/
      add_jira_auth(request, uri)
    when /clickup\.com$/
      add_clickup_auth(request, uri)
    when /asana\.com$/
      add_asana_auth(request, uri)
    when /trello\.com$/
      add_trello_auth(request, uri)
    when /monday\.com$/
      add_monday_auth(request, uri)
    when /github\.com$/
      add_github_auth(request, uri)
    when /gitlab\.com$/
      add_gitlab_auth(request, uri)
    else
      # Try basic auth from URL if present
      if uri.userinfo
        request.basic_auth(uri.user, uri.password)
        puts "Using basic auth from URL for #{host}"
      end
    end
  end

  # Add Jira authentication using API token with basic auth
  def add_jira_auth(request, uri)
    # Try external config first, then fallback to environment variables
    if @external_config&.system_type == 'jira' && @external_config.credentials_configured?
      credentials = @external_config.get_auth_credentials
      request.basic_auth(credentials[:email], credentials[:api_token])
      puts "Using Jira auth from external config: #{credentials[:email].gsub(/@.+/, '@***')}"
    elsif ENV['JIRA_EMAIL'] && ENV['JIRA_API_TOKEN']
      # Fallback to environment variables
      jira_email = ENV['JIRA_EMAIL']
      jira_token = ENV['JIRA_API_TOKEN']

      if jira_token != 'your-jira-api-token-here'
        request.basic_auth(jira_email, jira_token)
        puts "Using Jira basic auth from environment: #{jira_email.gsub(/@.+/, '@***')}"
      else
        add_fallback_auth(request, uri, 'Jira')
      end
    elsif uri.userinfo
      # Basic auth from URL if credentials not configured
      request.basic_auth(uri.user, uri.password)
      puts "Using basic auth from URL for Jira"
    else
      add_fallback_auth(request, uri, 'Jira')
    end
  end

  # Add ClickUp authentication
  def add_clickup_auth(request, uri)
    if @external_config&.system_type == 'clickup' && @external_config.credentials_configured?
      credentials = @external_config.get_auth_credentials
      request['Authorization'] = credentials[:api_key]
      puts "Using ClickUp auth from external config"
    else
      add_fallback_auth(request, uri, 'ClickUp')
    end
  end

  # Add Asana authentication
  def add_asana_auth(request, uri)
    if @external_config&.system_type == 'asana' && @external_config.credentials_configured?
      credentials = @external_config.get_auth_credentials
      request['Authorization'] = "Bearer #{credentials[:api_token]}"
      puts "Using Asana auth from external config"
    else
      add_fallback_auth(request, uri, 'Asana')
    end
  end

  # Add Trello authentication
  def add_trello_auth(request, uri)
    if @external_config&.system_type == 'trello' && @external_config.credentials_configured?
      credentials = @external_config.get_auth_credentials
      # Trello uses API key and token as query parameters
      connector = uri.query ? '&' : '?'
      # Note: For Trello, the URI modification should happen at the request level
      # This is a placeholder - actual implementation may need URI reconstruction
      puts 'Using Trello auth from external config'
      puts "Note: Trello authentication requires URL modification with key=#{credentials[:api_key]}"
    else
      add_fallback_auth(request, uri, 'Trello')
    end
  end

  # Add Monday.com authentication
  def add_monday_auth(request, uri)
    if @external_config&.system_type == 'monday' && @external_config.credentials_configured?
      credentials = @external_config.get_auth_credentials
      request['Authorization'] = credentials[:api_key]
      puts "Using Monday.com auth from external config"
    else
      add_fallback_auth(request, uri, 'Monday.com')
    end
  end

  # Add GitHub authentication (if needed)
  def add_github_auth(request, uri)
    github_token = ENV['GITHUB_TOKEN'] || get_setting('github_token')
    if github_token
      request['Authorization'] = "token #{github_token}"
      puts "Using GitHub token authentication"
    end
  end

  # Add GitLab authentication (if needed)
  def add_gitlab_auth(request, uri)
    gitlab_token = ENV['GITLAB_TOKEN'] || get_setting('gitlab_token')
    if gitlab_token
      request['Authorization'] = "Bearer #{gitlab_token}"
      puts "Using GitLab token authentication"
    end
  end

  # Fallback authentication handler
  def add_fallback_auth(request, uri, system_name)
    if uri.userinfo
      request.basic_auth(uri.user, uri.password)
      puts "Using basic auth from URL for #{system_name}"
    else
      puts "WARNING: #{system_name} authentication not configured!"
      puts "Please configure external asset configuration or use environment variables"
    end
  end

  # Get setting from Redmine (implement based on your settings structure)
  def get_setting(key)
    # This would depend on how you store plugin settings
    # For now, return nil - you can implement based on your needs
    nil
  end

  # Extract filename from URL or generate one
  def extract_filename(uri, field_name = nil, row_number = nil)
    filename = File.basename(uri.path)

    # If no filename in URL or it's just a path, generate a name
    if filename.blank? || filename == '/' || !filename.include?('.')
      base_name = field_name || 'attachment'
      row_suffix = row_number ? "_row_#{row_number}" : ''
      extension = guess_extension_from_path(uri.path)
      filename = "#{base_name}#{row_suffix}#{extension}"
    end

    # Sanitize filename
    sanitize_filename(filename)
  end

  # Guess file extension from URL path or default to .txt
  def guess_extension_from_path(path)
    ext = File.extname(path)
    return ext if ext.present?

    # Common patterns in URL paths
    case path.downcase
    when /\.(jpg|jpeg|png|gif|bmp|svg)(\?|$)/
      '.jpg'
    when /\.(pdf)(\?|$)/
      '.pdf'
    when /\.(doc|docx)(\?|$)/
      '.doc'
    when /\.(xls|xlsx)(\?|$)/
      '.xls'
    when /\.(zip|rar|7z)(\?|$)/
      '.zip'
    else
      '.txt'
    end
  end

  # Sanitize filename for filesystem compatibility
  def sanitize_filename(filename)
    # Remove or replace problematic characters
    sanitized = filename.gsub(/[^\w\-_.()]/, '_')

    # Ensure it's not too long
    if sanitized.length > 100
      ext = File.extname(sanitized)
      base = File.basename(sanitized, ext)
      sanitized = "#{base[0, 95]}#{ext}"
    end

    sanitized
  end

  # Create Redmine attachment from file data
  def create_attachment(file_data, filename, content_type)
    temp_file = nil

    begin
      puts "Creating attachment: #{filename} (#{content_type}) - #{file_data.length} bytes"

      # Create temporary file
      temp_file = Tempfile.new(['attachment', File.extname(filename)])
      temp_file.binmode
      temp_file.write(file_data)
      temp_file.rewind

      # Create Redmine attachment with explicit file handling
      attachment = Attachment.new(
        container: @issue,
        filename: filename,
        content_type: content_type,
        author: @user,
        filesize: file_data.length
      )

      # Manually set the file content to avoid S3 issues
      attachment.file = temp_file

      # Save with error handling
      if attachment.save
        puts "Successfully attached file: #{filename} to issue #{@issue.id} (#{attachment.id})"
        true
      else
        error_msg = "Failed to attach file: #{attachment.errors.full_messages.join(', ')}"
        @errors << error_msg
        puts error_msg

        # Try alternative approach if standard save fails
        puts "Attempting alternative attachment creation..."
        begin
          # Create attachment without using carrierwave/S3
          attachment_alt = create_attachment_alternative(file_data, filename, content_type)
          if attachment_alt
            puts "Successfully created attachment using alternative method"
            true
          else
            false
          end
        rescue => e2
          puts "Alternative method also failed: #{e2.message}"
          false
        end
      end

    rescue => e
      error_msg = "Error creating attachment #{filename}: #{e.message}"
      @errors << error_msg
      puts error_msg
      Rails.logger.error "Attachment creation error for issue #{@issue.id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"

      # If it's an AWS error, skip the attachment but don't fail the whole process
      if e.message.include?('AWS') || e.message.include?('region')
        puts "Skipping attachment due to AWS configuration issue - continuing with issue creation"
        return true  # Don't fail the entire process for attachment issues
      end

      false
    ensure
      if temp_file
        temp_file.close
        temp_file.unlink
      end
    end
  end

  # Alternative attachment creation method
  def create_attachment_alternative(file_data, filename, content_type)
    # Save file directly to Redmine's files directory
    files_dir = Rails.root.join('files')
    FileUtils.mkdir_p(files_dir) unless Dir.exist?(files_dir)

    # Generate unique filename
    unique_filename = "#{Time.current.to_i}_#{SecureRandom.hex(8)}_#{filename}"
    file_path = files_dir.join(unique_filename)

    # Write file
    File.open(file_path, 'wb') do |f|
      f.write(file_data)
    end

    # Create attachment record manually
    attachment = Attachment.create!(
      container: @issue,
      filename: filename,
      disk_filename: unique_filename,
      content_type: content_type,
      author: @user,
      filesize: file_data.length,
      created_on: Time.current
    )

    puts "Created attachment using alternative method: #{attachment.id}"
    attachment
  end
end