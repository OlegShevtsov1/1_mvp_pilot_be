require 'rails_helper'

# Devise's default sign-in and sign-up routes checked passwords without the failed sign-in limit (AC-10, ADR-0009)
# and created users without the sign-up limit (AC-04b); the app mounts none of them (PILOT-362).
RSpec.describe 'Devise default routes', type: :request do
  let!(:user) { create(:user) }

  it 'answers 404 to a sign-in at /users/sign_in, even with the right password' do
    post '/users/sign_in', params: { user: { email: user.email, password: 'password' } }, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'answers 404 to a sign-up at /users and creates no user' do
    expect do
      post '/users', params: { user: { email: 'door@example.com', password: 'password123',
                                       password_confirmation: 'password123' } }, as: :json
    end.not_to change(User, :count)

    expect(response).to have_http_status(:not_found)
  end
end
