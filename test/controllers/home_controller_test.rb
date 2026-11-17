require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "root page renders inside the base layout" do
    get root_path

    assert_response :success
    assert_select "a.skip-link[href='#main']"
    assert_select "header a[href='#{root_path}']", text: "Climbing Gear Rental"
    assert_select "nav[aria-label='Main'] a[href='#{root_path}']", text: "Equipment"
    assert_select "main#main h1"
    assert_select "footer"
  end

  test "root page renders no flash container when flash is empty" do
    get root_path

    assert_select ".flash", count: 0
  end
end
