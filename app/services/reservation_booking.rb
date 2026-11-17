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
      equipment = lock_equipment

      if over_capacity?(equipment)
        add_capacity_error(equipment)
        false
      else
        after_capacity_check
        reservation.save!
      end
    end
  rescue ActiveRecord::RecordInvalid
    false
  rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
    # Should not happen (one lock per booking, no lock-ordering cycles), but a
    # long-running lock holder can still time us out. Report, do not retry.
    reservation.errors.add(:base, :busy)
    false
  end

  private
    # SELECT ... FOR UPDATE on the equipment primary key: an exclusive record
    # lock (no gap lock) that serializes all bookings of this equipment.
    #
    # InnoDB (REPEATABLE READ) takes the read snapshot at the first plain,
    # non-locking read. Locking first means the snapshot for the overlap query
    # is taken only after the lock is granted, i.e. after any competing booking
    # of this equipment has committed. A plain read before the lock would let
    # two bookings check against the same stale data.
    def lock_equipment
      Equipment.lock.find(reservation.equipment_id)
    end

    def over_capacity?(equipment)
      turnaround = equipment.turnaround_minutes.minutes
      window = reservation.start_date...(reservation.end_date + turnaround)

      # Plain (non-locking) read on purpose: the equipment lock already
      # serializes writers, a locking range read would only add gap locks.
      # Blocked intervals intersect: existing.start < window.end and
      # existing.end + turnaround > window.start (touching rows are dropped
      # by the timeline). On update the reservation itself is excluded (D6);
      # on create its id is nil, which excludes nothing.
      existing = equipment.reservations.active
        .where.not(id: reservation.id)
        .where(start_date: ...window.end)
        .where(end_date: (window.begin - turnaround)..)
        .pluck(:start_date, :end_date)
        .map { |start_date, end_date| start_date...(end_date + turnaround) }

      CapacityTimeline.peak(window: window, intervals: existing + [ window ]) > equipment.capacity
    end

    # Test seam (plan §9.4): the concurrency test slows this down to widen the
    # window between check and write. Intentionally a no-op.
    def after_capacity_check
    end

    def add_capacity_error(equipment)
      reservation.errors.add(:base, :over_capacity,
        capacity: equipment.capacity,
        start: I18n.l(reservation.start_date),
        end: I18n.l(reservation.end_date),
        turnaround: equipment.turnaround_minutes)
    end
end
