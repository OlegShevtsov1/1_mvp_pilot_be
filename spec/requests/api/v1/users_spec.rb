require 'swagger_helper'
require 'schemas/users'

RSpec.describe 'API V1 Users', type: :request do
  include OauthTokenHelper

  path '/api/v1/users' do
    post 'Creates a user' do
      tags 'Users'
      security []
      consumes 'application/json'
      produces 'application/json'
      parameter name: :user, in: :body, schema: Schemas::Users::CREATE_REQUEST_SCHEMA
      request_body_example value: {
        user: { email: 'user@example.test', password: '<password>', password_confirmation: '<password>' }
      }

      response '201', 'user created and this device signed in (AC-02)' do
        schema Schemas::Users::SIGN_UP_RESULT
        let(:test_email) { "new_user#{Time.now.to_i}@example.com" }
        let(:user) do
          {
            user: {
              email: test_email,
              password: "password",
              password_confirmation: "password"
            }
          }
        end

        around { |example| with_env('OAUTH_CLIENT_ID' => 'web-client-test') { example.run } }

        run_test_with_example! do |response|
          data = JSON.parse(response.body)
          expect(data['status']).to eq('success')
          expect(data['message']).to eq('User created successfully')
          expect(data['data']).to include('user_id', 'email', 'authentication_token',
                                          'access_token', 'refresh_token', 'expires_in')
          expect(User.find_by(email: test_email)).to be_present
        end
      end

      response '422', 'invalid request' do
        schema Schemas::Users::ERROR_LIST
        let(:user) do
          {
            user: {
              email: 'invalid-email',
              password: 'short',
              password_confirmation: 'not-matching'
            }
          }
        end

        let(:payload) do
          { "status"=>"error", "message"=>"User could not be created",
           "errors"=>[ "Email is invalid",
                      "Password confirmation doesn't match Password",
                      "Password is too short (minimum is 6 characters)" ] }
        end

        run_test_with_example! do
          expect(json_response).to eq(payload)
        end
      end

      response '429', 'too many sign-ups from this source' do
        schema Schemas::Users::ERROR_LIST
        header 'Retry-After', schema: { type: :integer }, description: 'Seconds to wait'
        let(:user) do
          { user: { email: 'one-too-many@example.com', password: 'password', password_confirmation: 'password' } }
        end

        around { |example| with_env('SMOKE_TOKEN' => nil) { example.run } }

        before do
          5.times do |i|
            post '/api/v1/users', params: { user: { email: "counted-#{i}@example.com", password: 'password',
                                                    password_confirmation: 'password' } }, as: :json
          end
        end

        run_test_with_example! do
          expect(response.headers['Retry-After']).to eq('3600')
          expect(User.find_by(email: 'one-too-many@example.com')).to be_nil
        end
      end
    end
  end

  path '/api/v1/me' do
    get 'Get the current user profile' do
      tags 'Users'
      produces 'application/json'
      security [ { bearer_auth: [] }, { x_auth_token: [], x_auth_email: [] } ]

      response '200', 'user profile' do
        schema Schemas::Users::PROFILE
        let(:user) { create(:user) }
        let(:Authorization) { "Bearer #{create(:oauth_access_token, resource_owner_id: user.id).plaintext_token}" }

        let(:payload) do
          { "status"=>"success", "message"=>"User profile",
            "data"=>{ "user_id"=>user.id, "email"=>user.email } }
        end

        run_test_with_example! do
          expect(json_response).to eq(payload)
        end
      end

      response '401', 'unauthorized' do
        schema Schemas::Users::ERROR_MESSAGE
        let(:'X-User-Email') { 'wrong@example.com' }
        let(:'X-User-Token') { 'wrong_token' }

        run_test_with_example! do
          expect(json_response).to eq({ "error"=>"Not Authorized" })
        end
      end
    end
  end
end
