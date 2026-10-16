RSpec.describe Tasks::Create do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:valid_params) do
    ActionController::Parameters.new({ task:
                                         { name: "New Task", description: "Task description", status: "not_started" } })
  end
  let(:invalid_params) do
    ActionController::Parameters.new({ task: { name: "", description: "", status: nil } })
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(user, project, valid_params) }

      subject { service.call }

      it 'creates a new task' do
        expect { service.call }.to change(Task, :count).by(1)
      end

      it 'associates the task with the project' do
        expect(subject.task.project).to eq(project)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end
    end

    context 'with invalid parameters' do
      let(:service) { described_class.new(user, project, invalid_params) }

      subject { service.call }

      it 'does not create a new task' do
        expect { service.call }.not_to change(Task, :count)
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
