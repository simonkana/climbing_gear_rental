require "test_helper"

class I18nFormatsTest < ActiveSupport::TestCase
  test "application time zone is Prague" do
    assert_equal "Prague", Time.zone.name
  end

  test "times display in Czech format in Prague winter time" do
    time = Time.utc(2026, 11, 17, 13, 30).in_time_zone

    assert_equal "17. 11. 2026 14:30", I18n.l(time)
  end

  test "times display in Prague summer time without zero padding of day and month" do
    time = Time.utc(2026, 7, 1, 12, 0).in_time_zone

    assert_equal "1. 7. 2026 14:00", I18n.l(time)
  end

  test "dates display in Czech format" do
    assert_equal "17. 11. 2026", I18n.l(Date.new(2026, 11, 17))
  end
end
