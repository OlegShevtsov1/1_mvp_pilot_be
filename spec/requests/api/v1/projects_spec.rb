require 'swagger_helper'
require 'schemas/projects'

RSpec.describe 'API V1 Projects', type: :request do
  let(:user) { create(:user) }
  let(:token) { user.authentication_token }
  let(:email) { user.email }

  path '/api/v1/projects' do
    auth_parameters

    get 'Lists all projects for user' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '200', 'projects found' do
        schema schema_data_obj(Schemas::Projects::PROJECTS_COLLECTION_SCHEMA)
        authenticate_with_token

        before do
          create_list(:project, 3, user: user)
        end

        run_test_with_example!
      end

      response '401', 'unauthorized' do
        let(:'X-User-Token') { 'invalid' }
        let(:'X-User-Email') { email }

        run_test!
      end
    end

    post 'Creates a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :project, in: :body, schema: Schemas::Projects::PROJECT_REQUEST_SCHEMA

      response '201', 'project created' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_token
        let(:project) { { project: { name: 'Test Project', description: 'This is a test description with at least 20 characters' } } }

        run_test_with_example!
      end

      response '422', 'invalid request' do
        authenticate_with_token
        let(:project) { { project: { name: '', description: '' } } }

        run_test!
      end
    end
  end

  path '/api/v1/projects/{id}' do
    parameter name: 'id', in: :path, type: :integer, required: true
    auth_parameters

    let(:existing_project) { create(:project, user: user) }
    let(:id) { existing_project.id }

    get 'Retrieves a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '200', 'project found' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_token

        run_test_with_example!
      end

      response '404', 'project not found' do
        authenticate_with_token
        let(:id) { 999999 }

        run_test!
      end
    end

    put 'Updates a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security
      parameter name: :project, in: :body, schema: Schemas::Projects::PROJECT_REQUEST_SCHEMA

      response '200', 'project updated' do
        schema schema_data_obj(Schemas::Projects::PROJECT_RESPONSE_SCHEMA)
        authenticate_with_token
        let(:project) { { project: { name: 'Updated Project', description: 'This is an updated description with at least 20 characters' } } }

        run_test_with_example!
      end
    end

    delete 'Deletes a project' do
      tags 'Projects'
      consumes 'application/json'
      produces 'application/json'
      auth_security

      response '204', 'project deleted' do
        authenticate_with_token

        run_test!
      end
    end
  end
end
