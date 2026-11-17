require "test_helper"

class ReservationTest < ActiveSupport::TestCase
  NOW = Time.zone.local(2026, 12, 1, 8, 0)
  UUID_V7 = /\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/

  setup { travel_to NOW }

  def build_reservation(**attributes)
    Reservation.new({
      equipment: equipment(:crashpad),
      customer_name: "Tommy Caldwell",
      customer_email: "tommy@example.com",
      start_date: Time.zone.local(2026, 12, 5, 10, 0),
      end_date: Time.zone.local(2026, 12, 5, 12, 0)
    }.merge(attributes))
  end

  test "fixtures are valid" do
    %i[upcoming in_progress finished cancelled].each do |name|
      assert reservations(name).valid?, "#{name}: #{reservations(name).errors.full_messages}"
    end
  end

  test "generates a UUIDv7 public_id on create" do
    reservation = build_reservation
    reservation.save!

    assert_match UUID_V7, reservation.public_id
    assert_equal reservation.public_id, reservation.to_param
  end

  # customer fields

  test "requires equipment" do
    assert_not build_reservation(equipment: nil).valid?
  end

  test "requires customer name of at most 100 characters" do
    assert_not build_reservation(customer_name: " ").valid?
    assert build_reservation(customer_name: "a" * 100).valid?
    assert_not build_reservation(customer_name: "a" * 101).valid?
  end

  test "requires a well-formed customer email of at most 255 characters" do
    assert_not build_reservation(customer_email: "").valid?
    assert_not build_reservation(customer_email: "not-an-email").valid?
    assert_not build_reservation(customer_email: "#{"a" * 244}@example.com").valid?
  end

  test "customer phone is optional and at most 30 characters" do
    assert build_reservation(customer_phone: nil).valid?
    assert build_reservation(customer_phone: "1" * 30).valid?
    assert_not build_reservation(customer_phone: "1" * 31).valid?
  end

  # status

  test "status defaults to active" do
    assert build_reservation.active?
  end

  test "unknown status is a validation error" do
    reservation = build_reservation(status: "lost")

    assert_not reservation.valid?
    assert reservation.errors.key?(:status)
  end

  # time window

  test "requires start and end" do
    reservation = build_reservation(start_date: nil, end_date: nil)

    assert_not reservation.valid?
    assert_equal [ "can't be blank" ], reservation.errors[:start_date]
    assert_equal [ "can't be blank" ], reservation.errors[:end_date]
  end

  test "end must be after start" do
    start = Time.zone.local(2026, 12, 5, 10, 0)
    reservation = build_reservation(start_date: start, end_date: start)

    assert_not reservation.valid?
    assert reservation.errors.added?(:end_date, :not_after_start)
  end

  test "duration must be at least one hour" do
    start = Time.zone.local(2026, 12, 5, 10, 0)

    assert build_reservation(start_date: start, end_date: start + 1.hour).valid?

    too_short = build_reservation(start_date: start, end_date: start + 45.minutes)
    assert_not too_short.valid?
    assert too_short.errors.added?(:end_date, :duration_too_short)
  end

  test "duration must be at most 30 days" do
    start = Time.zone.local(2026, 12, 5, 10, 0)

    assert build_reservation(start_date: start, end_date: start + 30.days).valid?

    too_long = build_reservation(start_date: start, end_date: start + 30.days + 15.minutes)
    assert_not too_long.valid?
    assert too_long.errors.added?(:end_date, :duration_too_long)
  end

  test "times must be on a 15-minute boundary" do
    assert build_reservation(start_date: Time.zone.local(2026, 12, 5, 10, 15)).valid?

    off_minute = build_reservation(start_date: Time.zone.local(2026, 12, 5, 10, 7))
    assert_not off_minute.valid?
    assert off_minute.errors.added?(:start_date, :not_on_time_step)

    off_second = build_reservation(end_date: Time.zone.local(2026, 12, 5, 12, 0, 30))
    assert_not off_second.valid?
    assert off_second.errors.added?(:end_date, :not_on_time_step)
  end

  test "start must be in the future on create" do
    past = build_reservation(start_date: NOW - 1.hour, end_date: NOW + 1.hour)
    assert_not past.valid?
    assert past.errors.added?(:start_date, :not_in_future)

    assert_not build_reservation(start_date: NOW, end_date: NOW + 2.hours).valid?
  end

  test "unchanged past start does not block an update" do
    reservation = reservations(:in_progress)
    reservation.end_date += 1.hour

    assert reservation.valid?
  end

  test "duration across the DST change is measured in absolute time" do
    travel_to Time.zone.local(2026, 10, 1, 8, 0)
    # 25 Oct 2026: clocks go back at 03:00 CEST to 02:00 CET, so 01:00-03:00 local is 3 real hours.
    start = Time.zone.local(2026, 10, 25, 1, 0)
    finish = Time.zone.local(2026, 10, 25, 3, 0)

    assert_equal 3.hours.to_i, (finish - start).to_i
    assert build_reservation(start_date: start, end_date: finish).valid?
  end

  # database constraints (bypassing validations on purpose)

  def build_unvalidated(**attributes)
    build_reservation(public_id: SecureRandom.uuid_v7, **attributes)
  end

  test "database rejects end not after start" do
    start = Time.zone.local(2026, 12, 5, 10, 0)
    reservation = build_unvalidated(start_date: start, end_date: start)

    assert_raises(ActiveRecord::CheckViolation) { reservation.save(validate: false) }
  end

  test "database rejects unknown status" do
    reservation = build_unvalidated
    reservation.write_attribute(:status, "lost")

    assert_raises(ActiveRecord::CheckViolation) { reservation.save(validate: false) }
  end

  test "database rejects unknown equipment" do
    reservation = build_unvalidated(equipment: nil)
    reservation.equipment_id = 0

    assert_raises(ActiveRecord::InvalidForeignKey) { reservation.save(validate: false) }
  end
end
