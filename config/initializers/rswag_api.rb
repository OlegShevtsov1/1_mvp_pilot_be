Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.to_s + '/swagger'

  # The committed swagger.json lists localhost; serve the origin the reader actually reached
  # (behind kamal-proxy via X-Forwarded-Proto/Host) so "Try it out" targets this deployment.
  # Rswag ignores the return value: the document must be changed in place.
  c.swagger_filter = lambda do |swagger, env|
    swagger['servers'] = [
      { 'url' => Rack::Request.new(env).base_url,
        'description' => "PILOT #{ENV.fetch('SENTRY_ENVIRONMENT') { Rails.env }}" }
    ]
  end
end
