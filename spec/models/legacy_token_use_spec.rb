RSpec.describe 'LegacyTokenUse', type: :model do
  subject { build(:legacy_token_use) }

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:used_on) }
    it { is_expected.to validate_uniqueness_of(:used_on).scoped_to(:user_id) }
    it { is_expected.to validate_numericality_of(:uses_count).only_integer.is_greater_than_or_equal_to(0) }
  end
end
