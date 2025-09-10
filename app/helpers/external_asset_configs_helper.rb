module ExternalAssetConfigsHelper
  def external_asset_config_breadcrumbs(config = nil, action = nil)
    breadcrumbs = []
    breadcrumbs << link_to(l(:label_administration), administration_path)
    breadcrumbs << link_to('External Asset Configurations', external_asset_configs_path)
    
    case action || action_name
    when 'show'
      breadcrumbs << config.name if config
    when 'new'
      breadcrumbs << 'New Configuration'
    when 'edit'
      if config
        breadcrumbs << link_to(config.name, external_asset_config_path(config))
        breadcrumbs << 'Edit'
      end
    end
    
    breadcrumbs
  end
  
  def render_breadcrumbs(config = nil, action = nil)
    breadcrumbs = external_asset_config_breadcrumbs(config, action)
    content_tag :div, class: 'contextual-breadcrumbs' do
      breadcrumbs.map.with_index do |crumb, index|
        if index == breadcrumbs.length - 1
          content_tag :span, crumb, class: 'current'
        else
          crumb + content_tag(:span, ' » ', class: 'separator')
        end
      end.join.html_safe
    end
  end
end