class Task < ApplicationRecord
  STATUSES = %w[not_started in_progress completed].freeze

  belongs_to :project, counter_cache: true, touch: true

  enum :status, STATUSES.index_by(&:itself),
       default: :not_started, validate: { message: "must be one of: #{STATUSES.join(', ')}" }

  validates :name, presence: true
  validates :description, presence: true
  validates :status, presence: true
end
