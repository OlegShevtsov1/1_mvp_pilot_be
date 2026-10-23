# Google sign-in (ADR-0004): verifies the Google ID token, then signs in the user linked to that Google account,
# links Google to the user with the same email, or creates a user. Any refusal creates and links nothing (AC-07).
module Auth
  class GoogleSignIn < ApplicationService
    attr_reader :user, :error

    def initialize(id_token)
      @id_token = id_token
    end

    def call
      @verification = GoogleIdTokenVerifier.call(@id_token)
      return refuse(@verification.error) unless @verification.success?

      ActiveRecord::Base.transaction { @user = linked_user || link_or_create }
      @user ? self : refuse(:already_linked)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      # The database message names the email it collided on.
      Sentry.capture_message("Google sign-in not saved: #{e.class}")
      @user = nil
      refuse(:not_saved)
    end

    def success?
      error.nil?
    end

    private

    def linked_user
      Identity.find_by(provider: Identity::GOOGLE, uid: @verification.uid)&.user
    end

    # Devise's lookup ignores capital letters, so a Google email never makes a second account (AC-06).
    def link_or_create
      user = User.find_for_database_authentication(email: @verification.email)
      return create_user unless user
      return if user.identities.exists?(provider: Identity::GOOGLE)

      LinkIdentity.call(user, @verification.uid)
    end

    def create_user
      user = User.new(email: @verification.email)
      user.identities.build(provider: Identity::GOOGLE, uid: @verification.uid)
      user.save!
      user
    end

    def refuse(error)
      @error = error
      self
    end
  end
end
