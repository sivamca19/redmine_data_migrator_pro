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
  end

  def update
    # Filter out empty credential fields to preserve existing values
    filtered_params = config_params
    if @config.persisted?
      ['email', 'api_token', 'api_key', 'team_id'].each do |field|
        filtered_params.delete(field) if filtered_params[field].blank?
      end
    end

    if @config.update(filtered_params)
      flash[:notice] = "Configuration '#{@config.name}' was successfully updated."
      redirect_to external_asset_configs_path
    else
      @projects = Project.active.has_module(:issue_tracking)
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