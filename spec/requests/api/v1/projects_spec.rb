require 'swagger_helper'
require 'schemas/projects'

RSpec.describe 'API V1 Projects', type: :request do
  let(:user) { create(:user) }

  shared_examples 'an unauthorized request' do
    let(:Authorization) { 'Bearer invalid' }

    run_test! do
      expect(json_response).to eq('error' => 'Not Authorized')
    end
  end

  shared_examples 'a not found request' do
    run_test! do
      expect(json_response).to eq('error' => 'Not Found')
    end
  end

  path '/api/v1/projects' do
    get 'Lists all projects for user' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :task_status, in: :query, required: false,
                schema: { type: :string, enum: Task::STATUSES }

      let!(:completed_project) { create(:project, user: user) }
      let!(:not_started_project) { create(:project, user: user) }

      before do
        create(:task, :completed, project: completed_project)
        create(:task, project: not_started_project)
        create(:task, :completed, project: create(:project))
      end

      response '200', 'projects found' do
        schema schema_data_obj(Schemas::Projects::PROJECTS_COLLECTION_SCHEMA)
        authenticate_with_bearer

        context 'without a task status filter' do
          run_test_with_example! do
            data = json_response['data']
            expect(data.pluck('id')).to contain_exactly(completed_project.id, not_started_project.id)
            expect(data.to_h { |project| [ project['id'], project['tasks'].pluck('status') ] })
              .to eq(completed_project.id => %w[completed], not_started_project.id => %w[not_started])
          end
        end

        context 'with a task status filter' do
          let(:task_status) { 'completed' }

          run_test! do
            expect(json_response['data'].pluck('id')).to eq([ completed_project.id ])
          end
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end
    end

    post 'Creates a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :project, in: :body, schema: Schemas::Projects::PROJECT_REQUEST_SCHEMA

      let(:project) { { project: { name: 'Test Project', description: 'This is a test description with at least 20 characters' } } }

      response '201', 'project created' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_bearer

        run_test_with_example! do
          expect(json_response.dig('data', 'name')).to eq('Test Project')
          expect(Project.find(json_response.dig('data', 'id')).user_id).to eq(user.id)
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '422', 'invalid request' do
        authenticate_with_bearer
        let!(:project_count_before) { Project.count }

        context 'with a name shorter than 5 characters' do
          let(:project) { { project: { name: 'abcd', description: 'x' * 30 } } }

          run_test! do
            expect(json_response['errors']).to include('Name is too short (minimum is 5 characters)')
            expect(Project.count).to eq(project_count_before)
          end
        end

        context 'with a description longer than 120 characters' do
          let(:project) { { project: { name: 'Test Project', description: 'x' * 121 } } }

          run_test! do
            expect(json_response['errors']).to include('Description is too long (maximum is 120 characters)')
            expect(Project.count).to eq(project_count_before)
          end
        end
      end
    end
  end

  path '/api/v1/projects/{id}' do
    parameter name: 'id', in: :path, type: :integer, required: true

    let(:existing_project) { create(:project, user: user) }
    let(:id) { existing_project.id }

    get 'Retrieves a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '200', 'project found' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_bearer

        run_test_with_example!
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'project not found' do
        authenticate_with_bearer

        context 'when the project does not exist' do
          let(:id) { 999999 }

          it_behaves_like 'a not found request'
        end

        context "when the project is another user's" do
          let(:id) { create(:project).id }

          it_behaves_like 'a not found request'
        end
      end
    end

    put 'Updates a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :project, in: :body, schema: Schemas::Projects::PROJECT_REQUEST_SCHEMA

      let(:project) { { project: { name: 'Updated Project' } } }

      response '200', 'project updated' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_bearer

        run_test_with_example! do
          expect(json_response.dig('data', 'name')).to eq('Updated Project')
          expect(existing_project.reload.name).to eq('Updated Project')
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'project not found' do
        authenticate_with_bearer
        let(:id) { 999999 }

        it_behaves_like 'a not found request'
      end

      response '422', 'invalid request' do
        authenticate_with_bearer
        let(:project) { { project: { name: 'x' * 21 } } }

        run_test! do
          expect(json_response['errors']).to include('Name is too long (maximum is 20 characters)')
          expect(existing_project.reload.name).not_to eq('x' * 21)
        end
      end
    end

    delete 'Deletes a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '204', 'project deleted' do
        authenticate_with_bearer

        run_test! do
          expect(Project.exists?(existing_project.id)).to be(false)
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'project not found' do
        authenticate_with_bearer
        let(:id) { 999999 }

        it_behaves_like 'a not found request'
      end

      response '422', 'project still has tasks' do
        authenticate_with_bearer
        let!(:task) { create(:task, project: existing_project) }

        run_test! do
          expect(json_response['errors']).to eq([ 'Cannot delete record because dependent tasks exist' ])
          expect(Project.exists?(existing_project.id)).to be(true)
          expect(Task.exists?(task.id)).to be(true)
        end
      end
    end
  end
end
