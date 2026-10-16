RSpec.describe Tasks::Delete do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let!(:task) { create(:task, project: project) }

  describe '#call' do
    context 'when deletion is successful' do
      let(:service) { described_class.new(user, project, task) }

      subject { service.call }

      it 'deletes the task' do
        expect { service.call }.to change(Task, :count).by(-1)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end
    end

    context 'when deletion fails' do
      let(:service) { described_class.new(user, project, task) }

      subject { service.call }

      before do
        allow(task).to receive(:destroy).and_return(false)
        allow(task).to receive(:errors).and_return(
          double(full_messages: [ 'Task cannot be deleted' ])
        )
      end

      it 'does not delete the task' do
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
