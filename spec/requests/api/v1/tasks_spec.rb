require 'swagger_helper'
require 'schemas/tasks'

RSpec.describe 'API V1 Tasks', type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user) }
  let(:allowed_statuses_error) { 'Status must be one of: not_started, in_progress, completed' }

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

  path '/api/v1/projects/{project_id}/tasks' do
    parameter name: 'project_id', in: :path, type: :integer, required: true

    let(:project_id) { project.id }

    get 'Lists all tasks for a project' do
      tags 'Tasks'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '200', 'tasks found' do
        schema schema_data_obj(Schemas::Tasks::TASKS_COLLECTION_SCHEMA)
        authenticate_with_bearer

        before do
          create_list(:task, 3, project: project)
        end

        run_test_with_example!
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'project not found' do
        authenticate_with_bearer

        context 'when the project does not exist' do
          let(:project_id) { 999999 }

          it_behaves_like 'a not found request'
        end

        context "when the project is another user's" do
          let(:project_id) { create(:project).id }

          it_behaves_like 'a not found request'
        end
      end
    end

    post 'Creates a task' do
      tags 'Tasks'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :task, in: :body, schema: Schemas::Tasks::TASK_REQUEST_SCHEMA

      let(:task) { { task: { name: 'Test Task', description: 'This is a test task' } } }

      response '201', 'task created' do
        schema schema_data_obj(Schemas::Tasks::TASK_RESPONSE_SCHEMA)
        authenticate_with_bearer

        run_test_with_example! do
          expect(json_response.dig('data', 'status')).to eq('not_started')
          expect(Task.find(json_response.dig('data', 'id'))).to be_not_started
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'project not found' do
        authenticate_with_bearer
        let(:project_id) { 999999 }

        it_behaves_like 'a not found request'
      end

      response '422', 'invalid request' do
        authenticate_with_bearer
        let!(:task_count_before) { Task.count }

        context 'with an empty name and description' do
          let(:task) { { task: { name: '', description: '' } } }

          run_test! do
            expect(json_response['errors']).to include("Name can't be blank", "Description can't be blank")
            expect(Task.count).to eq(task_count_before)
          end
        end

        context 'with an empty status' do
          let(:task) { { task: { name: 'Test Task', description: 'This is a test task', status: '' } } }

          run_test! do
            expect(json_response['errors']).to include(allowed_statuses_error)
            expect(Task.count).to eq(task_count_before)
          end
        end

        context 'with a status outside the three' do
          let(:task) { { task: { name: 'Test Task', description: 'This is a test task', status: 'archived' } } }

          run_test! do
            expect(json_response['errors']).to include(allowed_statuses_error)
            expect(Task.count).to eq(task_count_before)
          end
        end
      end
    end
  end

  path '/api/v1/projects/{project_id}/tasks/{id}' do
    parameter name: 'project_id', in: :path, type: :integer, required: true
    parameter name: 'id', in: :path, type: :integer, required: true

    let(:existing_task) { create(:task, project: project) }
    let(:project_id) { project.id }
    let(:id) { existing_task.id }

    get 'Fetches a task' do
      tags 'Tasks'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '200', 'task found' do
        schema schema_data_obj(Schemas::Tasks::TASK_RESPONSE_SCHEMA)
        authenticate_with_bearer

        run_test_with_example!
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'task not found' do
        authenticate_with_bearer
        let(:id) { 999999 }

        it_behaves_like 'a not found request'
      end
    end

    put 'Updates a task' do
      tags 'Tasks'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :task, in: :body, schema: Schemas::Tasks::TASK_REQUEST_SCHEMA

      let(:task) { { task: { status: 'in_progress' } } }

      response '200', 'task updated' do
        schema schema_data_obj(Schemas::Tasks::TASK_RESPONSE_SCHEMA)
        authenticate_with_bearer

        context 'when the status changes to in progress' do
          run_test_with_example! do
            expect(json_response.dig('data', 'status')).to eq('in_progress')
            expect(existing_task.reload).to be_in_progress
          end
        end

        context 'when the status changes to completed' do
          let(:task) { { task: { status: 'completed' } } }

          run_test! do
            expect(json_response.dig('data', 'status')).to eq('completed')
            expect(existing_task.reload).to be_completed
          end
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'task not found' do
        authenticate_with_bearer
        let(:id) { 999999 }

        it_behaves_like 'a not found request'
      end

      response '422', 'invalid request' do
        authenticate_with_bearer

        context 'with an empty name' do
          let(:task) { { task: { name: '' } } }

          run_test! do
            expect(json_response['errors']).to include("Name can't be blank")
            expect(existing_task.reload.name).to be_present
          end
        end

        context 'with an empty status' do
          let(:task) { { task: { status: '' } } }

          run_test! do
            expect(json_response['errors']).to include(allowed_statuses_error)
            expect(existing_task.reload).to be_not_started
          end
        end

        context 'with a status outside the three' do
          let(:task) { { task: { status: 'archived' } } }

          run_test! do
            expect(json_response['errors']).to include(allowed_statuses_error)
            expect(existing_task.reload).to be_not_started
          end
        end
      end
    end

    delete 'Deletes a task' do
      tags 'Tasks'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '204', 'task deleted' do
        authenticate_with_bearer

        run_test! do
          expect(Task.exists?(existing_task.id)).to be(false)
        end
      end

      response '401', 'unauthorized' do
        it_behaves_like 'an unauthorized request'
      end

      response '404', 'task not found' do
        authenticate_with_bearer
        let(:id) { 999999 }

        it_behaves_like 'a not found request'
      end
    end
  end
end
