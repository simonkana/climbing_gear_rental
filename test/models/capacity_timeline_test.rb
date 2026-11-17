require "test_helper"

class CapacityTimelineTest < ActiveSupport::TestCase
  # Most cases use integer hours for readability; intervals are half-open ranges.
  def peak(window, *intervals)
    CapacityTimeline.peak(window: window, intervals: intervals)
  end

  test "no intervals give a peak of zero" do
    assert_equal 0, peak(8...12)
  end

  test "a single interval gives a peak of one" do
    assert_equal 1, peak(8...12, 9...11)
  end

  test "touching intervals do not overlap" do
    assert_equal 1, peak(8...12, 8...10, 10...12)
  end

  test "nested intervals overlap" do
    assert_equal 2, peak(8...12, 8...12, 9...10)
  end

  test "identical intervals all count" do
    assert_equal 3, peak(8...12, 9...11, 9...11, 9...11)
  end

  test "counts the real peak, not every interval overlapping the window" do
    # Plan §4.2: capacity 2, A 08-10, B 12-14, candidate 09-13.
    # The candidate overlaps both, so a naive count gives 3, but at no instant
    # are more than 2 units in use.
    candidate = 9...13

    assert_equal 2, peak(candidate, 8...10, 12...14, candidate)
  end

  test "ignores a peak outside the window" do
    assert_equal 0, peak(8...12, 14...16, 14...16, 14...16)
    assert_equal 1, peak(8...12, 10...16, 14...16, 14...16)
  end

  test "clips intervals that partly overlap the window" do
    assert_equal 1, peak(10...12, 6...11)
    assert_equal 2, peak(10...12, 6...11, 11...20, 10...14)
  end

  test "an interval ending where the window starts does not count" do
    assert_equal 0, peak(10...12, 8...10)
    assert_equal 0, peak(10...12, 12...14)
  end

  test "result does not depend on input order" do
    intervals = [ 8...10, 9...13, 12...14, 11...12, 9...10 ]

    expected = CapacityTimeline.peak(window: 8...14, intervals: intervals)
    intervals.permutation.each do |order|
      assert_equal expected, CapacityTimeline.peak(window: 8...14, intervals: order)
    end
    assert_equal 3, expected
  end

  test "works with times including turnaround" do
    turnaround = 2.hours
    existing_start = Time.zone.local(2026, 12, 5, 8, 0)
    existing_end = Time.zone.local(2026, 12, 5, 12, 0)
    blocked = existing_start...(existing_end + turnaround) # blocked until 14:00

    at_blocked_end = Time.zone.local(2026, 12, 5, 14, 0)...Time.zone.local(2026, 12, 5, 18, 0)
    one_step_earlier = Time.zone.local(2026, 12, 5, 13, 45)...Time.zone.local(2026, 12, 5, 18, 0)

    assert_equal 1, peak(at_blocked_end, blocked, at_blocked_end)
    assert_equal 2, peak(one_step_earlier, blocked, one_step_earlier)
  end
end
