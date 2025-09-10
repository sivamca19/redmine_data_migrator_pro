# Admin controller for managing External Asset Configurations
# Allows admins to configure JIRA, ClickUp, and other PM tool access credentials
class ExternalAssetConfigsController < ApplicationController
  before_action :require_admin
  before_action :find_config, only: [:show, :edit, :update, :destroy, :test_connection]

  def index
    @configs = ExternalAssetConfig.includes(:project)
                                  .order(:name)
  end

  def show
    # Configuration details view
  end

  def new
    @config = ExternalAssetConfig.new
    @projects = Project.active.has_module(:issue_tracking)
  end

  def create
    @config = ExternalAssetConfig.new(config_params)

    if @config.save
      flash[:notice] = "External asset configuration '#{@config.name}' was successfully created."
      redirect_to external_asset_configs_path
    else
      @projects = Project.active.has_module(:issue_tracking)
      render :new
    end
  end

  def edit
    @projects = Project.active.has_module(:issue_tracking)
    # Load existing credentials into virtual attributes for form display
    @config.load_credentials_to_attributes
  end

  def update
    if @config.update(config_params)
      flash[:notice] = "Configuration '#{@config.name}' was successfully updated."
      redirect_to external_asset_configs_path
    else
      @projects = Project.active.has_module(:issue_tracking)
      # Load credentials for form redisplay
      @config.load_credentials_to_attributes
      render :edit
    end
  end

  def destroy
    name = @config.name

    if @config.data_migrations.any?
      flash[:error] = "Cannot delete configuration '#{name}' because it is used by #{@config.data_migrations.count} migration(s)."
    else
      @config.destroy
      flash[:notice] = "Configuration '#{name}' was successfully deleted."
    end

    redirect_to external_asset_configs_path
  end

  def test_connection
    result = @config.test_connection

    respond_to do |format|
      format.json do
        render json: {
          success: result[:success],
          message: result[:message]
        }
      end
    end
  end

  def system_fields
    @config = params[:config_id].present? ? ExternalAssetConfig.find(params[:config_id]) : ExternalAssetConfig.new
    @config.system_type = params[:system_type]
    @config.load_credentials_to_attributes if @config.persisted?

    respond_to do |format|
      format.html do
        render partial: 'system_fields_content', locals: { system_type: params[:system_type], config: @config }
      end
    end
  end

  private

  def find_config
    @config = ExternalAssetConfig.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Configuration not found."
    redirect_to external_asset_configs_path
  end

  def config_params
    params.require(:external_asset_config).permit(
      :name, :system_type, :project_id, :base_url, :status, :description,
      :email, :api_token, :api_key, :team_id, :additional_config
    )
  end
end