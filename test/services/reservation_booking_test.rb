require "test_helper"

class ReservationBookingTest < ActiveSupport::TestCase
  NOW = Time.zone.local(2026, 12, 1, 8, 0)

  setup { travel_to NOW }

  def create_equipment(capacity:, turnaround_minutes: 60)
    Equipment.create!(name: "Test gear", capacity: capacity, turnaround_minutes: turnaround_minutes)
  end

  def build(equipment, start_date, end_date)
    Reservation.new(
      equipment: equipment,
      customer_name: "Tommy Caldwell",
      customer_email: "tommy@example.com",
      start_date: start_date,
      end_date: end_date
    )
  end

  # Builds a reservation and books it through the service; returns [result, reservation].
  def book(equipment, start_date, end_date)
    reservation = build(equipment, start_date, end_date)
    [ ReservationBooking.new(reservation).call, reservation ]
  end

  def book!(equipment, start_date, end_date)
    result, reservation = book(equipment, start_date, end_date)
    assert result, "setup booking failed: #{reservation.errors.full_messages}"
    reservation
  end

  def at(hour, minute = 0, day: 5)
    Time.zone.local(2026, 12, day, hour, minute)
  end

  def assert_over_capacity(result, reservation)
    assert_not result
    assert_not reservation.persisted?
    assert reservation.errors.of_kind?(:base, :over_capacity), reservation.errors.full_messages.inspect
  end

  test "books a reservation when a unit is free" do
    result, reservation = book(create_equipment(capacity: 1), at(10), at(12))

    assert result
    assert reservation.persisted?
  end

  test "rejects invalid input without taking the lock" do
    reservation = build(create_equipment(capacity: 1), at(12), at(10))

    assert_no_queries_match(/FOR UPDATE/) do
      assert_not ReservationBooking.new(reservation).call
    end
    assert_not reservation.persisted?
    assert_not reservation.errors.of_kind?(:base, :over_capacity)
  end

  test "locks the equipment row as the first statement of the transaction" do
    reservation = build(create_equipment(capacity: 1), at(10), at(12))
    statements = []
    collect = ->(*, payload) { statements << payload[:sql] }

    ActiveSupport::Notifications.subscribed(collect, "sql.active_record") do
      assert ReservationBooking.new(reservation).call
    end

    transaction_start = statements.index { |sql| sql.match?(/\A(BEGIN|SAVEPOINT)\b/) }
    assert transaction_start, "no transaction was opened: #{statements.inspect}"
    assert_match(/\ASELECT .*FROM `equipment` WHERE .*FOR UPDATE\z/m, statements[transaction_start + 1])
  end

  test "accepts a booking while one unit is still free" do
    gear = create_equipment(capacity: 2)
    book!(gear, at(10), at(14))

    result, = book(gear, at(11), at(13))

    assert result
  end

  test "rejects a booking when all units are taken" do
    gear = create_equipment(capacity: 2)
    book!(gear, at(10), at(14))
    book!(gear, at(11), at(15))

    assert_no_difference -> { Reservation.count } do
      result, reservation = book(gear, at(12), at(13))
      assert_over_capacity(result, reservation)
    end
  end

  test "capacity error names the capacity and the window" do
    gear = create_equipment(capacity: 1, turnaround_minutes: 30)
    book!(gear, at(10), at(14))

    _, reservation = book(gear, at(12), at(13))

    message = reservation.errors.full_messages.first
    assert_includes message, "all 1 units"
    assert_includes message, "5. 12. 2026 12:00"
    assert_includes message, "5. 12. 2026 13:00"
    assert_includes message, "30 min"
  end

  test "turnaround keeps the unit blocked after the reservation ends" do
    crashpad = equipment(:crashpad) # capacity 1, turnaround 60 min
    book!(crashpad, at(10), at(18))

    result, reservation = book(crashpad, at(18, 45), at(20))
    assert_over_capacity(result, reservation)

    result, = book(crashpad, at(19), at(20))
    assert result
  end

  test "counts the real peak, not every overlapping reservation" do
    # Plan §4.2: A 08-10 and B 12-14 never overlap each other, so 09-13 fits.
    gear = create_equipment(capacity: 2, turnaround_minutes: 0)
    book!(gear, at(8), at(10))
    book!(gear, at(12), at(14))

    result, = book(gear, at(9), at(13))

    assert result
  end

  test "cancelled reservations do not block" do
    gear = create_equipment(capacity: 1)
    book!(gear, at(10), at(14)).update!(status: :cancelled)

    result, = book(gear, at(10), at(14))

    assert result
  end

  test "reservations of other equipment do not block" do
    book!(create_equipment(capacity: 1), at(10), at(14))

    result, = book(create_equipment(capacity: 1), at(10), at(14))

    assert result
  end

  test "turnaround across the DST change uses absolute time" do
    travel_to Time.utc(2026, 10, 20, 8, 0)
    gear = create_equipment(capacity: 1, turnaround_minutes: 60)
    # Ends 02:00 CEST = 00:00 UTC; blocked until 01:00 UTC = 02:00 CET (clocks went back at 01:00 UTC).
    book!(gear, Time.utc(2026, 10, 24, 22, 0), Time.utc(2026, 10, 25, 0, 0))

    result, reservation = book(gear, Time.utc(2026, 10, 25, 0, 45), Time.utc(2026, 10, 25, 3, 0))
    assert_over_capacity(result, reservation)

    result, = book(gear, Time.utc(2026, 10, 25, 1, 0), Time.utc(2026, 10, 25, 3, 0))
    assert result
  end
end
