Redmine::Plugin.register :redmine_data_migrator_pro do
  name 'Redmine Data Migrator Pro'
  author 'Sivamanikandan'
  description 'Advanced data migration plugin for importing CSV, XLS, XLSX files from Jira, ClickUp and other PM tools'
  version '1.0.0'
  url 'https://github.com/sivamca19/redmine_data_migrator_pro.git'
  author_url 'https://github.com/sivamca19'

  requires_redmine :version_or_higher => '4.0.0'

  settings default: {
    'job_processor' => 'cron',
    'chunk_size' => 100,
    'max_file_size_mb' => 50,
    'cleanup_days' => 30
  }, partial: 'settings/redmine_data_migrator_pro_settings'

  menu :admin_menu, :data_migrator, { :controller => 'data_migrator', :action => 'index' },
       :caption => %Q{
    <svg xmlns="http://www.w3.org/2000/svg" class='s18 icon-svg' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
      <polyline points="14,2 14,8 20,8"></polyline>
      <line x1="16" y1="13" x2="8" y2="13"></line>
      <line x1="16" y1="17" x2="8" y2="17"></line>
      <polyline points="10,9 9,9 8,9"></polyline>
    </svg>
    Data Migrator
  }.html_safe,
       :html => { :class => 'icon icon-package' }

  menu :admin_menu, :external_asset_configs, { :controller => 'external_asset_configs', :action => 'index' },
       :caption => %Q{
    <svg xmlns="http://www.w3.org/2000/svg" class='s18 icon-svg' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;">
      <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
      <line x1="9" y1="9" x2="15" y2="9"></line>
      <line x1="9" y1="12" x2="15" y2="12"></line>
      <line x1="9" y1="15" x2="15" y2="15"></line>
      <circle cx="6" cy="9" r="1"></circle>
      <circle cx="6" cy="12" r="1"></circle>
      <circle cx="6" cy="15" r="1"></circle>
      <path d="M21 9l-4 4-4-4"></path>
    </svg>
    External Asset Configs
  }.html_safe,
       :html => { :class => 'icon icon-settings' }

  permission :manage_data_migration, { :data_migrator => [:index, :upload, :process, :history, :download_report] }
  permission :manage_external_asset_configs, { :external_asset_configs => [:index, :show, :new, :create, :edit, :update, :destroy, :test_connection] }
end
