RSpec.describe Users::Me do
  let(:user) { create(:user) }

  describe '#call' do
    let(:service) { described_class.new(user) }

    subject { service.call }

    it 'returns the user object' do
      expect(subject.user).to eq(user)
    end

    it 'returns success' do
      expect(subject.success?).to be_truthy
    end

    it 'has no errors' do
      expect(subject.errors).to be_empty
    end

    it 'returns unprocessable_entity status when there are errors' do
      expect(subject.status_error).to eq(:unprocessable_entity)
    end
  end
end
