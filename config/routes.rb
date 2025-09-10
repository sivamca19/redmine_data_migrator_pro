# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

resources :data_migrator do
  collection do
    get :index
    post :upload
    get :history
    delete :clear_history
  end
  member do
    get :show
    get :edit_mapping
    patch :update_mapping
    post :process_migration
    post :restart
    post :rollback
    get :download_report
    delete :destroy
  end
end

resources :external_asset_configs do
  member do
    get :test_connection
  end
  collection do
    get :system_fields
  end
end
