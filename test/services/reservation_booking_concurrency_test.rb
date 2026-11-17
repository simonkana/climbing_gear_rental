require "test_helper"

# Proves that ReservationBooking never overbooks under concurrent requests
# (plan §9.4, GUARDRAILS #7). Must stay non-transactional, multi-threaded and
# barrier-synchronized: every thread uses its own connection and commits for
# real, exactly like parallel web requests.
class ReservationBookingConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  THREADS = 8
  # Widens the race window between the capacity check and the write. With the
  # lock the threads queue up; without it they would all pass the check.
  DELAY_BEFORE_WRITE = 0.2

  setup do
    # Real clock (travel_to would stub time for all threads at once).
    @start = (Time.current + 7.days).change(hour: 10, min: 0)
    @end = @start + 2.hours
    @created_equipment = []
  end

  teardown do
    # Cleanup of this test's own committed rows (not a booking write).
    Reservation.where(equipment: @created_equipment).delete_all
    Equipment.where(id: @created_equipment).delete_all
  end

  def create_equipment(capacity:)
    Equipment.create!(name: "Race test gear", capacity: capacity).tap { @created_equipment << it }
  end

  def build(equipment, index)
    Reservation.new(
      equipment: equipment,
      customer_name: "Climber #{index}",
      customer_email: "climber#{index}@example.com",
      start_date: @start,
      end_date: @end
    )
  end

  # Starts THREADS bookings of the same window at the same moment.
  # Returns [[result, reservation], ...].
  def race(equipment)
    barrier = Concurrent::CyclicBarrier.new(THREADS)

    threads = Array.new(THREADS) do |index|
      reservation = build(equipment, index)
      booking = ReservationBooking.new(reservation)
      booking.define_singleton_method(:after_capacity_check) { sleep DELAY_BEFORE_WRITE }

      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Fail loudly instead of hanging if not all threads get a connection
          # (test pool too small, see config/database.yml).
          raise "not all #{THREADS} threads reached the barrier" unless barrier.wait(10)

          [ booking.call, reservation ]
        end
      end
    end

    threads.map(&:value)
  end

  def assert_race_outcome(outcomes, equipment, expected_successes:)
    successes = outcomes.count { |result, _| result }
    failures = outcomes.reject { |result, _| result }.map(&:last)

    assert_equal expected_successes, successes, "successful concurrent bookings"
    failures.each do |reservation|
      assert reservation.errors.of_kind?(:base, :over_capacity), reservation.errors.full_messages.inspect
    end
    assert_equal equipment.capacity, Reservation.active.where(equipment: equipment).count,
      "active reservations in the database must never exceed capacity"
  end

  test "only one of many simultaneous bookings gets the last unit" do
    gear = create_equipment(capacity: 1)

    outcomes = race(gear)

    assert_race_outcome(outcomes, gear, expected_successes: 1)
  end

  test "simultaneous bookings fill exactly the remaining capacity" do
    gear = create_equipment(capacity: 3)
    2.times { |index| assert ReservationBooking.new(build(gear, 100 + index)).call }

    outcomes = race(gear)

    assert_race_outcome(outcomes, gear, expected_successes: 1)
  end
end
