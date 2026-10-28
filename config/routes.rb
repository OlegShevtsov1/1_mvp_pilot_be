Rails.application.routes.draw do
  get '/health', to: 'health#show'
  post '/api/errors', to: 'errors#create'
  post '/admin/glitchtip_smoke/:kind', to: 'admin/glitchtip_smoke#create'

  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  devise_for :users, skip: :all
  use_doorkeeper do
    skip_controllers :authorizations, :applications, :authorized_applications, :token_info
    controllers tokens: 'oauth/tokens'
  end

  namespace :api do
    namespace :v1 do
      resources :users, only: [ :create ]
      post 'sign_in', to: 'sessions#create'
      post 'sign_out', to: 'sign_out#create'
      get 'me', to: 'users#me'
      resources :projects do
        resources :tasks
      end
    end
  end
end
