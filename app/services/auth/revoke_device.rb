module Auth
  # Sign-out ends this device's access (AC-11). A bearer token's row holds its refresh token too, so revoking it ends
  # both; a legacy token belongs to the account, so it is rotated and ends for every device using it (AC-11b,
  # ADR-0005).
  class RevokeDevice < ApplicationService
    def initialize(user, bearer)
      @user = user
      @bearer = bearer
    end

    def call
      return OauthAccessToken.by_token(@bearer)&.revoke if @bearer.present?

      # acts_as_token_authenticatable regenerates a blank token on save. Only the token changes, so an old row's
      # unrelated validations cannot make sign-out fail.
      @user.authentication_token = nil
      @user.save!(validate: false)
    end
  end
end
