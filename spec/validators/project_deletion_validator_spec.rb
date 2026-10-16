RSpec.describe ProjectDeletionValidator do
  describe '#validate' do
    let(:validator) { described_class.new }
    let(:project) { create(:project) }

    context 'when project has tasks' do
      before do
        create(:task, project: project)
      end

      it 'adds error to the record' do
        validator.validate(project)
        expect(project.errors[:base]).to include('Cannot delete record because dependent tasks exist')
      end
    end

    context 'when project has no tasks' do
      it 'does not add any errors' do
        validator.validate(project)
        expect(project.errors[:base]).to be_empty
      end
    end
  end
end
