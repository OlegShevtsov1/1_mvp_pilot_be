RSpec.describe Projects::Delete do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when project has no tasks' do
      let!(:project) { create(:project, user: user) }
      let(:service) { described_class.new(user, project) }

      subject { service.call }

      it 'deletes the project' do
        expect { service.call }.to change(Project, :count).by(-1)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end
    end

    context 'when project has tasks' do
      let!(:project) { create(:project, user: user) }
      let!(:task) { create(:task, project: project) }
      let(:service) { described_class.new(user, project) }

      subject { service.call }

      it 'does not delete the project' do
        expect { service.call }.not_to change(Project, :count)
      end

      it 'returns errors' do
        expect(subject.errors).not_to be_empty
        expect(subject.errors).to include('Cannot delete record because dependent tasks exist')
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns unprocessable_entity status' do
        expect(subject.status_error).to eq(:unprocessable_entity)
      end
    end

    context 'when project does not exist' do
      let(:non_existent_project) { double('Project', destroy: false) }
      let(:service) { described_class.new(user, non_existent_project) }

      subject { service.call }

      before do
        allow(non_existent_project).to receive(:errors).and_return(
          double(full_messages: [ 'Project not found' ])
        )
      end

      it 'returns error' do
        expect(subject.errors).to include('Project not found')
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns not_found status' do
        expect(subject.status_error).to eq(:not_found)
      end
    end
  end
end
