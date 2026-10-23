# The google_id_token grant of POST /oauth/token (ADR-0004). Unlike Doorkeeper's password strategy, which looks up
# the resource owner while it builds the request, this one checks the client, grant flow and scopes before Google
# sign-in may create or link a user.
module Auth
  class GoogleIdTokenGrant < Doorkeeper::Request::Strategy
    delegate :client, :parameters, to: :server

    def request
      @request ||= Request.new(Doorkeeper.config, client, parameters)
    end

    class Request < Doorkeeper::OAuth::BaseRequest
      validate :client, error: Doorkeeper::Errors::InvalidClient
      validate :client_supports_grant_flow, error: Doorkeeper::Errors::UnauthorizedClient
      validate :scopes, error: Doorkeeper::Errors::InvalidScope
      validate :resource_owner, error: Doorkeeper::Errors::InvalidGrant

      attr_reader :client, :parameters, :access_token, :resource_owner

      def initialize(server, client, parameters)
        @server = server
        @client = client
        @parameters = parameters
        @original_scopes = parameters[:scope]
        @grant_type = GoogleIdTokenGrantStrategy::GRANT_TYPE
      end

      private

      def before_successful_response
        find_or_create_access_token(client, resource_owner, scopes, {}, server)
        super
      end

      def validate_client
        client.present?
      end

      def validate_client_supports_grant_flow
        Doorkeeper.config.allow_grant_flow_for_client?(grant_type, client.application)
      end

      def validate_scopes
        return true if scopes.blank?

        Doorkeeper::OAuth::Helpers::ScopeChecker.valid?(scope_str: scopes.to_s, server_scopes: server.scopes,
                                                        app_scopes: client.try(:scopes), grant_type:)
      end

      def validate_resource_owner
        @resource_owner = GoogleSignIn.call(parameters[:id_token].to_s).user
      end
    end
  end
end
