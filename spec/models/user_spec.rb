RSpec.describe User, type: :model do
  subject { build(:user) }

  describe 'associations' do
    it { is_expected.to have_many(:projects).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:password) }
  end

  describe 'authentication' do
    let!(:user) { create(:user) }

    context 'with valid credentials' do
      it 'authenticates the user' do
        expect(user.valid_password?(user.password)).to be_truthy
      end
    end

    context 'with invalid credentials' do
      it 'does not authenticate the user' do
        expect(user.valid_password?('wrong_password')).to be_falsey
      end
    end
  end

  describe 'token authentication' do
    let(:user) { create(:user) }

    it 'generates an authentication token' do
      expect(user.authentication_token).not_to be_nil
    end
  end
end
