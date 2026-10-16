RSpec.describe BaseApplication::Authenticate do
  let(:user) { create(:user) }

  describe '#call' do
    subject { described_class.call(headers) }

    context 'with a matching email and token' do
      let(:headers) { { 'X-User-Email' => user.email, 'X-User-Token' => user.authentication_token } }

      it 'authenticates the user' do
        expect(subject).to eq(success: true, current_user: user)
      end
    end

    context 'with a wrong token' do
      let(:headers) { { 'X-User-Email' => user.email, 'X-User-Token' => 'not-the-token' } }

      it 'does not authenticate' do
        expect(subject).to eq(success: false, current_user: nil)
      end
    end

    context 'when the stored token is blank and the sent token is blank' do
      let(:headers) { { 'X-User-Email' => user.email, 'X-User-Token' => '' } }

      before { user.update_column(:authentication_token, '') }

      it 'does not authenticate' do
        expect(subject).to eq(success: false, current_user: nil)
      end
    end
  end
end
