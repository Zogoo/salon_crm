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

      # --- Money and operations ---
      resources :orders, only: %i[create show] do
        member do
          post :payments
          post :gift_card_redemptions
          post :membership_credit
          post :tips
          post :settle
        end
      end
      resources :gift_cards, only: %i[index show create] do
        member do
          post :adjust
          post :void
        end
      end
      resources :memberships, only: %i[index show create update] do
        member do
          post :record_payment
          post :request_cancellation
          post :adjust_credits
        end
      end

      # --- Earnings ---
      get  "earning_periods",            to: "earnings#periods"
      post "earning_periods/:id/build",  to: "earnings#build"
      post "earning_periods/:id/lock",   to: "earnings#lock"
      get  "earning_periods/:id/statements", to: "earnings#statements"
      get  "earning_statements/:id",     to: "earnings#statement"
      post "earning_statements/:id/adjustments", to: "earnings#create_adjustment"
      get  "earning_lines",              to: "earnings#lines"
      post "earning_lines",              to: "earnings#create_line"
      get  "reports/staff_earnings",     to: "earnings#report"

      # --- Reports ---
      get "reports/daily_revenue",       to: "reports#daily_revenue"
      get "reports/client_log",          to: "reports#client_log"
      get "reports/gift_card_liability", to: "reports#gift_card_liability"
      get "reports/ratings",             to: "reports#ratings"
      get "reports/outstanding_fees",    to: "reports#outstanding_fees"

      # --- Client care and feedback ---
      resources :care_notes, only: %i[index create]
      post "ratings",             to: "ratings#create"
      get  "ratings/kiosk_queue", to: "ratings#kiosk_queue"
      get  "public/ratings/:token",  to: "ratings#show_by_token"
      post "public/ratings/:token",  to: "ratings#create_by_token"
    end
  end

  # SPA catch-all: everything except the API, health check and asset-like paths
  # is served by the built Angular app.
  get "*path", to: "spa#index", constraints: ->(req) {
    !req.path.start_with?("/api/", "/up") && !req.path.match?(/\.\w+$/)
  }
end
