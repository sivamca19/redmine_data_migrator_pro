# frozen_string_literal: true

# Helper for Data Migrator
module DataMigratorHelper
  include AdminBreadcrumbsHelper

  def render_breadcrumbs(migration = nil, action = nil)
    render_admin_breadcrumbs(
      show_admin: true,
      section_name: 'Data Migrator',
      section_path: data_migrator_index_path,
      action: action,
      item_name: migration ? "Migration ##{migration.id}" : nil,
      item_path: migration ? data_migrator_path(migration) : nil,
      edit_label: 'Field Mapping',
      history_label: 'Migration History'
    )
  end
end