FactoryBot.define do
  factory :project do
    name { "Sample Project" }
    description { "This is a sample project description that meets the minimum length requirement" }
    association :user

    trait :with_tasks do
      after(:create) do |project|
        create_list(:task, 3, project: project)
      end
    end
  end
end
