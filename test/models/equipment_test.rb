require "test_helper"

class EquipmentTest < ActiveSupport::TestCase
  UUID_V7 = /\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/

  def build_equipment(**attributes)
    Equipment.new({ name: "Helmet", capacity: 5 }.merge(attributes))
  end

  test "fixtures are valid" do
    assert equipment(:rope).valid?
    assert equipment(:crashpad).valid?
  end

  # public_id

  test "generates a UUIDv7 public_id on create and uses it as param" do
    item = build_equipment
    item.save!

    assert_match UUID_V7, item.public_id
    assert_equal item.public_id, item.to_param
  end

  test "keeps an explicitly given public_id" do
    public_id = SecureRandom.uuid_v7
    item = build_equipment(public_id: public_id)
    item.save!

    assert_equal public_id, item.reload.public_id
  end

  test "public_id cannot be changed after create" do
    item = equipment(:rope)

    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      item.public_id = SecureRandom.uuid_v7
    end
  end

  test "public_id is unique at database level" do
    duplicate = build_equipment(public_id: equipment(:rope).public_id)

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  # name

  test "requires a name" do
    item = build_equipment(name: " ")

    assert_not item.valid?
    assert item.errors.added?(:name, :blank)
  end

  test "limits name to 120 characters" do
    assert build_equipment(name: "a" * 120).valid?
    assert_not build_equipment(name: "a" * 121).valid?
  end

  test "strips surrounding whitespace from the name" do
    assert_equal "Helmet", build_equipment(name: "  Helmet \n").tap(&:valid?).name
  end

  test "limits description to 2000 characters" do
    assert build_equipment(description: "a" * 2000).valid?
    assert_not build_equipment(description: "a" * 2001).valid?
  end

  test "non-numeric capacity and turnaround get friendly messages" do
    item = build_equipment(capacity: "abc", turnaround_minutes: "")
    item.valid?

    assert_equal [ "Capacity must be a whole number" ], item.errors.full_messages_for(:capacity)
    assert_equal [ "Turnaround must be a whole number of minutes" ], item.errors.full_messages_for(:turnaround_minutes)
  end

  # capacity

  test "requires a capacity" do
    item = build_equipment(capacity: nil)

    assert_not item.valid?
    assert item.errors.key?(:capacity)
  end

  test "capacity must be an integer" do
    assert_not build_equipment(capacity: 1.5).valid?
  end

  test "capacity must be between 1 and 100" do
    assert_not build_equipment(capacity: 0).valid?
    assert build_equipment(capacity: 1).valid?
    assert build_equipment(capacity: 100).valid?
    assert_not build_equipment(capacity: 101).valid?
  end

  # turnaround_minutes

  test "turnaround defaults to 60 minutes" do
    assert_equal 60, Equipment.new.turnaround_minutes
  end

  test "turnaround must be an integer between 0 and 1440 minutes" do
    assert_not build_equipment(turnaround_minutes: -1).valid?
    assert build_equipment(turnaround_minutes: 0).valid?
    assert build_equipment(turnaround_minutes: 1440).valid?
    assert_not build_equipment(turnaround_minutes: 1441).valid?
    assert_not build_equipment(turnaround_minutes: 30.5).valid?
  end

  # image_url

  test "image url is optional and blank becomes nil" do
    item = build_equipment(image_url: "   ")

    assert item.valid?
    assert_nil item.image_url
  end

  test "accepts an https image url" do
    assert build_equipment(image_url: "https://upload.wikimedia.org/rope.jpg").valid?
  end

  test "rejects image urls that are not https links" do
    [ "http://example.com/rope.jpg", "javascript:alert(1)", "data:image/png;base64,AAAA",
      "not a url", "https://", "//example.com/rope.jpg" ].each do |url|
      item = build_equipment(image_url: url)

      assert_not item.valid?, url
      assert item.errors.added?(:image_url, :not_https_url), url
    end
  end

  test "limits image url to 2048 characters" do
    assert build_equipment(image_url: "https://example.com/#{"a" * 2028}").valid?
    assert_not build_equipment(image_url: "https://example.com/#{"a" * 2029}").valid?
  end

  # units_free_at

  test "units free at a moment subtract reservations blocking that moment" do
    travel_to Time.zone.local(2026, 12, 1, 8, 0)

    assert_equal 2, equipment(:rope).units_free_at # in_progress blocks one unit
    assert_equal 1, equipment(:crashpad).units_free_at
  end

  test "a unit stays blocked during turnaround and is free exactly at its end" do
    rope = equipment(:rope) # in_progress ends 12:00 UTC, turnaround 120 min

    assert_equal 2, rope.units_free_at(Time.utc(2026, 12, 1, 13, 59))
    assert_equal 3, rope.units_free_at(Time.utc(2026, 12, 1, 14, 0))
  end

  test "cancelled reservations do not reduce free units" do
    rope = equipment(:rope) # cancelled fixture: 3 Dec 09:00-11:00 UTC

    assert_equal 3, rope.units_free_at(Time.utc(2026, 12, 3, 10, 0))
  end

  # associations

  test "equipment with reservations cannot be destroyed" do
    item = equipment(:rope)

    assert_not item.destroy
    assert item.errors.added?(:base, :"restrict_dependent_destroy.has_many", record: "reservations")
    assert Equipment.exists?(item.id)
  end

  # database constraints (bypassing validations on purpose; public_id is set
  # explicitly because save(validate: false) skips the before_validation callback)

  def build_unvalidated(**attributes)
    build_equipment(public_id: SecureRandom.uuid_v7, **attributes)
  end

  test "database rejects non-positive capacity" do
    item = build_unvalidated(capacity: 0)

    assert_raises(ActiveRecord::CheckViolation) { item.save(validate: false) }
  end

  test "database rejects negative turnaround" do
    item = build_unvalidated(turnaround_minutes: -1)

    assert_raises(ActiveRecord::CheckViolation) { item.save(validate: false) }
  end

  test "database rejects a non-https image url" do
    item = build_unvalidated(image_url: "http://example.com/rope.jpg")

    assert_raises(ActiveRecord::CheckViolation) { item.save(validate: false) }
  end

  test "database rejects missing name" do
    item = build_unvalidated(name: nil)

    assert_raises(ActiveRecord::NotNullViolation) { item.save(validate: false) }
  end
end
