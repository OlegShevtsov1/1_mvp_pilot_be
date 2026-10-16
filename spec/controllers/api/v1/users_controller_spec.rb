RSpec.describe Api::V1::UsersController, type: :controller do
  render_views

  let(:user) { create(:user) }
  let(:valid_user_params) do
    { user: { email: 'new@example.com', password: 'password123', password_confirmation: 'password123' } }
  end
  let(:invalid_user_params) do
    { user: { email: 'invalid', password: 'short', password_confirmation: 'mismatch' } }
  end

  describe '#create' do
    context 'with valid parameters' do
      let(:service) { instance_double(Users::Create, success?: true, user: user, errors: []) }

      before do
        allow(Users::Create).to receive(:call).and_return(service)
      end

      it 'creates a new user' do
        post :create, params: valid_user_params

        expect(response).to have_http_status(:created)
        expect(json_response['status']).to eq('success')
        expect(json_response['message']).to eq('User created successfully')
        expect(json_response['data']).to have_key('user_id')
        expect(json_response['data']).to have_key('email')
        expect(json_response['data']).to have_key('authentication_token')
      end
    end

    context 'with invalid parameters' do
      let(:service) { instance_double(Users::Create, success?: false, errors: [ 'Invalid email format' ]) }

      before do
        allow(Users::Create).to receive(:call).and_return(service)
      end

      it 'returns error response' do
        post :create, params: invalid_user_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to eq('User could not be created')
        expect(json_response['errors']).to eq([ 'Invalid email format' ])
      end
    end
  end

  describe '#me' do
    before do
      authenticate_user(user)
    end

    it 'returns current user profile' do
      service = instance_double(Users::Me, user: user)
      allow(Users::Me).to receive(:call).with(user).and_return(service)

      get :me

      expect(response).to have_http_status(:success)
      expect(json_response['status']).to eq('success')
      expect(json_response['message']).to eq('User profile')
      expect(json_response['data']).to have_key('user_id')
      expect(json_response['data']).to have_key('email')
      expect(json_response['data']['email']).to eq(user.email)
    end
  end
end
