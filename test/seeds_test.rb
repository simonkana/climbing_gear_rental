require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  def load_seeds
    capture_io { Rails.application.load_seed }
  end

  test "seeds the equipment catalogue" do
    load_seeds

    expected = {
      "Rope 60 m" => 3, "Harness M" => 4, "GriGri" => 2, "Climbing shoes EU 42" => 2,
      "Quickdraw set 12 pcs" => 3, "Helmet" => 5, "Crashpad" => 1
    }
    assert_equal expected, Equipment.order(:id).pluck(:name, :capacity).to_h
    assert_equal 120, Equipment.find_by!(name: "Rope 60 m").turnaround_minutes
  end

  test "seeds can be loaded repeatedly" do
    load_seeds
    load_seeds

    assert_equal 7, Equipment.count
  end

  # Each scenario printed in the seed guide is checked through the booking service.

  # Seeds run at 1 Dec 08:00 (setup); scenarios are one week ahead.
  def scenario_at(hour, min = 0)
    Time.zone.local(2026, 12, 8, hour, min)
  end

  def try_booking(equipment_name, from, to)
    reservation = Reservation.new(
      equipment: Equipment.find_by!(name: equipment_name),
      customer_name: "Seed check", customer_email: "check@example.com",
      start_date: from, end_date: to
    )
    ReservationBooking.new(reservation).call
  end

  test "S1: crashpad is blocked during turnaround and free right after it" do
    load_seeds

    assert_not try_booking("Crashpad", scenario_at(18, 30), scenario_at(20))
    assert try_booking("Crashpad", scenario_at(19), scenario_at(20))
  end

  test "S2: GriGri is full where both bookings overlap" do
    load_seeds

    assert_not try_booking("GriGri", scenario_at(15), scenario_at(16))
    assert try_booking("GriGri", scenario_at(10), scenario_at(12))
  end

  test "S3: rope is nearly full and only fits around the full hour" do
    load_seeds

    assert_not try_booking("Rope 60 m", scenario_at(12), scenario_at(15))
    assert try_booking("Rope 60 m", scenario_at(9), scenario_at(11))
  end

  test "S4: shoes accept a booking a naive overlap count would reject" do
    load_seeds

    assert try_booking("Climbing shoes EU 42", scenario_at(9), scenario_at(13))
  end

  test "S5: a cancelled harness booking does not take a unit" do
    load_seeds
    harness = Equipment.find_by!(name: "Harness M")
    assert_equal 1, harness.reservations.cancelled.count

    assert try_booking("Harness M", scenario_at(10), scenario_at(14))
    assert_not try_booking("Harness M", scenario_at(10), scenario_at(14))
  end

  test "S6: helmet has finished reservations that are not editable" do
    load_seeds
    reservations = Equipment.find_by!(name: "Helmet").reservations

    assert_equal 2, reservations.count
    assert reservations.all? { it.finished? && !it.editable? }
  end

  test "scenarios stay bookable for a week after seeding" do
    load_seeds
    first_scenario_start = Reservation.active.where(Reservation.arel_table[:end_date].gt(Time.current)).minimum(:start_date)

    assert_operator first_scenario_start, :>=, Time.zone.local(2026, 12, 8)
  end

  test "every equipment item has at least one reservation" do
    load_seeds

    assert Equipment.all.all? { it.reservations.any? }
  end
end
