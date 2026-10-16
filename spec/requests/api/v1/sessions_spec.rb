require 'swagger_helper'
require 'schemas/sessions'

RSpec.describe 'Sessions API', type: :request do
  path '/api/v1/sign_in' do
    post 'Creates a session (logs in)' do
      let!(:user) { create(:user) }
      let(:email) { user.email }
      let(:password) { "password" }

      tags 'Sessions'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :credentials, in: :body, schema: Schemas::Sessions::CREATE_REQUEST_SCHEMA

      response '200', 'session created' do
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
        let(:credentials) { { email: 'wrong@example.com', password: 'wrong_password' } }

        let(:payload) do
          { "status"=>"error", "message"=>"Invalid email or password" }
        end

        run_test_with_example! do
          expect(json_response).to eq(payload)
        end
      end
    end
  end
end
