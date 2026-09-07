FactoryBot.define do
  factory :location do
    sequence(:name) { |n| "Location #{n}" }
    sequence(:code) { |n| "loc#{n}" }
    timezone { "America/Chicago" }
    opens_at { "09:00" }
    closes_at { "22:00" }
  end

  factory :room do
    location
    sequence(:name) { |n| "Room #{n}" }
    room_type { "single" }
    client_capacity { 1 }
    exclusive { false }
  end

  factory :service_category do
    sequence(:name) { |n| "Category #{n}" }
    sequence(:code) { |n| "cat#{n}" }
  end

  factory :service do
    service_category
    sequence(:name) { |n| "Service #{n}" }
    kind { "standard" }
  end

  factory :service_variant do
    service
    duration_minutes { 60 }
    therapist_count { 1 }
    required_client_capacity { 1 }
    base_price_cents { 8000 }
  end

  factory :staff_profile do
    association :user, factory: :user
    location
    sequence(:employee_code) { |n| "EMP-#{n}" }
    sequence(:display_name) { |n| "Therapist #{n}" }
    hire_date { Date.new(2026, 1, 1) }
  end

  factory :shift do
    staff_profile
    location
    work_date { Date.current }
    starts_at { Time.zone.now.change(hour: 9) }
    ends_at { Time.zone.now.change(hour: 22) }
    status { "published" }
  end

  factory :client do
    sequence(:first_name) { |n| "Client#{n}" }
    last_name { "Test" }
    sequence(:phone) { |n| "+1312555#{n.to_s.rjust(4, '0')}" }
    # Clients reachable on both channels, since FRS §22 requires email and SMS.
    sequence(:email) { |n| "client#{n}@example.com" }
  end
end
