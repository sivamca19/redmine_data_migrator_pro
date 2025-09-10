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

  permission :manage_data_migration, { :data_migrator => [:index, :upload, :process, :history, :download_report] }
end
