class LegacyTokenUse < ApplicationRecord
  belongs_to :user

  validates :used_on, presence: true, uniqueness: { scope: :user_id }
  validates :uses_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
