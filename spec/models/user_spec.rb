RSpec.describe User, type: :model do
  subject { build(:user) }

  describe 'associations' do
    it { is_expected.to have_many(:projects).dependent(:destroy) }

    it do
      expect(subject).to have_many(:access_tokens)
        .class_name('OauthAccessToken').with_foreign_key(:resource_owner_id).dependent(:delete_all)
    end

    it { is_expected.to have_many(:identities).dependent(:destroy) }
    it { is_expected.to have_many(:legacy_token_uses).dependent(:delete_all) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:password) }
  end

  describe 'password rule' do
    it 'is valid without a password when it has a Google identity' do
      user = described_class.new(email: 'Google.User@Example.com')
      user.identities.build(provider: 'google', uid: 'google-uid-new')

      expect(user).to be_valid
      user.save!
      user.reload
      expect(user.encrypted_password).to eq('')
      expect(user.valid_password?('')).to be(false)
      expect(user.email).to eq('google.user@example.com')
    end

    it 'still needs a password without an identity' do
      user = described_class.new(email: 'no.identity@example.com')

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it 'still refuses an empty password for a persisted password user' do
      user = create(:user)
      user.password = ''
      user.password_confirmation = ''

      expect(user).not_to be_valid
    end

    it 'saves a persisted password user without an identity when the password is not touched' do
      user = described_class.find(create(:user).id)
      user.email = 'updated@example.com'

      expect(user.save).to be(true)
    end

    it 'refuses the old password once a linked user\'s password is cleared' do
      user = create(:user)
      create(:identity, user:)
      user.reload
      user.encrypted_password = ''

      expect(user.save).to be(true)
      expect(user.reload.valid_password?('password')).to be(false)
    end
  end

  describe 'destroy' do
    let!(:user) { create(:user) }

    before do
      create(:oauth_access_token, resource_owner_id: user.id)
      create(:identity, user:)
      create(:legacy_token_use, user:)
      create(:project, user:)
    end

    it 'removes the access tokens, identity, legacy-use rows and projects' do
      expect { user.destroy! }
        .to change(OauthAccessToken, :count).by(-1)
        .and change(Identity, :count).by(-1)
        .and change(LegacyTokenUse, :count).by(-1)
        .and change(Project, :count).by(-1)
    end
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
