require 'rails_helper'

RSpec.describe 'Authentication routes', type: :routing do
  it 'keeps only the sign-up, sign-in, token and sign-out routes the feature uses' do
    expect(auth_routes).to contain_exactly(
      [ 'POST', '/oauth/token', 'oauth/tokens#create' ],
      [ 'POST', '/oauth/revoke', 'oauth/tokens#revoke' ],
      [ 'POST', '/api/v1/users', 'api/v1/users#create' ],
      [ 'POST', '/api/v1/sign_in', 'api/v1/sessions#create' ],
      [ 'POST', '/api/v1/sign_out', 'api/v1/sign_out#create' ],
      [ 'GET', '/api/v1/me', 'api/v1/users#me' ]
    )
  end

  it 'routes no Devise sign-in or sign-up' do
    expect(post: '/users/sign_in').not_to be_routable
    expect(post: '/users').not_to be_routable
  end

  private

  def auth_routes
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s
      controller = route.defaults[:controller].to_s
      next unless path.match?(%r{\A/(users|oauth|api/v1/(users|sign_in|sign_out|me))(/|\(|\z)}) ||
                  controller.start_with?('devise/')

      [ route.verb, path.delete_suffix('(.:format)'), "#{controller}##{route.defaults[:action]}" ]
    end
  end
end
