require 'rails_helper'

RSpec.describe 'OAuth tokens', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include OauthTokenHelper

  let(:user) { create(:user) }

  def sign_in(password: 'password', client_id: web_client.uid, email: user.email)
    post '/oauth/token', params: { grant_type: 'password', client_id:, username: email, password: }.compact
    response.parsed_body
  end

  it 'gives this device its own token pair while another device keeps its access (AC-08)' do
    other_device = sign_in
    this_device = sign_in

    expect(response).to have_http_status(:ok)
    expect(this_device.keys).to contain_exactly('access_token', 'token_type', 'expires_in', 'refresh_token', 'created_at')
    expect(this_device).to include('token_type' => 'Bearer', 'expires_in' => 3600)
    expect(this_device['created_at']).to be_an(Integer)
    expect(this_device['access_token']).not_to eq(other_device['access_token'])
    expect(OauthAccessToken.by_token(other_device['access_token'])).to be_accessible
    expect(OauthAccessToken.where(resource_owner_id: user.id, revoked_at: nil).count).to eq(2)
  end

  it 'signs in with the email in another letter case' do
    sign_in(email: user.email.upcase)

    expect(response).to have_http_status(:ok)
  end

  it 'refuses a wrong password with invalid_grant and issues no token' do
    body = sign_in(password: 'wrong-password')

    expect(response).to have_http_status(:bad_request)
    expect(body['error']).to eq('invalid_grant')
    expect(OauthAccessToken.count).to eq(0)
  end

  it 'refuses an unknown or missing client_id with invalid_client' do
    [ 'unknown-client', nil ].each do |client_id|
      body = sign_in(client_id:)

      expect(response).to have_http_status(:unauthorized)
      expect(body['error']).to eq('invalid_client')
    end
    expect(OauthAccessToken.count).to eq(0)
  end

  it 'replaces the pair on refresh and revokes the old one at once' do
    old_pair = sign_in
    new_pair = refresh(old_pair['refresh_token'])

    expect(response).to have_http_status(:ok)
    expect(new_pair['access_token']).not_to eq(old_pair['access_token'])
    expect(new_pair['refresh_token']).not_to eq(old_pair['refresh_token'])
    expect(OauthAccessToken.by_token(old_pair['access_token'])).to be_revoked

    reused = refresh(old_pair['refresh_token'])
    expect(response).to have_http_status(:bad_request)
    expect(reused['error']).to eq('invalid_grant')
  end

  it 'refuses a refresh token 30 days old' do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 0).change(usec: 500_000), with_usec: true
    pair = sign_in
    travel 30.days

    body = refresh(pair['refresh_token'])
    expect(response).to have_http_status(:bad_request)
    expect(body['error']).to eq('invalid_grant')
  end

  it 'accepts a refresh token younger than 30 days and restarts the window with the new one' do
    pair = sign_in
    travel 29.days
    pair = refresh(pair['refresh_token'])
    expect(response).to have_http_status(:ok)

    travel 29.days
    refresh(pair['refresh_token'])
    expect(response).to have_http_status(:ok)
  end

  it 'refuses a revoked refresh token' do
    pair = sign_in
    post '/oauth/revoke', params: { client_id: web_client.uid, token: pair['refresh_token'] }

    body = refresh(pair['refresh_token'])
    expect(response).to have_http_status(:bad_request)
    expect(body['error']).to eq('invalid_grant')
  end

  it 'stores SHA-256 hashes of the access and refresh tokens, not the secrets' do
    pair = sign_in
    row = OauthAccessToken.sole

    expect(row.token).to eq(Digest::SHA256.hexdigest(pair['access_token']))
    expect(row.refresh_token).to eq(Digest::SHA256.hexdigest(pair['refresh_token']))
  end

  it 'revokes an access token at /oauth/revoke' do
    pair = sign_in
    post '/oauth/revoke', params: { client_id: web_client.uid, token: pair['access_token'] }

    expect(response).to have_http_status(:ok)
    expect(OauthAccessToken.sole).to be_revoked
  end

  it 'offers only the password and refresh grants, with no authorization or introspection endpoints' do
    post '/oauth/token', params: { grant_type: 'client_credentials', client_id: web_client.uid }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body['error']).to eq('unsupported_grant_type')

    get '/oauth/authorize'
    expect(response).to have_http_status(:not_found)
    post '/oauth/introspect'
    expect(response).to have_http_status(:not_found)
  end
end
