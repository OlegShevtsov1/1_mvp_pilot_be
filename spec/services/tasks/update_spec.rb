RSpec.describe Tasks::Update do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:task) do
    create(:task, project: project, name: "Original Task", description: "Original description", status: "not_started")
  end
  let(:valid_params) do
    ActionController::Parameters.new(
      { task: { name: "Updated Task", description: "Updated description", status: "in_progress" } })
  end
  let(:invalid_params) do
    ActionController::Parameters.new({ task: { name: "", description: "", status: nil } })
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(user, project, task, valid_params) }

      subject { service.call }

      it 'updates the task' do
        subject
        task.reload
        expect(task.name).to eq("Updated Task")
        expect(task.description).to eq("Updated description")
        expect(task.status).to eq("in_progress")
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end
    end

    context 'with invalid parameters' do
      let(:service) { described_class.new(user, project, task, invalid_params) }
      subject { service.call }

      it 'does not update the task' do
        original_name = task.name
        original_status = task.status
        service.call
        task.reload
        expect(task.name).to eq(original_name)
        expect(task.status).to eq(original_status)
      end

      it 'returns errors' do
        expect(subject.errors).not_to be_empty
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end
    end
  end
end
