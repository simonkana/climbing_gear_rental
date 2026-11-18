require "test_helper"

class EquipmentControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  test "root page shows the equipment index inside the base layout" do
    get root_path

    assert_response :success
    assert_select "a.skip-link[href='#main']"
    assert_select "header a[href='#{root_path}']", text: "Climbing Gear Rental"
    assert_select "nav[aria-label='Main'] a[href='#{equipment_index_path}']", text: "Equipment"
    assert_select "main#main h1", text: "Rent climbing gear by the hour."
    assert_select ".flash", count: 0
  end

  test "pages send a strict content security policy with a script nonce" do
    get root_path

    policy = response.headers["Content-Security-Policy"]
    assert_match(/default-src 'self'/, policy)
    assert_match(/img-src 'self' https:/, policy)
    assert_match(/frame-ancestors 'none'/, policy)
    nonce = policy[/script-src 'self' 'nonce-([^']+)'/, 1]
    assert nonce.present?
    assert_select "script[type='importmap'][nonce='#{nonce}']"
  end

  test "nav marks the current section for assistive technology" do
    get equipment_index_path
    assert_select "nav a[aria-current='page']", text: "Equipment"

    get reservations_path
    assert_select "nav a[aria-current='page']", text: "Reservations"
    assert_select "nav a[aria-current]", count: 1
  end

  test "header has an accessible mobile menu toggle that is hidden until JavaScript enables it" do
    get equipment_index_path

    assert_select "header[data-controller='nav-menu']" do
      assert_select "button.menu-toggle[hidden][type='button'][aria-expanded='false'][aria-controls='main-nav']", text: /Menu/
      assert_select "nav#main-nav[aria-label='Main'] a", count: 2
    end
  end

  test "index lists equipment with capacity and units free now" do
    get equipment_index_path

    assert_response :success
    assert_select "#equipment_#{equipment(:rope).public_id}" do
      assert_select "a[href='#{equipment_path(equipment(:rope))}']", text: "Rope 60 m"
      assert_select ".capacity", text: "3"
      assert_select ".free-now", text: "2" # one reservation in progress
    end
    assert_select "#equipment_#{equipment(:crashpad).public_id} .free-now", text: "1"
  end

  test "each card shows a unit gauge with free units and the turnaround" do
    get equipment_index_path

    assert_select "#equipment_#{equipment(:rope).public_id}" do
      assert_select ".gauge-units[aria-hidden='true'] .gauge-unit", count: 3
      assert_select ".gauge-unit.is-free", count: 2
      assert_select ".gauge-text", text: "2 of 3 free now"
      assert_select ".hint", text: "2 h inspection after each return"
    end
    assert_select "#equipment_#{equipment(:crashpad).public_id} .hint", text: "1 h inspection after each return"
  end

  test "large capacities show the free units as text only" do
    big = Equipment.create!(name: "Carabiner", capacity: 40, turnaround_minutes: 30)

    get equipment_index_path

    assert_select "#equipment_#{big.public_id}" do
      assert_select ".gauge-units", count: 0
      assert_select ".gauge-text", text: "40 of 40 free now"
      assert_select ".hint", text: "30 min inspection after each return"
    end
  end

  test "gear without a turnaround says it is ready right after return" do
    chalk_bag = Equipment.create!(name: "Chalk bag", capacity: 6, turnaround_minutes: 0)

    get equipment_index_path

    assert_select "#equipment_#{chalk_bag.public_id} .hint", text: "Ready again right after return"
  end

  test "index without equipment invites adding the first piece" do
    Reservation.delete_all
    Equipment.delete_all

    get equipment_index_path

    assert_select "p", text: /No gear yet/
    assert_select "a[href='#{new_equipment_path}']", text: "Add the first piece"
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

  test "show keeps the line breaks of the description and escapes markup" do
    rope = equipment(:rope)
    rope.update!(description: "Dry treated.\n\nRetired after 5 years. <b>Bold</b>")

    get equipment_path(rope)

    assert_select "p.lead", count: 2
    assert_select "p.lead", text: "Retired after 5 years. <b>Bold</b>"
    assert_select "p.lead b", count: 0
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

  # images

  test "create stores an optional image url" do
    post equipment_index_path, params: { equipment: {
      name: "Helmet", capacity: 5, image_url: "https://example.com/helmet.jpg"
    } }

    assert_equal "https://example.com/helmet.jpg", Equipment.find_by!(name: "Helmet").image_url
  end

  test "create with an invalid image url re-renders the form" do
    post equipment_index_path, params: { equipment: { name: "Helmet", capacity: 5, image_url: "http://example.com/a.jpg" } }

    assert_response :unprocessable_content
    assert_select "#equipment_image_url[aria-invalid='true']"
    assert_select ".form-errors", text: /Image URL must be an https:\/\/ link to an image/
  end

  test "equipment with an image shows it with alt text, without one a placeholder" do
    rope = equipment(:rope)
    rope.update!(image_url: "https://example.com/rope.jpg")

    get equipment_path(rope)
    assert_select "img[src='https://example.com/rope.jpg'][alt='Rope 60 m'][loading='lazy'][referrerpolicy='no-referrer']"

    get equipment_path(equipment(:crashpad))
    assert_select "img", count: 0
    assert_select ".image-placeholder[role='img'][aria-label='No image available']", text: /No image available/
  end

  test "index and booking page show the equipment image or placeholder" do
    equipment(:rope).update!(image_url: "https://example.com/rope.jpg")

    get equipment_index_path
    assert_select "#equipment_#{equipment(:rope).public_id} img[src='https://example.com/rope.jpg']"
    assert_select "#equipment_#{equipment(:crashpad).public_id} .image-placeholder"

    get new_equipment_reservation_path(equipment(:rope))
    assert_select "img[src='https://example.com/rope.jpg']"
  end

  test "new equipment form has an image url field" do
    get new_equipment_path

    assert_select "label[for='equipment_image_url']"
    assert_select "input[type='url']#equipment_image_url"
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

  test "unknown public_id shows the not found page in the app layout" do
    get equipment_path(id: SecureRandom.uuid_v7)

    assert_response :not_found
    assert_select "h1", "Page not found"
    assert_select "nav#main-nav"
    assert_select "a[href=?]", equipment_index_path, text: "Browse equipment"
  end

  test "numeric id does not resolve" do
    get equipment_path(id: equipment(:rope).id)

    assert_response :not_found
  end
end
