FactoryBot.define do
  factory :note do
    sequence(:title) { |n| "Note #{n}" }
    body { "Some note body." }
    association :user
  end
end
