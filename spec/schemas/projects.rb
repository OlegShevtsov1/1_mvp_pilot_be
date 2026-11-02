require 'schemas/tasks'

module Schemas
  module Projects
    PROJECT_SCHEMA = {
      type: :object,
      properties: {
        id: { type: :integer },
        name: { type: :string },
        description: { type: :string },
        user_id: { type: :integer },
        created_at: { type: :string, format: :date_time },
        updated_at: { type: :string, format: :date_time },
        tasks: { type: :array, items: Schemas::Tasks::TASK_SCHEMA }
      },
      required: %w[id name description tasks]
    }.freeze

    PROJECT_REQUEST_SCHEMA = {
      type: :object,
      properties: {
        project: {
          type: :object,
          properties: {
            name: { type: :string, minLength: 5, maxLength: 20 },
            description: { type: :string, minLength: 20, maxLength: 120 }
          }
        }
      },
      required: %w[project]
    }.freeze

    PROJECT_RESPONSE_SCHEMA = PROJECT_SCHEMA

    PROJECTS_COLLECTION_SCHEMA = {
      type: :array,
      items: PROJECT_SCHEMA
    }.freeze
  end
end
