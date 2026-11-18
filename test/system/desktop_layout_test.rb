require "application_system_test_case"

class DesktopLayoutTest < ApplicationSystemTestCase
  WIDTH = 1400

  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  test "no page scrolls sideways on a desktop" do
    pages.each do |name, path|
      visit path
      assert_selector "main#main h1"
      save_review_screenshot("desktop_#{name}")
      assert_no_horizontal_overflow("desktop #{name}", page.evaluate_script("window.innerWidth"))
    end
  end

  test "navigation links are shown without a menu button" do
    visit equipment_index_path

    assert_no_button "Menu"
    assert_link "Equipment"
    assert_link "Reservations"
    assert_selector ".site-logo span", text: "Climbing Gear Rental"
  end

  test "equipment page shows the booking panel beside the details" do
    visit equipment_path(equipment(:rope))

    intro = rect(".detail-intro")
    panel = rect(".booking-panel")
    assert_operator panel["left"], :>=, intro["right"], "panel should be to the right"
    assert_in_delta intro["top"], panel["top"], 2, "panel should start at the top"
  end

  test "a reservation can be booked and cancelled in the browser" do
    visit equipment_path(equipment(:crashpad))
    click_link "Book a time slot"

    fill_in "Name", with: "Tommy Caldwell"
    fill_in "Email", with: "tommy@example.com"
    find_field("From").set(Time.zone.local(2026, 12, 5, 10, 0))
    find_field("To").set(Time.zone.local(2026, 12, 5, 12, 0))
    click_button "Book"

    assert_text "Reservation was created."
    assert_selector ".status-upcoming", text: "Upcoming"
    assert_text "5. 12. 2026 10:00"

    accept_confirm("Cancel this reservation?") { click_button "Cancel reservation" }

    assert_text "Reservation was cancelled."
    assert_selector ".status-cancelled", text: "Cancelled"
  end

  test "booking over capacity shows the capacity error in the form" do
    rope = equipment(:rope) # capacity 3
    3.times do |index|
      ReservationBooking.new(Reservation.new(equipment: rope, customer_name: "Climber #{index}",
        customer_email: "climber#{index}@example.com",
        start_date: Time.zone.local(2026, 12, 6, 10, 0), end_date: Time.zone.local(2026, 12, 6, 14, 0))).call
    end

    visit new_equipment_reservation_path(rope)
    fill_in "Name", with: "Late Climber"
    fill_in "Email", with: "late@example.com"
    find_field("From").set(Time.zone.local(2026, 12, 6, 11, 0))
    find_field("To").set(Time.zone.local(2026, 12, 6, 13, 0))
    click_button "Book"

    assert_selector ".form-errors[role='alert']", text: "all 3 units are taken"
    assert_selector "h1", text: "Book Rope 60 m"
  end

  test "an error link jumps to its field without clearing the form" do
    visit new_equipment_reservation_path(equipment(:crashpad))
    fill_in "Name", with: "Lynn Hill"
    fill_in "Email", with: "lynn@example.com"
    find_field("From").set(Time.zone.local(2026, 11, 30, 10, 0)) # before the travelled-to "now"
    find_field("To").set(Time.zone.local(2026, 12, 5, 12, 0))
    click_button "Book"

    error_link = find(".form-errors a", text: /future/)
    target = error_link[:href].split("#").last
    error_link.click

    assert_equal target, URI.parse(current_url).fragment
    assert_field "Name", with: "Lynn Hill"
    assert_field "Email", with: "lynn@example.com"
    assert_selector ".form-errors", text: /future/
  end
end
