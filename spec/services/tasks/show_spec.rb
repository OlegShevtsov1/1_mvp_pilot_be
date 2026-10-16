RSpec.describe Tasks::Show do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:task) { create(:task, project: project) }

  describe '#call' do
    let(:service) { described_class.new(user, project, task) }

    subject { service.call }

    it 'returns the task' do
      expect(subject.task).to eq(task)
    end

    it 'includes the project association' do
      expect(subject.task.project).to eq(project)
    end

    it 'returns success' do
      expect(subject.success?).to be_truthy
    end
  end
end
