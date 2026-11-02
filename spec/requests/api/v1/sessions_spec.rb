require 'swagger_helper'
require 'schemas/sessions'
require 'schemas/users'

RSpec.describe 'Sessions API', type: :request do
  path '/api/v1/sign_in' do
    post 'Creates a session (logs in)' do
      let!(:user) { create(:user) }
      let(:email) { user.email }
      let(:password) { "password" }

      tags 'Sessions'
      description 'Legacy sign-in, kept until the cutoff; new clients sign in through /oauth/token.'
      deprecated true
      security []
      consumes 'application/json'
      produces 'application/json'
      parameter name: :credentials, in: :body, schema: Schemas::Sessions::CREATE_REQUEST_SCHEMA

      response '200', 'session created' do
        schema Schemas::Sessions::LEGACY_SIGN_IN_RESULT
        let(:credentials) { { email:, password: } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['status']).to eq('success')
          expect(data['message']).to eq('Signed in successfully')
          expect(data['data']).to include('user_id', 'email', 'authentication_token')
          expect(data['data']['email']).to eq(user.email)
        end
      end

      response '401', 'invalid credentials' do
        schema Schemas::Sessions::STATUS_MESSAGE
        let(:credentials) { { email: 'wrong@example.com', password: 'wrong_password' } }

        let(:payload) do
          { "status"=>"error", "message"=>"Invalid email or password" }
        end

        run_test_with_example! do
          expect(json_response).to eq(payload)
        end
      end

      response '429', 'too many failed sign-ins from this source' do
        schema Schemas::Users::ERROR_LIST
        header 'Retry-After', schema: { type: :integer }, description: 'Seconds to wait'
        let(:credentials) { { email:, password: } }

        before do
          10.times { post '/api/v1/sign_in', params: { email:, password: 'wrong' }, as: :json }
        end

        run_test_with_example! do
          expect(response.headers['Retry-After']).to eq('60')
        end
      end
    end
  end

  path '/api/v1/sign_out' do
    post 'Signs out on this device' do
      tags 'Sessions'
      produces 'application/json'
      security [ { bearer_auth: [] }, { x_auth_token: [], x_auth_email: [] } ]

      response '204', 'signed out; other devices keep working (AC-11)' do
        include OauthTokenHelper

        let(:user) { create(:user) }
        let(:device_a) { sign_in_device }
        let!(:device_b) { sign_in_device }
        let(:Authorization) { "Bearer #{device_a['access_token']}" }

        def sign_in_device
          post '/oauth/token', params: { grant_type: 'password', client_id: web_client.uid,
                                         username: user.email, password: 'password' }
          response.parsed_body
        end

        run_test! do
          get '/api/v1/me', headers: { 'Authorization' => "Bearer #{device_a['access_token']}" }
          expect(response).to have_http_status(:unauthorized)
          get '/api/v1/me', headers: { 'Authorization' => "Bearer #{device_b['access_token']}" }
          expect(response).to have_http_status(:ok)
        end
      end

      response '401', 'unauthorized' do
        schema Schemas::Users::ERROR_MESSAGE

        run_test_with_example! do
          expect(json_response).to eq({ "error"=>"Not Authorized" })
        end
      end
    end
  end
end
