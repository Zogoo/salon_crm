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


      # --- Massagelab domain ---
      resources :locations, only: %i[index show update] do
        collection { get :directory }
        member do
          get    :business_hours
          put    :business_hours, action: :set_business_hours
          get    :closures
          post   :closures, action: :create_closure
          delete "closures/:closure_id", action: :destroy_closure
          get    :rooms, to: "rooms#index"
        end
      end
      resources :rooms, only: %i[create update] do
        member do
          get    "blocks", action: :blocks
          post   "blocks", action: :create_block
          delete "blocks/:block_id", action: :destroy_block
        end
      end
      resources :service_categories, only: :index
      resources :services, only: %i[index show create update destroy] do
        member do
          get  :variants
          post :activate
          post :deactivate
        end
        resources :service_variants, only: :create, shallow: false
      end
      resources :service_variants, only: :update do
        member do
          get  "prices", action: :prices
          post "prices", action: :set_price
        end
      end
      resources :staff, only: %i[index show create update] do
        member { post :offboard }
        # Each hangs off a staff profile but is its own resource: rates are
        # effective-dated and qualifications are a set, neither of which
        # belongs in a PATCH of the profile.
        scope module: :staff do
          resource  :qualifications, only: %i[show update]
          resources :session_rates,  only: %i[index create]
          resource  :monthly_rate,   only: %i[show create], controller: :monthly_rates
        end
      end
      get "manager_payouts", to: "manager_payouts#index"
      resources :shifts, only: %i[index create update destroy] do
        collection do
          get  :day
          post :publish
        end
        member do
          get    "breaks", action: :breaks
          post   "breaks", action: :create_break
          delete "breaks/:break_id", action: :destroy_break
        end
      end
      resources :clients, only: %i[index show create update] do
        member do
          get  :preferences
          put  :preferences, action: :update_preferences
          get  "preferences/versions", action: :preference_versions
          post :merge
        end
        # The company-wide client record (BR-42), read-only views of it.
        scope module: :clients do
          get "appointments",     to: "history#appointments"
          get "orders",           to: "history#orders"
          get "gift_cards",       to: "history#gift_cards"
          get "ratings",          to: "history#ratings"
          get "history_summary",  to: "history#summary"
        end
      end
      get "availability", to: "availability#index"
      get "availability/next_for_therapist", to: "availability#next_for_therapist"
      resources :appointments, only: %i[index show create update] do
        collection { get :calendar }
        member do
          post   :transition
          post   :reschedule
          post   :assign_staff
          post   :repeat
          post   :replace_service
          post   :cancel
          post   :complete_for_checkout
          post   :deposit
          post   "deposit/refund", action: :refund_deposit
          post   "items", action: :add_items
          delete "items/:item_id", action: :remove_item
          get    "care_notes", to: "care_notes#index"
        end
      end
      post "care_notes/:id/supersede", to: "care_notes#supersede"
      # Doc 05 §3 names these /session and /me; the /auth/* paths above are
      # kept because the console already uses them.
      post   "session",         to: "auth#sign_in"
      delete "session",         to: "auth#sign_out"
      get    "me",              to: "auth#me"
      post   "me/otp",          to: "auth#enrol_otp"
      post   "me/otp/confirm",  to: "auth#confirm_otp"
      post   "password_resets", to: "auth#request_password_reset"
      put    "password_resets/:token", to: "auth#reset_password"
      get    "earning_statements/:id/pdf", to: "earnings#statement_pdf"
      post   "kiosk/ratings",   to: "ratings#create"

      resources :staff_requests, only: %i[index create] do
        member do
          post :approve
          post :reject
          post :withdraw
        end
      end
      resources :approval_requests, only: :index do
        member do
          post :approve
          post :reject
        end
      end
      get "dashboard", to: "dashboard#show"
      resources :audit_logs, only: :index

      # --- Money and operations ---
      resources :orders, only: %i[create show] do
        member do
          get  :receipt
          post :discounts
          post :line_items
          post :refunds
          post :payments
          post :gift_card_redemptions
          post :membership_credit
          post :tips
          post :settle
          post "payments/:payment_id/void", action: :void_payment, as: :void_payment
        end
      end
      get "gift_cards/scan/:barcode", to: "gift_cards#scan"
      resources :gift_cards, only: %i[index show create] do
        member do
          post :adjust
          post :void
          post :redeem
        end
      end
      resources :memberships, only: %i[index show create update] do
        member do
          get  :credits
          post :record_payment
          post :request_cancellation
          post :adjust_credits
          post :authorize_cross_location
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
      patch "earning_lines/:id",         to: "earnings#update_line"
      get "reports/staff_earnings",      to: "earnings#report"

      # --- Reports ---
      get "reports/daily_revenue",       to: "reports#daily_revenue"
      get "reports/client_log",          to: "reports#client_log"
      get "reports/gift_card_liability", to: "reports#gift_card_liability"
      get "reports/ratings",             to: "reports#ratings"
      get "reports/ratings/alerts",      to: "reports#rating_alerts"
      get "reports/membership",          to: "reports#membership"
      get "reports/outstanding_fees",    to: "reports#outstanding_fees"
      get "reports/no_shows",            to: "reports#no_shows"
      get "reports/utilization",         to: "reports#utilization"
      get "reports/client_retention",    to: "reports#client_retention"

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
