# frozen_string_literal: true

Rails.application.routes.draw do
  get "learns/index"
  get "connect_services/index"
  root "homes#index"
  get "/login", to: "sessions#new"
  get "/logout", to: "sessions#destroy"
  post "/login", to: "sessions#create"
  post "lock_off", to: "sessions#lock_off"

  resources :video_views, only: %i(create)
  resources :organizations, only: %i(index)
  resources :rewards, only: %i(index) do
    collection do
      get "user_list"
    end
    member do
      get "pdf_output"
    end
  end

  resources :titles, only: %i(index)
  resources :introducers, only: %i(index) do
    collection do
      get "search"
    end
  end
  resources :users, only: %i(show edit update)
  resources :approvals, only: %i(index edit update)
  resources :learns, only: %i(index) do
    collection do
      get "learn_list"
    end
  end
  resources :connect_services, only: %i(index new create) do
    collection do
      get "whitening"
      get "photography"
      get "movie_edit"
      get "web_site_creation"
      get "rent"
      get "moving"
      get "beauty_clinic"
      get "hair_removal_medical"
      get "hair_removal_beauty"
      get "personal_color"
      get "job_change_agent"
      get "mobile_communicating_charge_rethink"
    end
  end
  resources :events, only: %i(index show)
  resources :reservations, only: %i(index create update destroy) do
    collection do
      get "reservation_status"
      get "reserved_list"
    end
    member do
      get "reserve_confirm"
      post "reserved_confirmation"
    end
  end
  resources :tmp_member_infos, only: %i(new create) do
    collection do
      post "confirm"
      get "get_confirm"
      get "complete"
    end
  end

  get "/admin", to: "admin#index"
  namespace :admin do
    resources :seminars
    resources :posts
    resources :incentives, only: %i(index edit update)
    resources :learns
    resources :learn_categories
    resources :cap_adjust_ments, only: %i(index edit update create)
  end

  # エラーページ用のルート
  if Rails.env.production?
    match "/404", to: "errors#not_found", via: :all
    match "/500", to: "errors#internal_server_error", via: :all
    match "*path", to: "application#render_404", via: :all
  end
end
