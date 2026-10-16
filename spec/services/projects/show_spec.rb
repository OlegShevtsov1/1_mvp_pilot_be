RSpec.describe Projects::Show do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }

  describe '#call' do
    let(:service) { described_class.new(user, project) }

    subject { service.call }

    it 'returns the project' do
      expect(subject.project).to eq(project)
    end

    it 'includes associated records' do
      expect(subject.project.association(:user)).to be_loaded
      expect(subject.project.association(:tasks)).to be_loaded
    end

    it 'returns success' do
      expect(subject.success?).to be_truthy
    end
  end
end
