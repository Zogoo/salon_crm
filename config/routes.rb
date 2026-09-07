Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "auth/sign_in", to: "auth#sign_in"
      post "auth/sign_up", to: "auth#sign_up"
      get  "auth/me",      to: "auth#me"

      resource :profile, only: %i[show update] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :notes

      # --- Massagelab domain ---
      resources :locations, only: %i[index show]
      resources :services, only: :index
      resources :staff, only: %i[index show]
      resources :shifts, only: %i[index create destroy]
      resources :clients, only: %i[index show create update] do
        put :preferences, on: :member, action: :update_preferences
      end
      get "availability", to: "availability#index"
      get "availability/next_for_therapist", to: "availability#next_for_therapist"
      resources :appointments, only: %i[index show create] do
        collection { get :calendar }
        member { post :transition }
      end
      resources :approval_requests, only: :index do
        member do
          post :approve
          post :reject
        end
      end
      get "dashboard", to: "dashboard#show"
    end
  end

  # SPA catch-all: everything except the API, health check and asset-like paths
  # is served by the built Angular app.
  get "*path", to: "spa#index", constraints: ->(req) {
    !req.path.start_with?("/api/", "/up") && !req.path.match?(/\.\w+$/)
  }
end
