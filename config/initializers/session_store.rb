require 'action_dispatch/middleware/session/redis_store'

Rails.application.config.session_store(
  ActionDispatch::Session::RedisStore,
  servers: [ ENV.fetch('REDIS_URL') { 'redis://localhost:6379/0' } ],
  expire_after: 90.minutes,
  key: '_pilot_session',
  secure: Rails.env.production?
)
