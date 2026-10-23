FactoryBot.define do
  factory :identity do
    user
    provider { 'google' }
    sequence(:uid) { |n| "google-uid-#{n}" }
  end
end
