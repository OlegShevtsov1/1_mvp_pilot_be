FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "test#{n}@example.com" }
    password { "password" }
    password_confirmation { "password" }
  end

  trait :example do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password" }
  end
end
