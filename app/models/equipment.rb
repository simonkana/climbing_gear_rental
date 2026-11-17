class Equipment < ApplicationRecord
  include HasPublicId

  has_many :reservations, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }
  validates :capacity, numericality: { only_integer: true, in: 1..100 }
  validates :turnaround_minutes, numericality: { only_integer: true, in: 0..1440 }

  # Units not blocked at a single instant (display only; bookings are checked
  # in ReservationBooking). A reservation blocks [start_date, end_date + turnaround).
  def units_free_at(time = Time.current)
    in_use = reservations.active
      .where(start_date: ..time)
      .where(Reservation.arel_table[:end_date].gt(time - turnaround_minutes.minutes))
      .count

    [ capacity - in_use, 0 ].max
  end
end
