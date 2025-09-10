# Redmine Data Migrator Pro

Advanced data migration plugin for importing CSV, XLS, XLSX files from Jira, ClickUp, Asana, Trello, Monday.com and other PM tools into Redmine.

## Features

- **Universal PM Tool Support**: Import from any PM tool (Jira, ClickUp, Asana, Trello, etc.)
- **Automatic Custom Field Creation**: Detects and creates custom fields for unmapped columns
- **Row-by-Row Tracking**: Processes every row with detailed progress tracking
- **Large File Support**: Chunked processing for handling large datasets
- **Comprehensive Error Reporting**: Detailed error reports with CSV export
- **Cron-Based Processing**: Background processing without ActiveJob dependency

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

## Cron Job Setup

Add these cron jobs to process migrations automatically:

```bash
# Edit crontab
crontab -e

# Add these lines (adjust path to your Redmine installation):

# Process migrations every 5 minutes
*/5 * * * * cd /path/to/redmine && RAILS_ENV=production bundle exec rake data_migration:process >> log/data_migration.log 2>&1

# Cleanup old migrations daily at 2 AM
0 2 * * * cd /path/to/redmine && RAILS_ENV=production bundle exec rake data_migration:cleanup >> log/data_migration.log 2>&1

# Reset stuck migrations every hour
0 * * * * cd /path/to/redmine && RAILS_ENV=production bundle exec rake data_migration:reset_stuck >> log/data_migration.log 2>&1
```

## Usage

1. **Access the Plugin**: Go to Administration → Data Migrator
2. **Upload File**: Select your PM tool type and upload CSV/XLS/XLSX file
3. **Map Fields**: Review detected fields and configure mapping
4. **Process**: Submit for processing - cron job will handle the import
5. **Monitor**: Check progress and download error reports if needed

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

```bash
# Process pending migrations
rake data_migration:process

# Show migration status
rake data_migration:status

# Clean up old data
rake data_migration:cleanup

# Reset stuck migrations
rake data_migration:reset_stuck
```

## Configuration

Configure chunk size and other options in the UI:
- **Chunk Size**: Number of rows to process per batch (default: 100)
- **File Size Limit**: Maximum upload size
- **Custom Field Creation**: Enable/disable automatic custom field creation

## Troubleshooting

### Check Migration Status
```bash
cd /path/to/redmine
RAILS_ENV=production bundle exec rake data_migration:status
```

### View Logs
```bash
tail -f log/data_migration.log
```

### Reset Stuck Migrations
```bash
RAILS_ENV=production bundle exec rake data_migration:reset_stuck
```

## File Structure Requirements

Ensure your export files have:
1. **Headers in first row**
2. **Data starting from second row**
3. **UTF-8 encoding** (recommended)
4. **Consistent column structure**

## Security

- Admin-only access
- File validation and sanitization
- Temporary file cleanup
- Error log sanitization

## Support

For issues and feature requests, please contact the development team.