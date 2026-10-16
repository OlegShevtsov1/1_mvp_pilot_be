RSpec.describe Api::V1::SessionsController, type: :controller do
  render_views

  let(:user) { create(:user) }
  let(:valid_credentials) do
    { email: user.email, password: 'password' }
  end
  let(:invalid_credentials) do
    { email: user.email, password: 'wrong_password' }
  end

  describe '#create' do
    context 'with valid credentials' do
      let(:service) { instance_double(Sessions::Create, success?: true, user: user, errors: []) }

      before do
        allow(Sessions::Create).to receive(:call).and_return(service)
      end

      it 'returns authentication token' do
        post :create, params: valid_credentials

        expect(response).to have_http_status(:success)
        expect(json_response['status']).to eq('success')
        expect(json_response['message']).to eq('Signed in successfully')
        expect(json_response['data']).to have_key('user_id')
        expect(json_response['data']).to have_key('email')
        expect(json_response['data']).to have_key('authentication_token')
        expect(json_response['data']['email']).to eq(user.email)
      end
    end

    context 'with invalid credentials' do
      let(:service) do
        instance_double(
          Sessions::Create,
          success?: false,
          errors: [ 'Invalid email or password' ],
          status_error: :unauthorized
        )
      end

      before do
        allow(Sessions::Create).to receive(:call).and_return(service)
      end

      it 'returns error response' do
        post :create, params: invalid_credentials

        expect(response).to have_http_status(:unauthorized)
        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to eq('Invalid email or password')
      end
    end
  end
end
