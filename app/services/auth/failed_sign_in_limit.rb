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

    def initialize(request)
      @key = "failed-sign-in:#{self.class.source_of(request)}"
    end

    def attempt_refused?
      count(1) > LIMIT
    end

    # An increment on a key whose window ended starts a new window at that amount, so a give-back landing after the
    # window ended is undone instead of opening the next window below zero.
    def give_back
      count(1) if count(-1).negative?
    end

    private

    def count(amount)
      ErrorsController::RateLimitStore.increment(@key, amount, expires_in: WINDOW).to_i
    end
  end
end
