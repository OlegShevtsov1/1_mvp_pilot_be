RSpec.describe Api::V1::TasksController, type: :controller do
  render_views

  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:task) { create(:task, project: project) }

  before do
    authenticate_user(user)
    allow(controller).to receive(:authorize!).and_return(true)
    controller.instance_variable_set(:@project, project)
  end

  describe '#index' do
    before do
      create_list(:task, 3, project: project)

      task
    end

    it 'returns project tasks' do
      get :index, params: { project_id: project.id }

      expect(response).to have_http_status(:success)
      expect(json_response).to have_key('data')
      expect(json_response['data'].length).to eq(4)
    end
  end

  describe '#show' do
    it 'returns requested task' do
      controller.instance_variable_set(:@task, task)

      get :show, params: { project_id: project.id, id: task.id }

      expect(response).to have_http_status(:success)
      expect(json_response['data']['id']).to eq(task.id)
      expect(json_response['data']['name']).to eq(task.name)
    end
  end

  describe '#create' do
    let(:valid_params) do
      { task: { name: 'New Task', description: 'This is a test task description', status: 'not_started' } }
    end
    let(:invalid_params) do
      { task: { name: '', description: '', status: 'not_started' } }
    end

    it 'creates a new task with valid params' do
      expect {
        post :create, params: valid_params.merge(project_id: project.id)
      }.to change(Task, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['data']['name']).to eq('New Task')
    end

    it 'fails with invalid params' do
      expect {
        post :create, params: invalid_params.merge(project_id: project.id)
      }.not_to change(Task, :count)

      expect(response).to have_http_status(422)
      expect(json_response).to have_key('errors')
    end
  end

  describe '#update' do
    let(:valid_params) do
      { task: { name: 'Updated Task', description: 'Updated task description', status: 'in_progress' } }
    end
    let(:invalid_params) do
      { task: { name: '', description: '', status: 'not_started' } }
    end

    before do
      controller.instance_variable_set(:@task, task)
    end

    it 'updates task with valid params' do
      put :update, params: valid_params.merge(project_id: project.id, id: task.id)

      task.reload
      expect(task.name).to eq('Updated Task')
      expect(task.status).to eq('in_progress')
      expect(response).to have_http_status(:success)
    end

    it 'fails with invalid params' do
      put :update, params: invalid_params.merge(project_id: project.id, id: task.id)

      task.reload
      expect(task.name).to eq('Sample Task')
      expect(response).to have_http_status(422)
      expect(json_response).to have_key('errors')
    end
  end

  describe '#destroy' do
    before do
      controller.instance_variable_set(:@task, task)
    end

    it 'removes task' do
      expect {
        delete :destroy, params: { project_id: project.id, id: task.id }
      }.to change(Task, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'handles errors if task cannot be deleted' do
      allow_any_instance_of(Tasks::Delete).to receive(:success?).and_return(false)
      allow_any_instance_of(Tasks::Delete).to receive(:errors).and_return([ 'Cannot delete task' ])
      allow_any_instance_of(Tasks::Delete).to receive(:status_error).and_return(422)

      expect {
        delete :destroy, params: { project_id: project.id, id: task.id }
      }.not_to change(Task, :count)

      expect(response).to have_http_status(422)
      expect(json_response['errors']).to include('Cannot delete task')
    end
  end
end
