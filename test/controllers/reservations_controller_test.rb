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

  # new and create

  def booking_params(**overrides)
    { reservation: {
      customer_name: "Tommy Caldwell",
      customer_email: "tommy@example.com",
      customer_phone: "",
      start_date: "2026-12-05T10:00",
      end_date: "2026-12-05T12:00"
    }.merge(overrides) }
  end

  test "equipment page has a book button" do
    crashpad = equipment(:crashpad)

    get equipment_path(crashpad)

    assert_select "a[href='#{new_equipment_reservation_path(crashpad)}']", text: "Book"
  end

  test "new renders the booking form for the equipment" do
    crashpad = equipment(:crashpad)

    get new_equipment_reservation_path(crashpad)

    assert_response :success
    assert_select "h1", text: /Crashpad/
    assert_select "form[action='#{equipment_reservations_path(crashpad)}']" do
      assert_select "input[type='datetime-local'][step='900']#reservation_start_date"
      assert_select "input[type='datetime-local'][step='900']#reservation_end_date"
      %w[customer_name customer_email customer_phone start_date end_date].each do |field|
        assert_select "label[for='reservation_#{field}']"
      end
    end
  end

  test "create books the reservation in Prague time and redirects to its public_id page" do
    crashpad = equipment(:crashpad)

    assert_difference -> { crashpad.reservations.count }, 1 do
      post equipment_reservations_path(crashpad), params: booking_params
    end

    reservation = crashpad.reservations.order(:id).last
    assert_redirected_to reservation_path(reservation)
    assert_equal Time.utc(2026, 12, 5, 9, 0), reservation.start_date # 10:00 Prague
    follow_redirect!
    assert_select ".flash-notice", text: "Reservation was created."
  end

  test "create rejects a booking over capacity with the capacity message" do
    crashpad = equipment(:crashpad) # capacity 1
    post equipment_reservations_path(crashpad), params: booking_params

    assert_no_difference -> { Reservation.count } do
      post equipment_reservations_path(crashpad),
        params: booking_params(customer_name: "Second", start_date: "2026-12-05T11:00", end_date: "2026-12-05T13:00")
    end

    assert_response :unprocessable_content
    assert_select ".form-errors[role='alert']", text: /all 1 units are taken/
  end

  test "create with invalid input re-renders the form with accessible errors" do
    assert_no_difference -> { Reservation.count } do
      post equipment_reservations_path(equipment(:crashpad)), params: booking_params(customer_email: "nope")
    end

    assert_response :unprocessable_content
    assert_select "#reservation_customer_email[aria-invalid='true']"
    assert_select "a[href='#reservation_customer_email']"
  end

  test "create ignores status, equipment and public_id from params" do
    crashpad = equipment(:crashpad)
    chosen = SecureRandom.uuid_v7

    post equipment_reservations_path(crashpad),
      params: booking_params(status: "cancelled", equipment_id: equipment(:rope).id, public_id: chosen)

    reservation = Reservation.order(:id).last
    assert reservation.active?
    assert_equal crashpad, reservation.equipment
    assert_not_equal chosen, reservation.public_id
  end

  test "booking unknown equipment returns not found" do
    get new_equipment_reservation_path(equipment_id: SecureRandom.uuid_v7)

    assert_response :not_found
  end

  test "equipment page links its reservations" do
    get equipment_path(equipment(:rope))

    assert_select "##{row_id(:upcoming)} a[href='#{reservation_path(reservations(:upcoming))}']"
  end
end
