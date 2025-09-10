# frozen_string_literal: true

# Generic breadcrumb helper for admin interfaces
module AdminBreadcrumbsHelper
  def render_admin_breadcrumbs(config = {})
    breadcrumbs = build_breadcrumbs(config)
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

  private

  def build_breadcrumbs(config)
    breadcrumbs = []
    breadcrumbs << link_to(l(:label_administration), administration_path) if config[:show_admin]
    breadcrumbs << link_to(config[:section_name], config[:section_path]) if config[:section_name]
    
    case config[:action] || action_name
    when 'show'
      breadcrumbs << config[:item_name] if config[:item_name]
    when 'new'
      breadcrumbs << (config[:new_label] || 'New')
    when 'edit', 'edit_mapping'
      if config[:item_name] && config[:item_path]
        breadcrumbs << link_to(config[:item_name], config[:item_path])
        breadcrumbs << (config[:edit_label] || 'Edit')
      end
    when 'history'
      breadcrumbs << (config[:history_label] || 'History')
    end
    
    breadcrumbs
  end
end