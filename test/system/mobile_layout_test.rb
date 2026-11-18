require "application_system_test_case"

class MobileLayoutTest < ApplicationSystemTestCase
  WIDTH = 390

  # Headless Chrome windows cannot be narrower than 500px, so a phone is emulated.
  driven_by :selenium, using: :headless_chrome, screen_size: [ WIDTH, 844 ], options: { name: :mobile_chrome } do |options|
    options.binary = CHROME_BINARY
    options.add_emulation(device_metrics: { width: WIDTH, height: 844, pixelRatio: 2, touch: true })
  end

  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  test "no page scrolls sideways on a phone" do
    pages.each do |name, path|
      visit path
      assert_selector "main#main h1"
      save_review_screenshot("mobile_#{name}")
      assert_no_horizontal_overflow("mobile #{name}", WIDTH)
    end
  end

  test "header shows the logo mark and the menu button on one row" do
    visit equipment_index_path

    assert_operator rect(".site-logo span")["width"], :<=, 1, "logo name should be visually hidden"
    assert_selector ".site-logo", text: "Climbing Gear Rental" # still the link's accessible name
    logo = rect(".site-logo")
    toggle = rect(".menu-toggle")
    assert_in_delta logo["top"] + logo["height"] / 2, toggle["top"] + toggle["height"] / 2, 8, "not on one row"
    assert_operator toggle["right"], :>, WIDTH - 40, "menu button should sit at the right edge"
  end

  # Waits (with Capybara's retry timeout) until no CSS transition is running.
  def wait_for_animations
    page.document.synchronize do
      running = page.evaluate_script("document.getAnimations().length")
      raise Capybara::ExpectationNotMet, "#{running} animations still running" unless running.zero?
    end
  end

  test "menu opens, closes with Escape and navigates" do
    visit equipment_index_path
    assert_no_link "Reservations" # closed: hidden from view and from assistive technology

    click_button "Menu"
    assert_selector "button.menu-toggle[aria-expanded='true']"
    assert_link "Reservations"

    find("body").send_keys(:escape)
    assert_selector "button.menu-toggle[aria-expanded='false']"
    assert_no_link "Reservations"
    assert page.evaluate_script("document.activeElement.classList.contains('menu-toggle')"), "focus returns to the button"

    click_button "Menu"
    wait_for_animations # the link slides in; clicking mid-transition can miss it
    click_link "Reservations"
    assert_current_path reservations_path
    assert_selector "button.menu-toggle[aria-expanded='false']" # a new page starts closed
  end

  test "equipment page puts the booking panel between the photo and the reservations" do
    visit equipment_path(equipment(:rope))

    assert_operator rect(".detail-intro")["bottom"], :<=, rect(".booking-panel")["top"]
    assert_operator rect(".booking-panel")["bottom"], :<=, rect("#upcoming-reservations")["top"]
    assert_operator rect(".table-wrapper")["right"], :<=, WIDTH, "the table scrolls inside its wrapper"
  end
end
