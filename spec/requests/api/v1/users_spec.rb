require 'swagger_helper'
require 'schemas/users'

RSpec.describe 'API V1 Users', type: :request do
  path '/api/v1/users' do
    post 'Creates a user' do
      tags 'Users'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :user, in: :body, schema: Schemas::Users::CREATE_REQUEST_SCHEMA

      response '201', 'user created' do
        schema schema_data_obj(Schemas::Users::CREATE_RESPONSE_SCHEMA)
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

        run_test_with_example! do |response|
          data = JSON.parse(response.body)
          expect(data['status']).to eq('success')
          expect(data['message']).to eq('User created successfully')
          expect(data['data']).to include('user_id', 'email', 'authentication_token')
        end
      end

      response '422', 'invalid request' do
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
    end
  end

  path '/api/v1/me' do
    get 'Get the current user profile' do
      tags 'Users'
      produces 'application/json'
      auth_security
      auth_parameters

      response '200', 'user profile' do
        let(:user) { create(:user) }
        authenticate_with_user

        let(:payload) do
          { "status"=>"success", "message"=>"User profile",
            "data"=>{ "user_id"=>user.id, "email"=>user.email } }
        end

        run_test_with_example! do
          expect(json_response).to eq(payload)
        end
      end

      response '401', 'unauthorized' do
        let(:'X-User-Email') { 'wrong@example.com' }
        let(:'X-User-Token') { 'wrong_token' }

        run_test_with_example! do
          expect(json_response).to eq({ "error"=>"Not Authorized" })
        end
      end
    end
  end
end
