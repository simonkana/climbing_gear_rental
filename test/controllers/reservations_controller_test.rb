require "test_helper"

class ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  def row_id(name)
    "reservation_#{reservations(name).public_id}"
  end

  # index and show

  test "nav links to the reservations index" do
    get root_path

    assert_select "nav[aria-label='Main'] a[href='#{reservations_path}']", text: "Reservations"
  end

  test "index lists upcoming reservations first and past and cancelled ones separately" do
    get reservations_path

    assert_response :success
    assert_select "#upcoming-reservations tbody tr" do |rows|
      assert_equal [ row_id(:in_progress), row_id(:upcoming) ], rows.map { it["id"] }
    end
    assert_select "##{row_id(:in_progress)}", text: /In progress/
    assert_select "##{row_id(:upcoming)} a[href='#{reservation_path(reservations(:upcoming))}']"
    assert_select "##{row_id(:upcoming)}", text: /Rope 60 m/
    assert_select "#past-reservations" do
      assert_select "##{row_id(:finished)}", text: /Finished/
      assert_select "##{row_id(:cancelled)}", text: /Cancelled/
    end
  end

  test "show is addressed by public_id and explains the blocked time" do
    reservation = reservations(:upcoming)

    get reservation_path(reservation)

    assert_response :success
    assert_equal "/reservations/#{reservation.public_id}", path
    assert_select "dd", text: "Alex Honnold"
    assert_select "dd", text: "alex@example.com"
    assert_select "dd a[href='#{equipment_path(equipment(:rope))}']", text: "Rope 60 m"
    assert_select "dd", text: "2. 12. 2026 10:00"
    assert_select "dd", text: /2\. 12\. 2026 16:00/ # blocked until: 14:00 + 120 min
  end

  test "unknown public_id returns not found" do
    get reservation_path(id: SecureRandom.uuid_v7)

    assert_response :not_found
  end

  test "numeric id does not resolve" do
    get reservation_path(id: reservations(:upcoming).id)

    assert_response :not_found
  end

  test "equipment page links its reservations" do
    get equipment_path(equipment(:rope))

    assert_select "##{row_id(:upcoming)} a[href='#{reservation_path(reservations(:upcoming))}']"
  end
end
