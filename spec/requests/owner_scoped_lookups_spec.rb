require 'rails_helper'

RSpec.describe 'Project and task lookups scoped to the owner', type: :request do
  let(:owner) { create(:user) }
  let(:intruder) { create(:user) }
  let!(:project) { create(:project, user: owner) }
  let!(:task) { create(:task, project: project) }
  let!(:intruder_project) { create(:project, user: intruder) }

  def bearer_for(user)
    { 'Authorization' => "Bearer #{create(:oauth_access_token, resource_owner_id: user.id).plaintext_token}" }
  end

  def answer = [ response.status, JSON.parse(response.body) ]

  describe "another user's project or task (AC-17)" do
    let(:headers) { bearer_for(intruder) }
    let(:not_found) { [ 404, { 'error' => 'Not Found' } ] }

    def answer_to(method, path, params = {})
      public_send(method, path, headers: headers, params: params)
      answer
    end

    it 'shows a project like a missing one' do
      expect(answer_to(:get, "/api/v1/projects/#{project.id}")).to eq(not_found)
      expect(answer_to(:get, '/api/v1/projects/0')).to eq(not_found)
    end

    it 'refuses to change a project like a missing one' do
      expect {
        expect(answer_to(:patch, "/api/v1/projects/#{project.id}", { project: { name: 'Taken over' } })).to eq(not_found)
      }.not_to(change { project.reload.attributes })
      expect(answer_to(:patch, '/api/v1/projects/0', { project: { name: 'Taken over' } })).to eq(not_found)
    end

    it 'refuses to delete a project like a missing one' do
      expect(answer_to(:delete, "/api/v1/projects/#{project.id}")).to eq(not_found)
      expect(Project.exists?(project.id)).to be(true)
      expect(answer_to(:delete, '/api/v1/projects/0')).to eq(not_found)
    end

    it 'lists the tasks of a project like a missing one' do
      expect(answer_to(:get, "/api/v1/projects/#{project.id}/tasks")).to eq(not_found)
      expect(answer_to(:get, '/api/v1/projects/0/tasks')).to eq(not_found)
    end

    it 'shows a task like a missing one' do
      expect(answer_to(:get, "/api/v1/projects/#{project.id}/tasks/#{task.id}")).to eq(not_found)
      expect(answer_to(:get, "/api/v1/projects/#{intruder_project.id}/tasks/#{task.id}")).to eq(not_found)
      expect(answer_to(:get, "/api/v1/projects/#{intruder_project.id}/tasks/0")).to eq(not_found)
    end

    it 'refuses to change a task like a missing one' do
      expect {
        expect(answer_to(:patch, "/api/v1/projects/#{project.id}/tasks/#{task.id}",
                         { task: { status: 'completed' } })).to eq(not_found)
        expect(answer_to(:patch, "/api/v1/projects/#{intruder_project.id}/tasks/#{task.id}",
                         { task: { status: 'completed' } })).to eq(not_found)
      }.not_to(change { task.reload.attributes })
    end

    it 'refuses to delete a task like a missing one' do
      expect(answer_to(:delete, "/api/v1/projects/#{project.id}/tasks/#{task.id}")).to eq(not_found)
      expect(answer_to(:delete, "/api/v1/projects/#{intruder_project.id}/tasks/#{task.id}")).to eq(not_found)
      expect(Task.exists?(task.id)).to be(true)
    end

    it "refuses to add a task to another user's project like a missing one" do
      expect {
        expect(answer_to(:post, "/api/v1/projects/#{project.id}/tasks",
                         { task: { name: 'Planted', description: 'x' * 20, status: 'not_started' } })).to eq(not_found)
      }.not_to(change { project.tasks.count })
    end
  end

  describe 'the owner (unchanged)' do
    it 'still shows and changes their own project and shows its task' do
      headers = bearer_for(owner)

      get "/api/v1/projects/#{project.id}", headers: headers
      expect(response).to have_http_status(:ok)
      patch "/api/v1/projects/#{project.id}", headers: headers, params: { project: { name: 'Renamed' } }
      expect(response).to have_http_status(:ok)
      expect(project.reload.name).to eq('Renamed')
      get "/api/v1/projects/#{project.id}/tasks/#{task.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig('data', 'id')).to eq(task.id)
    end
  end

  describe 'a signed-out device (AC-22)' do
    let(:revoked) do
      token = create(:oauth_access_token, resource_owner_id: owner.id)
      token.revoke
      { 'Authorization' => "Bearer #{token.plaintext_token}" }
    end

    [ '/api/v1/projects', '/api/v1/projects/%<id>s', '/api/v1/projects/%<id>s/tasks' ].each do |template|
      it "answers Not Authorized and shows nothing for #{template}" do
        path = format(template, id: project.id)

        get path
        expect(answer).to eq([ 401, { 'error' => 'Not Authorized' } ])
        get path, headers: revoked
        expect(answer).to eq([ 401, { 'error' => 'Not Authorized' } ])
      end
    end
  end
end
