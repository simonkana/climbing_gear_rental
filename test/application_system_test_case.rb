require "test_helper"

# Browser tests (Capybara + Selenium, the Rails default). Selenium Manager
# downloads Chrome for Testing and chromedriver on first run if needed.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Rails resolves only the chromedriver path up front, so the Chrome binary
  # that Selenium Manager found (or downloaded) has to be passed explicitly.
  CHROME_BINARY = Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome")["browser_path"]

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |options|
    options.binary = CHROME_BINARY
  end

  # Every page these tests visit, by name, for layout checks and screenshots.
  def pages
    {
      "equipment_index" => equipment_index_path,
      "equipment_show" => equipment_path(equipment(:rope)),
      "equipment_new" => new_equipment_path,
      "reservation_new" => new_equipment_reservation_path(equipment(:rope)),
      "reservations_index" => reservations_path,
      "reservation_show" => reservation_path(reservations(:upcoming)),
      "reservation_edit" => edit_reservation_path(reservations(:upcoming))
    }
  end

  # The page must never scroll sideways: wide content (tables) scrolls inside its own wrapper.
  # Compared with the device width, not window.innerWidth: on mobile, Chrome
  # zooms out to fit overflowing content, which also grows innerWidth.
  def assert_no_horizontal_overflow(name, viewport_width)
    overflow = page.evaluate_script("document.documentElement.scrollWidth") - viewport_width
    assert_operator overflow, :<=, 0, "#{name}: page is #{overflow}px wider than the #{viewport_width}px viewport"
  end

  # SCREENSHOTS=1 bin/rails test:system saves every page to tmp/screenshots for a visual review.
  def save_review_screenshot(name)
    return unless ENV["SCREENSHOTS"]

    # Full-page capture through the Chrome DevTools Protocol (Selenium's own is viewport-only in Chrome).
    shot = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, Base64.decode64(shot["data"]))
  end

  def rect(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().toJSON()")
  end
end
