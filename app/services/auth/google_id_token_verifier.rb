require 'net/http'

# Proves that Google issued an ID token for this app and vouches for the email in it (ADR-0004), before
# Google sign-in creates or links a user; any doubt is a refusal (AC-07). Google's signing keys are kept in
# process memory, and Google is asked at most once per REFETCH_COOLDOWN, whether the last call worked or not,
# so tokens with made-up key ids or an outage at Google cannot make every request call Google.
module Auth
  class GoogleIdTokenVerifier < ApplicationService
    CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs'
    ISSUERS = [ 'https://accounts.google.com', 'accounts.google.com' ].freeze
    KEYS_TTL = 1.hour
    REFETCH_COOLDOWN = 60.seconds

    class KeySet
      class Unavailable < StandardError; end

      def initialize
        @mutex = Mutex.new
        @keys = nil
        @fetched_at = nil
        @attempted_at = nil
      end

      def call(options)
        @mutex.synchronize do
          refresh if expired? || options[:kid_not_found]
          @keys
        end
      end

      private

      def expired?
        @keys.nil? || @fetched_at < KEYS_TTL.ago
      end

      def cooling_down?
        @attempted_at.present? && @attempted_at > REFETCH_COOLDOWN.ago
      end

      def last_fetch_failed?
        @fetched_at != @attempted_at
      end

      # During the cooldown an unknown key id is a bad token only if the last fetch worked; after a failed one
      # nothing proves the key id is not Google's.
      def refresh
        return fetch! unless cooling_down?

        raise Unavailable, 'Google certs not retried yet' if last_fetch_failed?
      end

      # Anything that goes wrong reaching or reading Google's keys is an outage, never an unhandled error.
      def fetch!
        attempt = @attempted_at = Time.current
        @keys = parse(download)
        @fetched_at = attempt
      rescue Unavailable
        raise
      rescue StandardError => e
        raise Unavailable, "Google certs unusable: #{e.class}"
      end

      def download
        uri = URI(CERTS_URL)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 5) do |http|
          http.get(uri.request_uri)
        end
        raise Unavailable, "Google certs answered #{response.code}" unless response.code == '200'

        response.body
      end

      def parse(body)
        json = JSON.parse(body)
        unless json.is_a?(Hash) && json['keys'].is_a?(Array) && json['keys'].all?(Hash)
          raise Unavailable, 'Google certs have no keys'
        end

        keys = JWT::JWK::Set.new(json)
        raise Unavailable, 'Google certs have no usable keys' if keys.none?

        keys.each(&:verify_key)
        keys
      end
    end

    DEFAULT_KEYS = KeySet.new

    attr_reader :email, :uid, :error

    def initialize(id_token, client_id: ENV['GOOGLE_CLIENT_ID'], keys: DEFAULT_KEYS)
      @id_token = id_token
      @client_id = client_id
      @keys = keys
    end

    def call
      return refuse(:not_configured) if @client_id.blank?

      payload = decode
      return refuse(:email_not_verified) unless verified_email?(payload)

      @email = payload['email']
      @uid = payload['sub']
      self
    rescue JWT::DecodeError
      refuse(:invalid_token)
    rescue KeySet::Unavailable => e
      Sentry.capture_exception(e)
      refuse(:keys_unavailable)
    end

    def success?
      error.nil?
    end

    private

    def decode
      JWT.decode(@id_token, nil, true,
                 algorithms: [ 'RS256' ], jwks: @keys,
                 aud: @client_id, verify_aud: true,
                 iss: ISSUERS, verify_iss: true,
                 required_claims: %w[iss aud exp sub]).first
    end

    # Older Google tokens carry email_verified as the string 'true'.
    def verified_email?(payload)
      [ true, 'true' ].include?(payload['email_verified']) && payload['email'].present?
    end

    def refuse(error)
      @error = error
      self
    end
  end
end
