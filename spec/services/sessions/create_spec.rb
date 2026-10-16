RSpec.describe Sessions::Create do
  let(:password) { "password123" }
  let!(:user) { create(:user, email: "test@example.com", password: password, password_confirmation: password) }

  let(:valid_params) do
    { email: user.email, password: password }
  end

  let(:invalid_email_params) do
    { email: "wrong@example.com", password: password }
  end

  let(:invalid_password_params) do
    { email: user.email, password: "wrong_password" }
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(valid_params) }

      subject { service.call }

      it 'finds the correct user' do
        expect(subject.user).to eq(user)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end

      it 'has no errors' do
        expect(subject.errors).to be_empty
      end
    end

    context 'with invalid email' do
      let(:service) { described_class.new(invalid_email_params) }

      subject { service.call }

      it 'returns nil for user' do
        expect(subject.user).to be_nil
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns an error message' do
        expect(subject.errors).to include('Invalid email or password')
      end

      it 'returns unauthorized status' do
        expect(subject.status_error).to eq(:unauthorized)
      end
    end

    context 'with invalid password' do
      let(:service) { described_class.new(invalid_password_params) }

      subject { service.call }

      it 'returns the user object' do
        expect(subject.user).to eq(user)
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns an error message' do
        expect(subject.errors).to include('Invalid email or password')
      end

      it 'returns unauthorized status' do
        expect(subject.status_error).to eq(:unauthorized)
      end
    end
  end
end
