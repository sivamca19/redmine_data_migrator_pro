Redmine::Plugin.register :redmine_data_migrator_pro do
  name 'Redmine Data Migrator Pro'
  author 'Sivamanikandan'
  description 'Advanced data migration plugin for importing CSV, XLS, XLSX files from Jira, ClickUp and other PM tools'
  version '1.0.0'
  url 'https://github.com/sivamca19/redmine_data_migrator_pro.git'
  author_url 'https://github.com/sivamca19'

  requires_redmine :version_or_higher => '4.0.0'

  menu :admin_menu, :data_migrator, { :controller => 'data_migrator', :action => 'index' },
       :caption => 'Data Migrator',
       :html => { :class => 'icon icon-package' }

  menu :admin_menu, :external_asset_configs, { :controller => 'external_asset_configs', :action => 'index' },
       :caption => 'External Asset Configs',
       :html => { :class => 'icon icon-settings' }

  permission :manage_data_migration, { :data_migrator => [:index, :upload, :process, :history, :download_report] }
  permission :manage_external_asset_configs, { :external_asset_configs => [:index, :show, :new, :create, :edit, :update, :destroy, :test_connection] }
end
