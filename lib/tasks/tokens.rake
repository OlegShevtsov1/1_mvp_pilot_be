namespace :tokens do
  # No rescue: the Sentry rake integration reports a failure to GlitchTip and the run exits non-zero.
  desc 'Delete token rows revoked or expired longer ago than the refresh token idle limit and legacy-use rows older ' \
       'than 60 days'
  task purge: :environment do
    tokens = OauthAccessToken.revoked_or_expired_before(OauthAccessToken::REFRESH_TOKEN_IDLE_LIMIT.ago).delete_all
    uses = LegacyTokenUse.where(used_on: ...(Date.current - 60)).delete_all
    puts "tokens:purge deleted oauth_access_tokens=#{tokens} legacy_token_uses=#{uses}"
  end
end
