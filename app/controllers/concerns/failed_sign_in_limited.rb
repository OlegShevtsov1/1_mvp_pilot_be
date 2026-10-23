# The failed sign-in limit both sign-in doors share (AC-10, ADR-0009). Each attempt is counted before its credentials
# are checked and given back unless the door calls failed_sign_in!, so neither a success nor a server error counts.
module FailedSignInLimited
  extend ActiveSupport::Concern

  private

  def limit_failed_sign_ins
    limit = Auth::FailedSignInLimit.new(request)
    return refuse_failed_sign_in if limit.attempt_refused?

    begin
      yield
    ensure
      limit.give_back unless @failed_sign_in
    end
  end

  def failed_sign_in!
    @failed_sign_in = true
  end

  def refuse_failed_sign_in
    response.set_header('Retry-After', Auth::FailedSignInLimit::WINDOW.to_i.to_s)
    render json: { errors: [ Auth::FailedSignInLimit::MESSAGE ] }, status: :too_many_requests
  end
end
