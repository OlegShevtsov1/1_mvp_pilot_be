module Auth
  # One access and refresh token pair for the web client named by OAUTH_CLIENT_ID (ADR-0003, ADR-0006). Without that
  # client nothing is issued, so legacy-token callers keep working while the variable is unset (ADR-0008); a uid that
  # names no application is a misconfiguration and is reported.
  class IssueTokens < ApplicationService
    def initialize(user)
      @user = user
    end

    def call
      uid = ENV['OAUTH_CLIENT_ID'].to_s.strip
      return if uid.empty?

      application = Doorkeeper::Application.by_uid(uid)
      unless application
        Sentry.capture_message("No token pair issued: no OAuth application has OAUTH_CLIENT_ID's uid", level: :warning)
        return
      end

      OauthAccessToken.create_for(application:, resource_owner: @user, scopes: Doorkeeper.config.default_scopes,
                                  expires_in: Doorkeeper.config.access_token_expires_in.to_i, use_refresh_token: true)
    end
  end
end
