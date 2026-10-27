FactoryBot.define do
  factory :oauth_application, class: 'Doorkeeper::Application' do
    sequence(:name) { |n| "client #{n}" }
    sequence(:uid) { |n| "client-uid-#{n}" }
    confidential { false }
  end

  factory :oauth_access_token, class: 'OauthAccessToken' do
    association :application, factory: :oauth_application
    resource_owner_id { association(:user).id }
    expires_in { 1.hour.to_i }
  end
end
