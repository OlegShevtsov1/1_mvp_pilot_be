RSpec.describe Projects::Create do
  let(:user) { create(:user) }
  let(:valid_params) do
    ActionController::Parameters.new({ project:
                                        { name: "New Project",
                                          description: "This is a project description that's long enough." } })
  end
  let(:invalid_params) do
    ActionController::Parameters.new({ project:
                                        { name: "ab",
                                          description: "Too short" } })
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(user, valid_params) }
      subject { service.call }

      it 'creates a new project' do
        expect { service.call }.to change(Project, :count).by(1)
      end

      it 'associates the project with the user' do
        expect(subject.project.user).to eq(user)
      end

      it 'returns success' do
        expect(subject.success?).to be_truthy
      end

      it 'includes associated records' do
        expect(subject.project.association(:user)).to be_loaded
        expect(subject.project.association(:tasks)).to be_loaded
      end
    end

    context 'with invalid parameters' do
      let(:service) { described_class.new(user, invalid_params) }
      subject { service.call }

      it 'does not create a new project' do
        expect { service.call }.not_to change(Project, :count)
      end

      it 'returns errors' do
        expect(subject.errors).not_to be_empty
      end

      it 'returns failure' do
        expect(subject.success?).to be_falsey
      end

      it 'returns unprocessable_entity status' do
        expect(subject.status_error).to eq(:unprocessable_entity)
      end
    end
  end
end
