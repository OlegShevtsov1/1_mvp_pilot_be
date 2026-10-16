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
  end
end
