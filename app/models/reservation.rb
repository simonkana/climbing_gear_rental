# Field validations only. Capacity is checked exclusively in ReservationBooking,
# under the equipment row lock (see IMPLEMENTATION_PLAN.md §4.4).
class Reservation < ApplicationRecord
  include HasPublicId

  TIME_STEP = 15.minutes
  MIN_DURATION = 1.hour
  MAX_DURATION = 30.days

  belongs_to :equipment

  enum :status, { active: "active", cancelled: "cancelled" }, default: :active, validate: true

  validates :customer_name, presence: true, length: { maximum: 100 }
  validates :customer_email, presence: true, length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :customer_phone, length: { maximum: 30 }, allow_blank: true
  validates :start_date, :end_date, presence: true

  validate :end_after_start_within_duration_limits
  validate :times_on_time_step
  validate :start_in_future, if: -> { new_record? || will_save_change_to_start_date? }

  private
    def end_after_start_within_duration_limits
      return if start_date.blank? || end_date.blank?

      # Absolute seconds, so durations stay correct across DST changes.
      duration = end_date - start_date
      if duration <= 0
        errors.add(:end_date, :not_after_start)
      elsif duration < MIN_DURATION
        errors.add(:end_date, :duration_too_short)
      elsif duration > MAX_DURATION
        errors.add(:end_date, :duration_too_long)
      end
    end

    def times_on_time_step
      { start_date: start_date, end_date: end_date }.each do |attribute, time|
        next if time.blank?

        errors.add(attribute, :not_on_time_step) unless (time.to_r % TIME_STEP).zero?
      end
    end

    def start_in_future
      return if start_date.blank?

      errors.add(:start_date, :not_in_future) unless start_date > Time.current
    end
end
