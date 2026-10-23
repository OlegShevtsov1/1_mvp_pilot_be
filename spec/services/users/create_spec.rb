RSpec.describe Users::Create do
  let(:valid_params) do
    ActionController::Parameters.new({ user:
                                        { email: "test@example.com",
                                          password: "password123",
                                          password_confirmation: "password123" } })
  end
  let(:invalid_params) do
    ActionController::Parameters.new({ user:
                                        { email: "invalid_email",
                                          password: "pass",
                                          password_confirmation: "different" } })
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(valid_params) }

      subject { service.call }

      it 'creates a new user' do
        expect { service.call }.to change(User, :count).by(1)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end

      it 'returns a user with the correct email' do
        expect(subject.user.email).to eq("test@example.com")
      end
    end

    context 'with invalid parameters' do
      let(:service) { described_class.new(invalid_params) }

      subject { service.call }

      it 'does not create a new user' do
        expect { service.call }.not_to change(User, :count)
      end

      it 'returns errors' do
        expect(subject.errors).not_to be_empty
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns unprocessable_entity status' do
        expect(subject.status_error).to eq(:unprocessable_entity)
      end
    end

    context 'with one field wrong' do
      {
        'a malformed email' => [ { email: 'not-an-email' }, 'Email is invalid' ],
        'a short password' => [ { password: 'short', password_confirmation: 'short' },
                                'Password is too short (minimum is 6 characters)' ],
        'a mismatched confirmation' => [ { password_confirmation: 'different123' },
                                         "Password confirmation doesn't match Password" ]
      }.each do |case_name, (fields, message)|
        it "names the field for #{case_name} and creates no user" do
          params = ActionController::Parameters.new(
            user: { email: 'one@example.com', password: 'password123', password_confirmation: 'password123' }.merge(fields)
          )
          service = described_class.new(params)

          expect { service.call }.not_to change(User, :count)
          expect(service.errors).to include(message)
        end
      end
    end
  end

  describe '#token_fields' do
    it 'holds the new token pair of this device when the web client is configured' do
      Doorkeeper::Application.create!(name: 'todolist web', uid: 'web-client-test', confidential: false)

      service = with_env('OAUTH_CLIENT_ID' => 'web-client-test') { described_class.call(valid_params) }

      expect(service.token_fields.keys).to contain_exactly(:access_token, :refresh_token, :expires_in)
      expect(OauthAccessToken.where(resource_owner_id: service.user.id).count).to eq(1)
    end

    it 'is empty without a configured web client' do
      service = with_env('OAUTH_CLIENT_ID' => nil) { described_class.call(valid_params) }

      expect(service.token_fields).to eq({})
    end

    it 'is empty and the user is still created when no application has the configured uid' do
      service = nil

      expect do
        service = with_env('OAUTH_CLIENT_ID' => 'no-such-client') { described_class.call(valid_params) }
      end.to change(User, :count).by(1)
      expect(service.token_fields).to eq({})
    end
  end
end
