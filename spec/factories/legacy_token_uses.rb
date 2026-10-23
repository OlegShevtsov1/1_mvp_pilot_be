FactoryBot.define do
  factory :legacy_token_use do
    user
    used_on { Date.current }
    uses_count { 1 }
  end
end
