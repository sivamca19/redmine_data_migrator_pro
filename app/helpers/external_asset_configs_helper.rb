# frozen_string_literal: true

# Helper for External Asset Configurations
module ExternalAssetConfigsHelper
  include AdminBreadcrumbsHelper

  def render_breadcrumbs(config = nil, action = nil)
    render_admin_breadcrumbs(
      show_admin: true,
      section_name: 'External Asset Configurations',
      section_path: external_asset_configs_path,
      action: action,
      item_name: config&.name,
      item_path: config ? external_asset_config_path(config) : nil,
      new_label: 'New Configuration',
      edit_label: 'Edit'
    )
  end
end