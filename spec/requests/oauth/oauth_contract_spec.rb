require 'swagger_helper'
require 'schemas/oauth'
require 'schemas/users'

RSpec.describe 'OAuth API', type: :request do
  include OauthTokenHelper

  # A fixture key stands in for Google's; generated once per run, never committed.
  google_key = OpenSSL::PKey::RSA.generate(2048)

  let(:user) { create(:user) }

  path '/oauth/token' do
    post 'Gets an access token and a refresh token for this device' do
      tags 'OAuth'
      security []
      consumes 'application/json', 'application/x-www-form-urlencoded'
      produces 'application/json'
      parameter name: :token_request, in: :body, schema: Schemas::Oauth::TOKEN_REQUEST
      request_body_example name: 'password', value: {
        grant_type: 'password', client_id: '<client-id>', username: 'user@example.test', password: '<password>'
      }
      request_body_example name: 'google', value: {
        grant_type: 'google_id_token', client_id: '<client-id>', id_token: '<google-id-token>'
      }
      request_body_example name: 'refresh', value: {
        grant_type: 'refresh_token', client_id: '<client-id>', refresh_token: '<refresh-token>'
      }

      response '200', 'token pair for this device; other devices keep their access' do
        schema Schemas::Oauth::TOKEN_PAIR

        context 'with a password grant (AC-08)' do
          let!(:other_device) { create(:oauth_access_token, resource_owner_id: user.id, application: web_client) }
          let(:token_request) do
            { grant_type: 'password', client_id: web_client.uid, username: user.email, password: 'password' }
          end

          run_test_with_example! do
            expect(json_response['access_token']).not_to eq(other_device.plaintext_token)
            expect(OauthAccessToken.find(other_device.id)).to be_accessible
          end
        end

        context 'with a Google ID token for a new email (AC-05)' do
          let(:google_client_id) { 'test-client.apps.googleusercontent.com' }
          let(:token_request) do
            now = Time.now.to_i
            claims = { iss: 'https://accounts.google.com', aud: google_client_id, sub: 'google-1',
                       email: 'new.person@example.com', email_verified: true, iat: now, exp: now + 600 }
            { grant_type: 'google_id_token', client_id: web_client.uid,
              id_token: JWT.encode(claims, google_key, 'RS256', kid: 'k1') }
          end

          around { |example| with_env('GOOGLE_CLIENT_ID' => google_client_id) { example.run } }

          before do
            stub_const('Auth::GoogleIdTokenVerifier::DEFAULT_KEYS', Auth::GoogleIdTokenVerifier::KeySet.new)
            stub_request(:get, 'https://www.googleapis.com/oauth2/v3/certs')
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                         body: { keys: [ JWT::JWK.new(google_key, kid: 'k1', use: 'sig', alg: 'RS256').export ] }.to_json)
          end

          run_test! do
            expect(User.find_by(email: 'new.person@example.com')).to be_present
            expect(json_response['access_token']).to be_present
          end
        end
      end

      response '400', 'grant refused: wrong email or password, unconfirmed Google email, or a revoked or old refresh token' do
        schema Schemas::Oauth::OAUTH_ERROR
        let(:token_request) do
          { grant_type: 'password', client_id: web_client.uid, username: user.email, password: 'wrong' }
        end

        run_test_with_example! do
          expect(json_response['error']).to eq('invalid_grant')
        end
      end

      response '401', 'unknown client' do
        schema Schemas::Oauth::OAUTH_ERROR
        let(:token_request) do
          { grant_type: 'password', client_id: 'unknown-client', username: user.email, password: 'password' }
        end

        run_test_with_example! do
          expect(json_response['error']).to eq('invalid_client')
        end
      end

      response '429', 'too many failed sign-ins from this source' do
        schema Schemas::Users::ERROR_LIST
        header 'Retry-After', schema: { type: :integer }, description: 'Seconds to wait'
        let(:token_request) do
          { grant_type: 'password', client_id: web_client.uid, username: user.email, password: 'wrong' }
        end

        before do
          10.times do
            post '/oauth/token', params: { grant_type: 'password', client_id: web_client.uid,
                                           username: user.email, password: 'wrong' }
          end
        end

        run_test_with_example! do
          expect(response.headers['Retry-After']).to eq('60')
        end
      end
    end
  end

  path '/oauth/revoke' do
    post 'Revokes one token' do
      tags 'OAuth'
      security []
      consumes 'application/json', 'application/x-www-form-urlencoded'
      produces 'application/json'
      parameter name: :revoke_request, in: :body, schema: Schemas::Oauth::REVOKE_REQUEST

      response '200', 'revoked, or the token was unknown (the answer does not tell)' do
        let(:token) { create(:oauth_access_token, resource_owner_id: user.id, application: web_client) }
        let(:revoke_request) { { client_id: web_client.uid, token: token.plaintext_token } }

        run_test! do
          expect(OauthAccessToken.find(token.id)).to be_revoked
        end
      end
    end
  end
end
