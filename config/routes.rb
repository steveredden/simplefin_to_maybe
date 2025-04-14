Rails.application.routes.draw do

  resources :linkages, only: [:index, :create, :update, :destroy] do
    member do
      post :sync
      get :sync_status
    end
    collection do
      post :run_all_syncs
    end
  end
  
  resources :accounts, only: [:index, :destroy]

  resources :settings, only: [:index, :update]
  get 'test_simplefin', to: 'settings#test_simplefin'
  get 'test_maybe', to: 'settings#test_maybe'
  patch '/settings/:key', to: 'settings#update', as: 'update_setting'
  post 'add_institution_icons', to: 'settings#add_institution_icons'
  post 'remove_institution_icons', to: 'settings#remove_institution_icons'

  post '/reset_database', to: 'database#reset'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount GoodJob::Engine => '/good_job'

  # Defines the root path route ("/")
  root "linkages#index"
end
