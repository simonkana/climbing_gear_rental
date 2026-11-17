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

  test "a single error is shown as a plain human message without a count" do
    post equipment_reservations_path(equipment(:crashpad)), params: booking_params(customer_email: "nope")

    assert_select ".form-errors" do
      assert_select "p a[href='#reservation_customer_email']", text: "Email is invalid"
      assert_select "ul", count: 0
    end
    assert_no_match(/prevented|prohibited|error/i, css_select(".form-errors").text)
  end

  test "several errors are listed with human attribute names" do
    post equipment_reservations_path(equipment(:crashpad)),
      params: booking_params(customer_name: "", end_date: "2026-12-05T10:30")

    assert_select ".form-errors li", count: 2
    assert_select ".form-errors li", text: "Name can't be blank"
    assert_select ".form-errors li", text: "End must be at least 1 hour after the start"
    assert_select "#reservation_end_date_error", text: "must be at least 1 hour after the start"
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

  # edit and update

  test "show links to edit only while the reservation is editable" do
    get reservation_path(reservations(:upcoming))
    assert_select "a[href='#{edit_reservation_path(reservations(:upcoming))}']", text: "Edit"

    get reservation_path(reservations(:finished))
    assert_select "a[href='#{edit_reservation_path(reservations(:finished))}']", count: 0
  end

  test "edit form is prefilled in Prague time" do
    get edit_reservation_path(reservations(:upcoming))

    assert_response :success
    assert_select "form[action='#{reservation_path(reservations(:upcoming))}']"
    assert_select "#reservation_start_date[value='2026-12-02T10:00']" # 09:00 UTC
    assert_select "#reservation_start_date[disabled]", count: 0
  end

  test "update changes the reservation through the booking service" do
    reservation = reservations(:upcoming)

    patch reservation_path(reservation), params: { reservation: { end_date: "2026-12-02T15:00" } }

    assert_redirected_to reservation_path(reservation)
    assert_equal Time.utc(2026, 12, 2, 14, 0), reservation.reload.end_date
    follow_redirect!
    assert_select ".flash-notice", text: "Reservation was updated."
  end

  test "update over capacity re-renders the form and keeps the stored times" do
    crashpad = equipment(:crashpad) # capacity 1, turnaround 60 min
    post equipment_reservations_path(crashpad), params: booking_params
    first = Reservation.order(:id).last
    post equipment_reservations_path(crashpad),
      params: booking_params(start_date: "2026-12-05T14:00", end_date: "2026-12-05T16:00")

    patch reservation_path(first), params: { reservation: { end_date: "2026-12-05T13:30" } }

    assert_response :unprocessable_content
    assert_select ".form-errors[role='alert']", text: /all 1 units are taken/
    assert_equal Time.utc(2026, 12, 5, 11, 0), first.reload.end_date
  end

  test "in-progress reservation can be extended and its start field is disabled" do
    reservation = reservations(:in_progress)

    get edit_reservation_path(reservation)
    assert_select "#reservation_start_date[disabled]"

    patch reservation_path(reservation), params: { reservation: { end_date: "2026-12-01T15:00" } }
    assert_redirected_to reservation_path(reservation)
    assert_equal Time.utc(2026, 12, 1, 14, 0), reservation.reload.end_date
  end

  test "finished and cancelled reservations cannot be edited" do
    %i[finished cancelled].each do |name|
      reservation = reservations(name)

      get edit_reservation_path(reservation)
      assert_redirected_to reservation_path(reservation)
      assert_equal "This reservation can no longer be changed.", flash[:alert]

      patch reservation_path(reservation), params: { reservation: { customer_name: "Changed" } }
      assert_redirected_to reservation_path(reservation)
      assert_not_equal "Changed", reservation.reload.customer_name
    end
  end

  # cancel

  test "show offers cancelling with a confirmation only while editable" do
    reservation = reservations(:upcoming)
    get reservation_path(reservation)
    assert_select "form[action='#{cancel_reservation_path(reservation)}'][data-turbo-confirm]" do
      assert_select "input[name='_method'][value='patch']"
      assert_select "button", text: "Cancel reservation"
    end

    get reservation_path(reservations(:finished))
    assert_select "form[action='#{cancel_reservation_path(reservations(:finished))}']", count: 0
  end

  test "cancel marks the reservation cancelled and frees the slot" do
    crashpad = equipment(:crashpad) # capacity 1
    post equipment_reservations_path(crashpad), params: booking_params
    reservation = Reservation.order(:id).last

    patch cancel_reservation_path(reservation)

    assert_redirected_to reservation_path(reservation)
    assert reservation.reload.cancelled?
    follow_redirect!
    assert_select ".flash-notice[role='status']", text: "Reservation was cancelled."

    assert_difference -> { crashpad.reservations.active.count }, 1 do
      post equipment_reservations_path(crashpad), params: booking_params(customer_name: "Next")
    end
  end

  test "finished reservation cannot be cancelled" do
    reservation = reservations(:finished)

    patch cancel_reservation_path(reservation)

    assert_redirected_to reservation_path(reservation)
    assert reservation.reload.active?
    follow_redirect!
    assert_select ".flash-alert[role='alert']", text: "Finished or cancelled reservations cannot be changed"
  end

  test "equipment page links its reservations" do
    get equipment_path(equipment(:rope))

    assert_select "##{row_id(:upcoming)} a[href='#{reservation_path(reservations(:upcoming))}']"
  end
end
