require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 12, 1, 8, 0) }

  def load_seeds
    capture_io { Rails.application.load_seed }
  end

  test "seeds the equipment catalogue" do
    load_seeds

    expected = {
      "Rope 60 m" => 3, "Harness M" => 4, "GriGri" => 2, "Climbing shoes EU 42" => 2,
      "Quickdraw set 12 pcs" => 3, "Helmet" => 5, "Crashpad" => 1
    }
    assert_equal expected, Equipment.order(:id).pluck(:name, :capacity).to_h
    assert_equal 120, Equipment.find_by!(name: "Rope 60 m").turnaround_minutes
  end

  test "seeds can be loaded repeatedly" do
    load_seeds
    load_seeds

    assert_equal 7, Equipment.count
  end
end
