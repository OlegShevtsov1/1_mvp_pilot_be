# Links a Google account to an existing user and ends every other way into that account: the password, every
# access and refresh token and the legacy token (ADR-0004, AC-06). Token rows are revoked, not deleted, so the
# purge job still sees them.
module Auth
  class LinkIdentity < ApplicationService
    def initialize(user, uid)
      @user = user
      @uid = uid
    end

    # The row lock is the one the password and refresh grants take before they check the user
    # (config/initializers/doorkeeper.rb), so a token they write meanwhile is revoked here or refused after.
    def call
      @user.with_lock do
        @user.identities.create!(provider: Identity::GOOGLE, uid: @uid)
        @user.access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
        @user.encrypted_password = ''
        # simple_token_authentication generates a fresh legacy token on save.
        @user.authentication_token = nil
        @user.save!
      end
      @user
    end
  end
end
