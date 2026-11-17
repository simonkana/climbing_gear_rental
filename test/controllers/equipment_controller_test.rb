require "test_helper"

class EquipmentControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  test "root page shows the equipment index inside the base layout" do
    get root_path

    assert_response :success
    assert_select "a.skip-link[href='#main']"
    assert_select "header a[href='#{root_path}']", text: "Climbing Gear Rental"
    assert_select "nav[aria-label='Main'] a[href='#{equipment_index_path}']", text: "Equipment"
    assert_select "main#main h1", text: "Equipment"
    assert_select ".flash", count: 0
  end

  test "index lists equipment with capacity and units free now" do
    get equipment_index_path

    assert_response :success
    assert_select "tr#equipment_#{equipment(:rope).public_id}" do
      assert_select "a[href='#{equipment_path(equipment(:rope))}']", text: "Rope 60 m"
      assert_select "td.capacity", text: "3"
      assert_select "td.free-now", text: "2" # one reservation in progress
    end
    assert_select "tr#equipment_#{equipment(:crashpad).public_id} td.free-now", text: "1"
  end

  test "show is addressed by public_id and splits upcoming from past and cancelled reservations" do
    rope = equipment(:rope)

    get equipment_path(rope)

    assert_response :success
    assert_equal "/equipment/#{rope.public_id}", path
    assert_select "h1", text: "Rope 60 m"
    assert_select "#upcoming-reservations" do
      assert_select "tr#reservation_#{reservations(:upcoming).public_id}" do
        assert_select "td", text: "2. 12. 2026 10:00"
        assert_select "td", text: "2. 12. 2026 16:00" # blocked until: 14:00 + 120 min turnaround
      end
      assert_select "tr#reservation_#{reservations(:in_progress).public_id}"
      assert_select "tr#reservation_#{reservations(:finished).public_id}", count: 0
    end
    assert_select "#past-reservations" do
      assert_select "tr#reservation_#{reservations(:finished).public_id}"
      assert_select "tr#reservation_#{reservations(:cancelled).public_id}", text: /Cancelled/
    end
  end

  test "show without reservations says so" do
    get equipment_path(equipment(:crashpad))

    assert_response :success
    assert_select "#upcoming-reservations", text: /No upcoming reservations/
  end

  test "unknown public_id returns not found" do
    get equipment_path(id: SecureRandom.uuid_v7)

    assert_response :not_found
  end

  test "numeric id does not resolve" do
    get equipment_path(id: equipment(:rope).id)

    assert_response :not_found
  end
end
