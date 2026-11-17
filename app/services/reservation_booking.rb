# Creates or updates a reservation only if the equipment's capacity is never
# exceeded (plan §4.4). Every write of a reservation's dates, equipment or
# active status goes through here (GUARDRAILS #1).
#
#   ReservationBooking.new(reservation).call # => true / false (errors on reservation)
#
# Concurrency: bookings of the same equipment are serialized by a row lock on
# the equipment (SELECT ... FOR UPDATE). Must be called outside any other
# transaction, so that the lock really is the first statement (see below).
class ReservationBooking
  attr_reader :reservation

  def initialize(reservation)
    @reservation = reservation
  end

  def call
    return false unless reservation.valid?

    Reservation.transaction do
      # The lock MUST stay the first statement of the transaction (GUARDRAILS #2).
      # InnoDB (REPEATABLE READ) takes the read snapshot at the first plain,
      # non-locking read. Locking first means the snapshot for the overlap query
      # below is taken only after the lock is granted, i.e. after any competing
      # booking of this equipment has committed. A plain read before the lock
      # would let two bookings check against the same stale data.
      equipment = Equipment.lock.find(reservation.equipment_id)

      if over_capacity?(equipment)
        add_capacity_error(equipment)
        false
      else
        reservation.save!
      end
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  private
    def over_capacity?(equipment)
      turnaround = equipment.turnaround_minutes.minutes
      window = reservation.start_date...(reservation.end_date + turnaround)

      # Plain (non-locking) read on purpose: the equipment lock already
      # serializes writers, a locking range read would only add gap locks.
      # Blocked intervals intersect: existing.start < window.end and
      # existing.end + turnaround > window.start (touching rows are dropped
      # by the timeline).
      existing = equipment.reservations.active
        .where(start_date: ...window.end)
        .where(end_date: (window.begin - turnaround)..)
        .pluck(:start_date, :end_date)
        .map { |start_date, end_date| start_date...(end_date + turnaround) }

      CapacityTimeline.peak(window: window, intervals: existing + [ window ]) > equipment.capacity
    end

    def add_capacity_error(equipment)
      reservation.errors.add(:base, :over_capacity,
        capacity: equipment.capacity,
        start: I18n.l(reservation.start_date),
        end: I18n.l(reservation.end_date),
        turnaround: equipment.turnaround_minutes)
    end
end
