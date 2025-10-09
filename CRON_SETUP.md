# Cron Job Setup for Data Migrator Pro

## Overview
Data Migrator Pro uses cron jobs to process large data files in the background. This prevents timeouts and allows for better resource management.

## Required Cron Jobs

### 1. Process Pending Migrations
Processes migration files that are in "processing" status:

```bash
# Run every 5 minutes
*/5 * * * * cd /path/to/redmine && bundle exec rake data_migration:process_pending RAILS_ENV=production >> /var/log/redmine/data_migration.log 2>&1
```

### 2. Cleanup Old Migrations (Optional)
Cleans up migration files and records older than 30 days:

```bash
# Run daily at 2 AM
0 2 * * * cd /path/to/redmine && bundle exec rake data_migration:cleanup_old RAILS_ENV=production >> /var/log/redmine/data_migration_cleanup.log 2>&1
```

## Installation Steps

1. **Open crontab for editing:**
   ```bash
   crontab -e
   ```

2. **Add the cron jobs (adjust paths as needed):**
   ```bash
   # Data Migrator Pro - Process pending migrations every 5 minutes
   */5 * * * * cd /var/www/redmine && bundle exec rake data_migration:process_pending RAILS_ENV=production >> /var/log/redmine/data_migration.log 2>&1
   
   # Data Migrator Pro - Cleanup old migrations daily
   0 2 * * * cd /var/www/redmine && bundle exec rake data_migration:cleanup_old RAILS_ENV=production >> /var/log/redmine/data_migration_cleanup.log 2>&1
   ```

3. **Create log directory (if needed):**
   ```bash
   sudo mkdir -p /var/log/redmine
   sudo chown redmine:redmine /var/log/redmine  # adjust user as needed
   ```

## Manual Processing

### Process a specific migration:
```bash
cd /path/to/redmine
bundle exec rake data_migration:process_single[123] RAILS_ENV=production
```

### Check migration status:
```bash
cd /path/to/redmine
bundle exec rake data_migration:status RAILS_ENV=production
```

## Monitoring

### Check cron logs:
```bash
# Main processing log
tail -f /var/log/redmine/data_migration.log

# Cleanup log  
tail -f /var/log/redmine/data_migration_cleanup.log

# System cron log
tail -f /var/log/cron
```

### Check for errors:
```bash
grep -i error /var/log/redmine/data_migration.log
```

## Troubleshooting

### Common Issues:

1. **Permission errors:**
   - Ensure cron runs as the same user as your Redmine installation
   - Check file permissions on Redmine directory

2. **Environment issues:**
   - Always specify `RAILS_ENV=production` (or your environment)
   - Ensure all environment variables are available to cron

3. **Path issues:**
   - Use absolute paths in cron jobs
   - Test commands manually before adding to cron

4. **Database connection issues:**
   - Verify database credentials in `database.yml`
   - Check if database is accessible from cron environment

### Testing Cron Jobs:

```bash
# Test the command manually first:
cd /var/www/redmine
bundle exec rake data_migration:process_pending RAILS_ENV=production

# Check if it works, then add to cron
```

## Performance Considerations

- **Processing frequency:** Start with 5-minute intervals. Adjust based on your needs.
- **File size limits:** Large files may need longer processing times.
- **Resource usage:** Monitor server resources during migration processing.
- **Concurrent migrations:** The system processes one migration at a time to avoid conflicts.

## Security Notes

- Log files may contain sensitive data. Secure them appropriately.
- Ensure proper file permissions on upload directories.
- Consider log rotation for production systems.

## Log Rotation Setup

Add to `/etc/logrotate.d/redmine-data-migrator`:

```
/var/log/redmine/data_migration*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    create 644 redmine redmine
}
```