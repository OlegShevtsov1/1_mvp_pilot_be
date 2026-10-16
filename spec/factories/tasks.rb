FactoryBot.define do
  factory :task do
    name { "Sample Task" }
    description { "This is a sample task description" }
    status { "not_started" }
    association :project

    trait :in_progress do
      status { "in_progress" }
    end

    trait :completed do
      status { "completed" }
    end
  end
end
