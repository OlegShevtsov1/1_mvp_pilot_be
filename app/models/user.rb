class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  acts_as_token_authenticatable

  has_many :projects, dependent: :destroy
  has_many :access_tokens, class_name: 'OauthAccessToken', foreign_key: :resource_owner_id,
                           dependent: :delete_all
  has_many :identities, dependent: :destroy
  has_many :legacy_token_uses, dependent: :delete_all

  protected

  # A user with a linked Google identity may have no password; linking clears it (ADR-0004).
  def password_required?
    super && identities.empty?
  end
end
