# OAuth 2 token endpoint for the web client (ADR-0003, ADR-0006): password and Google ID-token grants (ADR-0004),
# one-hour access tokens and rotating refresh tokens, both stored as hashes. Failed password attempts are counted per
# source and refused above ten a minute (AC-10, ADR-0009).

# Doorkeeper keeps a grant's strategy for the life of the process, while development reloads the classes under app/,
# so it is given this stand-in, which looks the reloadable grant class up on every request.
module GoogleIdTokenGrantStrategy
  GRANT_TYPE = 'google_id_token'

  def self.new(server) = Auth::GoogleIdTokenGrant.new(server)
end

Doorkeeper.configure do
  orm :active_record
  api_only
  base_controller 'ActionController::API'

  # The row lock is held until the token is written (PasswordGrantUserLock below), and lock! reloads the row, so the
  # password is checked as it is after any Google link that held the lock first (AC-06).
  resource_owner_from_credentials do |_routes|
    user = User.find_for_database_authentication(email: params[:username])&.lock!
    next user if user&.valid_password?(params[:password])

    failed_sign_in!
    nil
  end

  grant_flows [ 'password', GoogleIdTokenGrantStrategy::GRANT_TYPE ]
  access_token_class 'OauthAccessToken'
  access_token_expires_in 1.hour
  use_refresh_token
  hash_token_secrets
  hash_application_secrets
  allow_token_introspection false
end

Doorkeeper::GrantFlow.register(GoogleIdTokenGrantStrategy::GRANT_TYPE,
                               grant_type_matches: GoogleIdTokenGrantStrategy::GRANT_TYPE,
                               grant_type_strategy: GoogleIdTokenGrantStrategy)

# The password and refresh grants check the user, then write the token. Each runs in one transaction that locks the
# user's row before the check, as Auth::LinkIdentity does before it links Google, so a token written while Google is
# being linked is revoked by the link, or the grant sees the removed password or revoked refresh token and refuses
# (AC-06). The password grant takes the lock in resource_owner_from_credentials, on the row it authenticates.
module PasswordGrantUserLock
  def authorize
    ActiveRecord::Base.transaction { super }
  end
end

module RefreshTokenGrantUserLock
  def authorize
    ActiveRecord::Base.transaction do
      User.lock.find_by(id: request.refresh_token&.resource_owner_id)
      super
    end
  end
end

Doorkeeper::Request::Password.prepend(PasswordGrantUserLock)
Doorkeeper::Request::RefreshToken.prepend(RefreshTokenGrantUserLock)
