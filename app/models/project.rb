class Project < ApplicationRecord
  NAME_MIN_LENGTH = 5
  NAME_MAX_LENGTH = 20
  DESCRIPTION_MIN_LENGTH = 20
  DESCRIPTION_MAX_LENGTH = 120

  belongs_to :user, counter_cache: true, touch: true
  has_many :tasks, dependent: :restrict_with_error

  validates :name, presence: true, length: { minimum: NAME_MIN_LENGTH, maximum: NAME_MAX_LENGTH }
  validates :description, presence: true, length: { minimum: DESCRIPTION_MIN_LENGTH, maximum: DESCRIPTION_MAX_LENGTH }

  validates_with ProjectDeletionValidator, on: :destroy
end
