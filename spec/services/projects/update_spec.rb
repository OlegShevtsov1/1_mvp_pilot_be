RSpec.describe Projects::Update do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:valid_params) do
    ActionController::Parameters.new({ project:
                                       { name: "Updated Project",
                                         description: "This is an updated project description that's long enough." } })
  end
  let(:invalid_params) do
    ActionController::Parameters.new({ project:
                                       { name: "ab",
                                         description: "Too short" } })
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:service) { described_class.new(user, project, valid_params) }

      subject { service.call }

      it 'updates the project' do
        service.call
        project.reload

        expect(project.name).to eq("Updated Project")
        expect(project.description).to eq("This is an updated project description that's long enough.")
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
      let(:service) { described_class.new(user, project, invalid_params) }
      let(:original_name) { project.name }
      let(:original_description) { project.description }

      subject { service.call }

      it 'does not update the project' do
        service.call
        project.reload

        expect(project.name).to eq(original_name)
        expect(project.description).to eq(original_description)
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
