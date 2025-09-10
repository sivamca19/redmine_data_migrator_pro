# External Asset Configuration model for accessing JIRA, ClickUp, and other PM tool assets
# Stores encrypted credentials for secure access to external attachment/file systems
class ExternalAssetConfig < ActiveRecord::Base
  SUPPORTED_SYSTEMS = %w[jira clickup asana trello monday].freeze
  STATUSES = %w[active inactive].freeze

  # Virtual attributes for form handling
  attr_accessor :email, :api_token, :api_key, :team_id, :additional_config

  belongs_to :project, optional: true
  has_many :data_migrations

  validates :name, presence: true, uniqueness: true
  validates :system_type, presence: true, inclusion: { in: SUPPORTED_SYSTEMS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :base_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  scope :active, -> { where(status: 'active') }
  scope :by_system_type, ->(type) { where(system_type: type) }
  scope :by_project, ->(project) { where(project: project) }

  # Encrypt sensitive fields
  before_save :encrypt_credentials
  after_find :decrypt_credentials

  def display_name
    project_name = project ? " (#{project.name})" : ""
    "#{name}#{project_name}"
  end

  def system_type_humanized
    system_type.humanize
  end

  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  # Get configuration for specific system and project
  def self.for_migration(system_type, project = nil)
    configurations = active.by_system_type(system_type)
    configurations = configurations.by_project(project) if project
    configurations.first
  end

  # Test connection to external system
  def test_connection
    case system_type
    when 'jira'
      test_jira_connection
    when 'clickup'
      test_clickup_connection
    else
      { success: false, message: "Connection test not implemented for #{system_type}" }
    end
  end

  def credentials_configured?
    # For persisted records, check if encrypted credentials exist
    if persisted?
      return encrypted_credentials.present? && has_required_credentials_in_storage?
    end

    # For new records, check virtual attributes
    case system_type
    when 'jira'
      email.present? && api_token.present?
    when 'clickup'
      api_key.present?
    when 'asana'
      api_token.present?
    when 'trello'
      api_key.present? && api_token.present?
    when 'monday'
      api_key.present?
    else
      true
    end
  end

  # Get credentials for AttachmentDownloadService
  def get_auth_credentials
    {
      email: email,
      api_token: api_token,
      api_key: api_key,
      base_url: base_url,
      system_type: system_type
    }
  end

  # Public method to load credentials into virtual attributes
  def load_credentials_to_attributes
    decrypt_credentials if encrypted_credentials.present?
  end

  private

  def has_required_credentials_in_storage?
    return false unless encrypted_credentials.present?

    begin
      decrypted = decrypt_sensitive_data(encrypted_credentials)
      return false unless decrypted.is_a?(Hash)
      
      case system_type
      when 'jira'
        email_present = decrypted['email'].to_s.strip.present?
        token_present = decrypted['api_token'].to_s.strip.present?
        email_present && token_present
      when 'clickup'
        decrypted['api_key'].to_s.strip.present?
      when 'asana'
        decrypted['api_token'].to_s.strip.present?
      when 'trello'
        api_key_present = decrypted['api_key'].to_s.strip.present?
        token_present = decrypted['api_token'].to_s.strip.present?
        api_key_present && token_present
      when 'monday'
        decrypted['api_key'].to_s.strip.present?
      else
        true
      end
    rescue StandardError => e
      Rails.logger.error "Failed to check stored credentials for asset config #{id}: #{e.message}"
      false
    end
  end

  def encrypt_credentials
    return unless changed?

    # Start with existing encrypted data if available
    existing_data = {}
    if encrypted_credentials.present?
      begin
        existing_data = decrypt_sensitive_data(encrypted_credentials)
      rescue StandardError => e
        Rails.logger.error "Failed to decrypt existing credentials during save: #{e.message}"
      end
    end

    # Merge with current virtual attributes, only overwriting when values are provided
    new_data = existing_data.dup
    %w[email api_token api_key team_id additional_config].each do |field|
      value = send(field)
      # Only update if value is not nil and not an empty string
      # This preserves existing values when fields are left blank
      if value.present?
        new_data[field] = value
      elsif value == '' && !existing_data.key?(field)
        # For new records, empty strings should be stored
        new_data[field] = value
      end
      # If value is nil or blank and existing_data has the field, keep existing value
    end

    self.encrypted_credentials = encrypt_sensitive_data(new_data)
  end

  def decrypt_credentials
    return unless encrypted_credentials.present?

    begin
      decrypted = decrypt_sensitive_data(encrypted_credentials)
      self.email = decrypted['email']
      self.api_token = decrypted['api_token']
      self.api_key = decrypted['api_key']
      self.team_id = decrypted['team_id']
      self.additional_config = decrypted['additional_config']
    rescue => e
      Rails.logger.error "Failed to decrypt credentials for asset config #{id}: #{e.message}"
    end
  end

  def encrypt_sensitive_data(data)
    # Simple Base64 encoding - in production, use Rails.application.secret_key_base
    Base64.strict_encode64(data.to_json)
  end

  def decrypt_sensitive_data(encrypted_data)
    # Simple Base64 decoding - in production, use proper decryption
    JSON.parse(Base64.strict_decode64(encrypted_data))
  end

  def test_jira_connection
    return { success: false, message: "Email and API token required" } unless credentials_configured?

    begin
      uri = URI("#{base_url}/rest/api/2/myself")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(email, api_token)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      if response.code == '200'
        user_data = JSON.parse(response.body)
        { success: true, message: "Connected successfully as #{user_data['displayName']}" }
      else
        { success: false, message: "HTTP #{response.code}: #{response.message}" }
      end
    rescue => e
      { success: false, message: "Connection failed: #{e.message}" }
    end
  end

  def test_clickup_connection
    return { success: false, message: "API key required" } unless credentials_configured?

    begin
      uri = URI("#{base_url}/api/v2/user")
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = api_key

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      if response.code == '200'
        user_data = JSON.parse(response.body)
        { success: true, message: "Connected successfully as #{user_data['user']['username']}" }
      else
        { success: false, message: "HTTP #{response.code}: #{response.message}" }
      end
    rescue => e
      { success: false, message: "Connection failed: #{e.message}" }
    end
  end

end