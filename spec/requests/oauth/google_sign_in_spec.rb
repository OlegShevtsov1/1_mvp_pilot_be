require 'rails_helper'

RSpec.describe 'Google sign-in at the token endpoint', type: :request do
  include OauthTokenHelper

  # A fixture key stands in for Google's; generated once per run, never committed.
  google_key = OpenSSL::PKey::RSA.generate(2048)

  let(:rsa_key) { google_key }
  let(:google_client_id) { 'test-client.apps.googleusercontent.com' }

  around { |example| with_env('GOOGLE_CLIENT_ID' => google_client_id) { example.run } }

  before do
    stub_const('Auth::GoogleIdTokenVerifier::DEFAULT_KEYS', Auth::GoogleIdTokenVerifier::KeySet.new)
    stub_request(:get, 'https://www.googleapis.com/oauth2/v3/certs')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { keys: [ JWT::JWK.new(rsa_key, kid: 'k1', use: 'sig', alg: 'RS256').export ] }.to_json)
  end

  def id_token(key: rsa_key, **claims)
    now = Time.now.to_i
    payload = { iss: 'https://accounts.google.com', aud: google_client_id, sub: 'google-1',
                email: 'person@example.com', email_verified: true, iat: now, exp: now + 600 }
    JWT.encode(payload.merge(claims), key, 'RS256', kid: 'k1')
  end

  def google_sign_in(token, client_id: web_client.uid)
    post '/oauth/token', params: { grant_type: 'google_id_token', client_id:, id_token: token }.compact
    response.parsed_body
  end

  def password_sign_in(email, password: 'password')
    post '/oauth/token', params: { grant_type: 'password', client_id: web_client.uid, username: email, password: }
    response.parsed_body
  end

  it 'creates a user with a Google identity for an unknown verified email and signs the device in (AC-05)' do
    body = nil
    expect { body = google_sign_in(id_token(email: 'New.Person@Example.com')) }.to change(User, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(body.keys).to contain_exactly('access_token', 'token_type', 'expires_in', 'refresh_token', 'created_at')
    expect(body['expires_in']).to eq(3600)
    user = User.find_by!(email: 'new.person@example.com')
    expect(user.identities.sole).to have_attributes(provider: 'google', uid: 'google-1')
    token = OauthAccessToken.by_token(body['access_token'])
    expect(token).to be_accessible
    expect(token.resource_owner_id).to eq(user.id)
  end

  context 'with a password user of the same email' do
    let!(:user) { create(:user, email: 'person@example.com') }
    let!(:project) { create(:project, user:) }

    it 'links Google to that user and cancels the password and all earlier access (AC-06)' do
      devices = Array.new(2) { password_sign_in(user.email) }
      legacy_token = user.authentication_token

      body = nil
      expect { body = google_sign_in(id_token(email: 'Person@Example.COM')) }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(user.identities.sole).to have_attributes(provider: 'google', uid: 'google-1')
      devices.each do |pair|
        expect(OauthAccessToken.by_token(pair['access_token'])).to be_revoked
        expect(refresh(pair['refresh_token'])['error']).to eq('invalid_grant')
        expect(response).to have_http_status(:bad_request)
      end

      expect(password_sign_in(user.email)['error']).to eq('invalid_grant')
      expect(response).to have_http_status(:bad_request)
      post '/api/v1/sign_in', params: { email: user.email, password: 'password' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      get '/api/v1/projects', headers: { 'X-User-Email' => user.email, 'X-User-Token' => legacy_token }
      expect(response).to have_http_status(:unauthorized)

      token = OauthAccessToken.by_token(body['access_token'])
      expect(token).to be_accessible
      expect(token.resource_owner_id).to eq(user.id)
      expect(User.find(token.resource_owner_id).projects).to contain_exactly(project)
    end

    it 'keeps one user and one identity whatever the capital letters of the email (AC-06)' do
      expect do
        [ 'PERSON@EXAMPLE.COM', 'person@example.com' ].each do |email|
          google_sign_in(id_token(email:))
          expect(response).to have_http_status(:ok)
        end
      end.not_to change(User, :count)

      expect(User.where('lower(email) = ?', 'person@example.com')).to contain_exactly(user)
      expect(Identity.count).to eq(1)
      expect(Identity.sole.user).to eq(user)
    end

    it 'leaves the password, tokens and legacy token working when Google sign-in is refused (AC-07)' do
      earlier = password_sign_in(user.email)
      legacy_token = user.authentication_token

      expect(google_sign_in(id_token(email_verified: false))['error']).to eq('invalid_grant')

      expect(OauthAccessToken.by_token(earlier['access_token'])).to be_accessible
      password_sign_in(user.email)
      expect(response).to have_http_status(:ok)
      expect(user.reload.authentication_token).to eq(legacy_token)
      expect(Identity.count).to eq(0)
    end

    it 'refuses an unknown client before the Google token is looked at' do
      body = google_sign_in(id_token, client_id: 'unknown-client')

      expect(response).to have_http_status(:unauthorized)
      expect(body['error']).to eq('invalid_client')
      expect(Identity.count).to eq(0)
      password_sign_in(user.email)
      expect(response).to have_http_status(:ok)
    end
  end

  it 'signs an already linked user in again without ending their other devices' do
    first = google_sign_in(id_token)
    google_sign_in(id_token)

    expect(response).to have_http_status(:ok)
    expect(OauthAccessToken.by_token(first['access_token'])).to be_accessible
    owner_id = OauthAccessToken.by_token(first['access_token']).resource_owner_id
    expect(OauthAccessToken.where(resource_owner_id: owner_id, revoked_at: nil).count).to eq(2)
  end

  describe 'a Google sign-in that did not complete (AC-07)' do
    stranger_key = OpenSSL::PKey::RSA.generate(2048)

    {
      'an email Google has not verified' => -> { id_token(email_verified: false) },
      'a token signed with a key Google did not publish' => -> { id_token(key: stranger_key) },
      'an expired token' => -> { id_token(exp: Time.now.to_i - 60) },
      'a missing token, as when the Google step is cancelled' => -> { nil },
      'something that is not a token' => -> { 'garbage' }
    }.each do |case_name, token|
      it "refuses #{case_name} with invalid_grant and creates or links nothing" do
        token = instance_exec(&token)

        expect { google_sign_in(token) }.not_to change { [ User.count, OauthAccessToken.count ] }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('invalid_grant')
        expect(Identity.count).to eq(0)
      end
    end
  end
end
