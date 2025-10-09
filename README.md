# Redmine Data Migrator Pro

Advanced data migration plugin for importing CSV, XLS, XLSX files from Jira, ClickUp, Asana, Trello, Monday.com and other PM tools into Redmine.

## Features

- **Universal PM Tool Support**: Import from any PM tool with External Asset Config management
- **Multiple Background Job Processors**: Choose between Cron, Delayed Job, Sidekiq, or Active Job
- **External Asset Configuration**: Secure credential management for JIRA, ClickUp, Asana, Trello, Monday.com APIs
- **Automatic Custom Field Creation**: Detects and creates custom fields for unmapped columns
- **Row-by-Row Tracking**: Processes every row with detailed progress tracking
- **Large File Support**: Chunked processing for handling large datasets
- **Comprehensive Error Reporting**: Detailed error reports with CSV export
- **Connection Testing**: Test API connections before processing
- **Migration Rollback**: Rollback completed migrations if needed

## Installation

1. Copy the plugin to your Redmine plugins directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone <repository_url> redmine_data_migrator_pro
   ```

2. Install dependencies:
   ```bash
   cd /path/to/redmine
   bundle install
   ```

3. Run database migration:
   ```bash
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate
   ```

4. Restart Redmine

5. Configure plugin settings:
   - Go to **Administration → Plugins → Data Migrator Pro → Configure**
   - Choose your preferred background job processor
   - Set processing options (chunk size, file limits, etc.)

## Background Job Configuration

### Supported Job Processors

Choose from multiple background job processors based on your environment:

#### 1. Cron Jobs (Default)
Traditional cron-based processing - no additional dependencies required.

```bash
# Edit crontab
crontab -e

# Add these lines (adjust path to your Redmine installation):
# Process migrations every 5 minutes
*/5 * * * * cd /path/to/redmine && RAILS_ENV=production bundle exec rake data_migration:process_pending >> log/data_migration.log 2>&1

# Cleanup old migrations daily at 2 AM
0 2 * * * cd /path/to/redmine && RAILS_ENV=production bundle exec rake data_migration:cleanup_old >> log/data_migration.log 2>&1
```

#### 2. Delayed Job
Database-backed job queue - requires delayed_job gem.

```ruby
# Add to Gemfile
gem 'delayed_job_active_record'

# Run setup
bundle install
rails generate delayed_job:active_record
rake db:migrate

# Start workers
RAILS_ENV=production bundle exec rake jobs:work
```

#### 3. Sidekiq
Redis-backed job queue - requires sidekiq gem and Redis server.

```ruby
# Add to Gemfile
gem 'sidekiq'

# Install and start Redis
# Ubuntu/Debian: apt-get install redis-server
# MacOS: brew install redis

# Start Sidekiq
RAILS_ENV=production bundle exec sidekiq
```

#### 4. Active Job
Rails built-in job framework - configure your preferred adapter.

```ruby
# config/application.rb
config.active_job.queue_adapter = :delayed_job  # or :sidekiq, :resque, etc.
```

## Usage

### 1. Configure External Assets (Optional)
If importing from external PM tools via API:
- Go to **Administration → External Asset Configs**
- Click **New Configuration**
- Select system type (Jira, ClickUp, Asana, etc.)
- Enter API credentials and base URL
- Test connection to verify setup

### 2. Import Data
- Go to **Administration → Data Migrator**
- Upload your CSV/XLS/XLSX file
- Select associated External Asset Config (if applicable)
- Review field mapping and processing options
- Submit for background processing

### 3. Monitor Progress
- View processing status on the main Data Migrator page
- Check current job processor status
- Download error reports for failed imports
- Use rollback feature if needed

## Supported File Formats

- CSV files with headers
- Excel files (.xls, .xlsx) with headers
- Any PM tool export format

## Supported PM Tools

- **Jira**: Issues, stories, tasks, bugs
- **ClickUp**: Tasks, lists, folders
- **Asana**: Tasks, projects, sections
- **Trello**: Cards, boards, lists
- **Monday.com**: Items, boards, groups
- **Custom**: Any CSV/Excel format

## Field Mapping

### Standard Fields (Auto-mapped)
- Subject, Description, Status, Priority
- Assignee, Reporter, Tracker
- Created Date, Updated Date, Due Date
- Parent Task, Versions, Application

### Custom Fields (Auto-created)
- Any unmapped column becomes a custom field
- Supports all Redmine custom field types
- Automatically detects field type based on content

## Rake Tasks

### General Tasks
```bash
# Show migration status
rake data_migration:status

