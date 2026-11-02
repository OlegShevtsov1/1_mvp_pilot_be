module Auth
  # Failed password sign-ins are counted per source, shared by /oauth/token and /api/v1/sign_in, and the source is
  # refused before its password is checked once it reached LIMIT failures in the window (AC-10, ADR-0009). Each attempt
  # is counted before its check, so attempts in flight together cannot all pass, and given back unless it failed.
  # The forwarded client address is believed only from a trusted proxy (SAD §7): Rails' remote_ip alone would take
  # X-Forwarded-For from any caller.
  class FailedSignInLimit
    LIMIT = 10
    WINDOW = 1.minute
    MESSAGE = 'Too many failed sign-ins from this address. Wait a minute before trying again'

    def self.source_of(request)
      proxies = Rails.application.config.action_dispatch.trusted_proxies.presence ||
                ActionDispatch::RemoteIp::TRUSTED_PROXIES
      proxies.any? { |proxy| proxy === request.remote_addr } ? request.remote_ip : request.remote_addr
    end

    # Windows are clock minutes and each has its own key, so the key names the window an attempt was counted in:
    # both stores agree on it whatever each one remembers, and a give-back reaches only that window.
    def initialize(request)
      @key = "failed-sign-in:#{self.class.source_of(request)}:#{Time.current.to_i / WINDOW.to_i}"
    end

    def attempt_refused?
      count(1) > LIMIT
    end

    # Gives the attempt back to the window it was counted in. A window whose count was lost (a cleared or failed
    # store) is not left below zero.
    def give_back
      count(1) if count(-1).negative?
    end

    private

    def count(amount)
      ErrorsController::RateLimitStore.increment(@key, amount, expires_in: WINDOW).to_i
    end
  end
end
