module Auth
  # The legacy X-User-Email / X-User-Token pair stays accepted until the evidence cutoff (ADR-0005); each use is
  # counted per user and day so the cutoff can be decided on data. LEGACY_AUTH_ENABLED=false switches the path off.
  # A failed count is reported, never allowed to refuse the already-authenticated request.
  module LegacyUsage
    module_function

    def enabled?
      ActiveModel::Type::Boolean.new.cast(ENV['LEGACY_AUTH_ENABLED'].presence || 'true')
    end

    def record(user)
      LegacyTokenUse.upsert_all(
        [ { user_id: user.id, used_on: Date.current, uses_count: 1 } ],
        unique_by: %i[user_id used_on],
        on_duplicate: Arel.sql('uses_count = legacy_token_uses.uses_count + 1, updated_at = CURRENT_TIMESTAMP')
      )
    rescue ActiveRecord::ActiveRecordError => e
      Sentry.capture_exception(e)
    end
  end
end