# Show job processor status and configuration
rake data_migration:processor_status

# Process specific migration by ID
rake data_migration:process_single[123]
```

### Cron-specific Tasks
```bash
# Process pending migrations (for cron processor)
rake data_migration:process_pending

# Clean up old completed/failed migrations (for cron processor)
rake data_migration:cleanup_old
```

### Cross-processor Tasks
```bash
# Queue cleanup job using configured processor
rake data_migration:queue_cleanup
```

## Configuration

### Plugin Settings
Go to **Administration → Plugins → Data Migrator Pro → Configure**:

#### Background Job Processing
- **Job Processor**: Choose from Cron, Delayed Job, Sidekiq, or Active Job
- **Chunk Size**: Number of rows to process per batch (10-1000, default: 100)
- **Max File Size**: Maximum upload size in MB (1-500, default: 50)
- **Cleanup Days**: Delete completed/failed migrations after N days (1-365, default: 30)

#### External Asset Configurations
- **System Type**: JIRA, ClickUp, Asana, Trello, Monday.com
- **Base URL**: API endpoint URL for the external system
- **Credentials**: API tokens, keys, and authentication details
- **Connection Testing**: Verify API connectivity before processing

### Processing Options (Per Migration)
- **Project Assignment**: Target Redmine project
- **Default Tracker**: Issue tracker for imported items
- **Default Status**: Initial status for imported issues
- **Default Priority**: Priority level for imported issues
- **Field Mapping**: Map external fields to Redmine fields

## Troubleshooting

### Check System Status
```bash
cd /path/to/redmine

# Check overall migration status
RAILS_ENV=production bundle exec rake data_migration:status

# Check job processor configuration
RAILS_ENV=production bundle exec rake data_migration:processor_status
```

### View Logs
```bash
# Application logs
tail -f log/production.log

# Data migration specific logs
tail -f log/data_migration.log

# Job processor logs (if using Sidekiq)
tail -f log/sidekiq.log
```

### Common Issues

#### 1. Jobs Not Processing
- Check job processor status in plugin settings
- Verify background workers are running (for Delayed Job/Sidekiq)
- Confirm cron jobs are configured (for cron processor)

#### 2. External Asset Connection Failures
- Test connection in External Asset Config
- Verify API credentials and base URL
- Check network connectivity to external systems

#### 3. Large File Processing Issues
- Increase chunk size in plugin settings
- Check available memory and disk space
- Consider using Sidekiq for better performance

#### 4. Permission Errors
- Ensure user has admin privileges
- Check file system permissions for uploads directory
- Verify database permissions for migrations

## File Structure Requirements

Ensure your export files have:
1. **Headers in first row**
2. **Data starting from second row**
3. **UTF-8 encoding** (recommended)
4. **Consistent column structure**

## Security Features

- **Admin-only Access**: All functionality restricted to Redmine administrators
- **Encrypted Credentials**: API tokens and keys stored with Base64 encoding
- **File Validation**: Upload validation and sanitization
- **Temporary File Cleanup**: Automatic cleanup of processed files
- **Error Log Sanitization**: Sensitive data filtered from logs
- **Connection Testing**: Secure API connection validation

## API Integration

### Supported External Systems
- **JIRA**: REST API v2/v3 with token authentication
- **ClickUp**: API v2 with personal access tokens
- **Asana**: REST API with personal access tokens
- **Trello**: REST API with API key + token
- **Monday.com**: API v2 with API keys

### Authentication Methods
- API Tokens (JIRA, ClickUp, Asana)
- API Key + Token (Trello)
- API Keys (Monday.com)
- Team/Organization IDs (for multi-tenant systems)

## Performance Optimization

### Recommended Job Processors by Scale
- **Small installations** (< 1000 issues): Cron Jobs
- **Medium installations** (1000-10000 issues): Delayed Job
- **Large installations** (> 10000 issues): Sidekiq
- **Enterprise installations**: Active Job with Sidekiq adapter

### Tuning Parameters
- **Chunk Size**: Start with 100, increase for better performance
- **File Size Limits**: Adjust based on server capacity
- **Cleanup Schedule**: Balance storage vs. audit trail needs

## License

This plugin is licensed under the MIT License.

## Support

For issues, feature requests, and contributions:
- Create issues in the project repository
- Follow the established coding standards
- Include test cases for new features