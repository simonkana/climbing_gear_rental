class Equipment < ApplicationRecord
  include HasPublicId

  has_many :reservations, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }
  validates :capacity, numericality: { only_integer: true, in: 1..100 }
  validates :turnaround_minutes, numericality: { only_integer: true, in: 0..1440 }
end
