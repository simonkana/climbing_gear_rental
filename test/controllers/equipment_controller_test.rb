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

  test "index links to the new equipment form" do
    get equipment_index_path

    assert_select "a[href='#{new_equipment_path}']", text: "Add equipment"
  end

  test "new renders a labelled form" do
    get new_equipment_path

    assert_response :success
    assert_select "form[action='#{equipment_index_path}']" do
      %w[name description capacity turnaround_minutes].each do |field|
        assert_select "label[for='equipment_#{field}']"
        assert_select "#equipment_#{field}"
      end
    end
  end

  test "create saves equipment and redirects to its public_id page" do
    assert_difference -> { Equipment.count }, 1 do
      post equipment_index_path, params: { equipment: {
        name: "Helmet", description: "Size M/L", capacity: 5, turnaround_minutes: 30
      } }
    end

    created = Equipment.order(:id).last
    assert_redirected_to equipment_path(created)
    assert_match(/\/equipment\/\h{8}-/, response.location)
    follow_redirect!
    assert_select ".flash-notice", text: "Equipment was created."
    assert_equal [ "Helmet", 5, 30 ], [ created.name, created.capacity, created.turnaround_minutes ]
  end

  test "create with invalid data re-renders the form with accessible errors" do
    assert_no_difference -> { Equipment.count } do
      post equipment_index_path, params: { equipment: { name: "", capacity: 0 } }
    end

    assert_response :unprocessable_content
    assert_select ".form-errors[role='alert']" do
      assert_select "a[href='#equipment_name']", text: /Name can't be blank/
      assert_select "a[href='#equipment_capacity']"
    end
    assert_select "#equipment_name[aria-invalid='true'][aria-describedby='equipment_name_error']"
    assert_select "#equipment_name_error", text: /can't be blank/
  end

  test "error summary shows only human messages" do
    post equipment_index_path, params: { equipment: { name: "Helmet", capacity: 5, turnaround_minutes: 2000 } }

    assert_response :unprocessable_content
    assert_select ".form-errors p", text: "Turnaround must be between 0 and 1440 minutes"
    assert_no_match(/prevented|prohibited/i, css_select(".form-errors").text)
  end

  test "create ignores a public_id sent in params" do
    chosen = SecureRandom.uuid_v7

    post equipment_index_path, params: { equipment: { name: "Helmet", capacity: 5, public_id: chosen } }

    assert_not Equipment.exists?(public_id: chosen)
    assert Equipment.exists?(name: "Helmet")
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
