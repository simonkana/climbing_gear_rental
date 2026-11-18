require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "unknown path shows the not found page in the app layout" do
    get "/no-such-page"

    assert_response :not_found
    assert_select "h1", "Page not found"
    assert_select "nav#main-nav"
    assert_select "a[href=?]", equipment_index_path, text: "Browse equipment"
  end

  test "unknown nested path shows the not found page" do
    get "/equipment/#{equipment(:rope).public_id}/no-such-page"

    assert_response :not_found
    assert_select "h1", "Page not found"
  end

  test "unknown path with a non-HTML format returns an empty not found" do
    get "/no-such-page.json"

    assert_response :not_found
    assert_empty response.body
  end

  test "unknown path gives not found for any HTTP method" do
    post "/no-such-page"
    assert_response :not_found

    delete reservation_path(reservations(:upcoming)) # reservations have no destroy
    assert_response :not_found
  end

  test "unknown path gives not found, not a CSRF error, when forgery protection is on" do
    ActionController::Base.allow_forgery_protection = true
    post "/no-such-page"

    assert_response :not_found
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "catch-all route comes after the framework routes" do
    assert_equal "errors#not_found", Rails.application.routes.routes.to_a.last.requirements.values_at(:controller, :action).join("#")
    assert_equal "rails/health", Rails.application.routes.recognize_path("/up")[:controller]
    assert_equal "turbo/native/navigation", Rails.application.routes.recognize_path("/recede_historical_location")[:controller]
    assert_equal "active_storage/disk",
      Rails.application.routes.recognize_path("/rails/active_storage/disk/key/file.jpg")[:controller]
  end
end
