require 'rails_helper'

RSpec.describe 'POST /api/v1/sign_out', type: :request do
  let!(:web_client) { Doorkeeper::Application.create!(name: 'todolist web', uid: 'web-client-test', confidential: false) }
  let(:user) { create(:user) }

  around { |ex| with_env('LEGACY_AUTH_ENABLED' => nil) { ex.run } }

  def sign_in_device
    post '/oauth/token', params: { grant_type: 'password', client_id: web_client.uid, username: user.email, password: 'password' }
    response.parsed_body
  end

  def refresh(refresh_token)
    post '/oauth/token', params: { grant_type: 'refresh_token', client_id: web_client.uid, refresh_token: }
    response.parsed_body
  end

  def bearer(token) = { 'Authorization' => "Bearer #{token}" }

  def legacy(token = user.authentication_token) = { 'X-User-Email' => user.email, 'X-User-Token' => token }

  def expect_not_authorized
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'Not Authorized')
  end

  it "ends this device's access and refresh token while another device keeps working (AC-11)" do
    device_a = sign_in_device
    device_b = sign_in_device

    post '/api/v1/sign_out', headers: bearer(device_a['access_token'])
    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty

    get '/api/v1/me', headers: bearer(device_a['access_token'])
    expect_not_authorized
    expect(refresh(device_a['refresh_token'])['error']).to eq('invalid_grant')
    expect(response).to have_http_status(:bad_request)

    get '/api/v1/me', headers: bearer(device_b['access_token'])
    expect(response).to have_http_status(:ok)
    refresh(device_b['refresh_token'])
    expect(response).to have_http_status(:ok)
  end

  it 'leaves the legacy token working after a bearer sign-out (AC-11)' do
    legacy_token = user.authentication_token

    post '/api/v1/sign_out', headers: bearer(sign_in_device['access_token'])
    expect(response).to have_http_status(:no_content)

    get '/api/v1/me', headers: legacy(legacy_token)
    expect(response).to have_http_status(:ok)
    expect(user.reload.authentication_token).to eq(legacy_token)
  end

  it 'rotates the legacy token so it stops working for every device that uses it (AC-11b)' do
    old_token = user.authentication_token

    post '/api/v1/sign_out', headers: legacy(old_token)
    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty

    get '/api/v1/me', headers: legacy(old_token)
    expect_not_authorized
    expect(user.reload.authentication_token).to be_present
    expect(user.authentication_token).not_to eq(old_token)

    post '/api/v1/sign_in', params: { email: user.email, password: 'password' }
    new_token = response.parsed_body.dig('data', 'authentication_token')
    expect(new_token).to eq(user.reload.authentication_token)
    get '/api/v1/me', headers: legacy(new_token)
    expect(response).to have_http_status(:ok)
  end

  it 'keeps bearer devices working after a legacy sign-out (AC-11b)' do
    device = sign_in_device

    post '/api/v1/sign_out', headers: legacy
    expect(response).to have_http_status(:no_content)

    get '/api/v1/me', headers: bearer(device['access_token'])
    expect(response).to have_http_status(:ok)
  end

  it 'refuses an unauthenticated sign-out with the existing Not Authorized answer' do
    legacy_token = user.authentication_token

    post '/api/v1/sign_out'
    expect_not_authorized

    post '/api/v1/sign_out', headers: legacy('wrong')
    expect_not_authorized
    expect(user.reload.authentication_token).to eq(legacy_token)

    revoked = create(:oauth_access_token, resource_owner_id: user.id)
    revoked.revoke
    post '/api/v1/sign_out', headers: bearer(revoked.plaintext_token)
    expect_not_authorized
  end
end
