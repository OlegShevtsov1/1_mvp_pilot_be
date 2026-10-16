RSpec.describe Project, type: :model do
  subject { build(:project) }

  describe 'associations' do
    it { is_expected.to belong_to(:user).counter_cache(true) }
    it { is_expected.to have_many(:tasks).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:description) }

    # Name length validations
    it { is_expected.to validate_length_of(:name).is_at_least(5) }
    it { is_expected.to validate_length_of(:name).is_at_most(20) }

    # Description length validations
    it { is_expected.to validate_length_of(:description).is_at_least(20) }
    it { is_expected.to validate_length_of(:description).is_at_most(120) }

    context 'with invalid attributes' do
      it 'is invalid with a short name' do
        project = build(:project, name: 'a' * 4)
        expect(project).not_to be_valid
        expect(project.errors[:name]).to include('is too short (minimum is 5 characters)')
      end

      it 'is invalid with a long name' do
        project = build(:project, name: 'a' * 21)
        expect(project).not_to be_valid
        expect(project.errors[:name]).to include('is too long (maximum is 20 characters)')
      end

      it 'is invalid with a short description' do
        project = build(:project, description: 'a' * 19)
        expect(project).not_to be_valid
        expect(project.errors[:description]).to include('is too short (minimum is 20 characters)')
      end

      it 'is invalid with a long description' do
        project = build(:project, description: 'a' * 121)
        expect(project).not_to be_valid
        expect(project.errors[:description]).to include('is too long (maximum is 120 characters)')
      end
    end

    context 'with valid attributes' do
      it 'is valid with a name at minimum length' do
        project = build(:project, name: 'a' * 5)
        expect(project).to be_valid
      end

      it 'is valid with a name at maximum length' do
        project = build(:project, name: 'a' * 20)
        expect(project).to be_valid
      end

      it 'is valid with a description at minimum length' do
        project = build(:project, description: 'a' * 20)
        expect(project).to be_valid
      end

      it 'is valid with a description at maximum length' do
        project = build(:project, description: 'a' * 120)
        expect(project).to be_valid
      end
    end
  end

  describe 'task counts' do
    let!(:project) { create(:project) }

    context 'when tasks are added' do
      let!(:tasks) { create_list(:task, 3, project: project) }

      it 'keeps track of the tasks count' do
        expect(project.tasks.count).to eq(3)
      end
    end
  end

  describe 'deletion restrictions' do
    let!(:project) { create(:project) }

    context 'when project has tasks' do
      before { create(:task, project: project) }

      it 'cannot be deleted' do
        expect { project.destroy }.not_to change(Project, :count)
        expect(project.errors[:base]).to include("Cannot delete record because dependent tasks exist")
      end
    end

    context 'when project has no tasks' do
      it 'can be deleted' do
        expect { project.destroy }.to change(Project, :count).by(-1)
      end
    end
  end
end
