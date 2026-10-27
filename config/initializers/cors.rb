# Browsers may call this API only from the origins in CORS_ALLOWED_ORIGINS (comma-separated,
# e.g. https://app.dev.example.com). Read per request; unset or empty allows no origin.
# No credentials: the API authenticates with headers (bearer Authorization, legacy token headers), not
# cookies, so any request header is allowed. Retry-After is exposed so the browser can read it on a 429.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins { |source, _env| ENV.fetch('CORS_ALLOWED_ORIGINS') { '' }.split(',').map(&:strip).include?(source) }

    resource '*',
      headers: :any,
      expose: %w[Retry-After],
      methods: %i[get post put patch delete options head]
  end
end
