RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  config.openapi_specs = {
    'v1/swagger.json' => {
      openapi: '3.0.1',
      info: {
        title: 'Pilot API',
        version: 'v1',
        description: 'API documentation for Pilot application'
      },
      components: {
        securitySchemes: {
          x_auth_token: {
            type: :apiKey,
            name: 'X-User-Token',
            in: :header
          },
          x_auth_email: {
            type: :apiKey,
            name: 'X-User-Email',
            in: :header
          }
        }
      },
      paths: {},
      servers: [
        {
          url: 'http://localhost:3000',
          description: 'PILOT server'
        }
      ]
    }
  }

  config.openapi_format = :json
end

def schema_data_obj(schema)
  schema(type: :object,
         properties: {
           data: schema
         },
         required: %w[data])
end

def run_test_with_example!(&)
  after do |example|
    example.metadata[:response][:content] = {
      'application/json' => {
        example: JSON.parse(response.body, symbolize_names: true)
      }
    }
  end
  run_test!(&)
end

def json_response
  JSON.parse @response.body if @response.body.present?
end
