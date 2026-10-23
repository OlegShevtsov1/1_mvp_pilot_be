# Doorkeeper's access token row, one per sign-in (ADR-0003). A refresh revokes the old row at once instead of when
# the new token is first used, and a refresh token is refused 30 days after its row was issued (ADR-0006).
class OauthAccessToken < ApplicationRecord
  include ::Doorkeeper::Orm::ActiveRecord::Mixins::AccessToken

  REFRESH_TOKEN_IDLE_LIMIT = 30.days

  # Doorkeeper defers revoking the old row while a previous_refresh_token column exists.
  def self.refresh_token_revoked_on_use?
    false
  end

  def self.by_refresh_token(refresh_token)
    token = super
    token if token && token.created_at > REFRESH_TOKEN_IDLE_LIMIT.ago
  end
end
