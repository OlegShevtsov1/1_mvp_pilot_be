RSpec.describe Api::V1::ProjectsController, type: :controller do
  render_views

  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }

  before do
    authenticate_user(user)
    allow(controller).to receive(:authorize!).and_return(true)
  end

  describe '#index' do
    it 'returns user projects' do
      get :index

      expect(response).to have_http_status(:success)
      expect(json_response).to have_key('data')
    end
  end

  describe '#show' do
    it 'returns requested project' do
      get :show, params: { id: project.id }

      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(project.id)
    end
  end

  describe '#create' do
    let(:valid_params) do
      { name: 'New Project', description: 'This is a test description that is at least 20 characters long.' }
    end
    let(:invalid_params) { { name: '', description: 'Too short' } }

    it 'creates a new project with valid params' do
      expect { post :create, params: { project: valid_params } }.to change(Project, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json_response['data']['name']).to eq('New Project')
    end

    it 'fails with invalid params' do
      expect { post :create, params: { project: invalid_params } }.not_to change(Project, :count)
      expect(response).to have_http_status(422)
      expect(json_response).to have_key('errors')
    end
  end

  describe '#update' do
    let(:valid_params) do
      { name: 'Updated Name', description: 'Updated description that is at least 20 characters long.' }
    end
    let(:invalid_params) { { name: '', description: 'Too short' } }

    it 'updates project with valid params' do
      put :update, params: { id: project.id, project: valid_params }

      project.reload
      expect(project.name).to eq('Updated Name')
      expect(response).to have_http_status(:success)
    end

    it 'fails with invalid params' do
      put :update, params: { id: project.id, project: invalid_params }

      project.reload

      expect(project.name).to eq(project.name)
      expect(response).to have_http_status(422)
      expect(json_response).to have_key('errors')
    end
  end

  describe '#destroy' do
    it 'removes project without tasks' do
      project_to_delete = create(:project, user: user)

      expect {
        delete :destroy, params: { id: project_to_delete.id }
      }.to change(Project, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'fails to remove project with tasks' do
      project_with_tasks = create(:project, user: user)
      create(:task, project: project_with_tasks)

      expect {
        delete :destroy, params: { id: project_with_tasks.id }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(422)
      expect(json_response['errors']).to include('Cannot delete record because dependent tasks exist')
    end
  end
end
