# Field validations only. Capacity is checked exclusively in ReservationBooking,
# under the equipment row lock (see IMPLEMENTATION_PLAN.md §4.4).
class Reservation < ApplicationRecord
  include HasPublicId

  TIME_STEP = 15.minutes
  MIN_DURATION = 1.hour
  MAX_DURATION = 30.days

  belongs_to :equipment
  # Moving a reservation to other equipment would need two equipment locks (D11).
  attr_readonly :equipment_id

  enum :status, { active: "active", cancelled: "cancelled" }, default: :active, validate: true

  validates :customer_name, presence: true, length: { maximum: 100 }
  validates :customer_email, presence: true, length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :customer_phone, length: { maximum: 30 }, allow_blank: true
  validates :start_date, :end_date, presence: true

  validate :end_after_start_within_duration_limits
  validate :times_on_time_step
  validate :start_in_future, if: -> { new_record? || (will_save_change_to_start_date? && !started?) }
  validate :editable, on: :update
  validate :start_unchanged_once_started, on: :update

  # End of the blocked interval: the unit is unavailable until inspection is done.
  def blocked_until
    end_date + equipment.turnaround_minutes.minutes
  end

  # Based on the persisted values, so edits in progress don't change the answer.
  def started?
    persisted? && start_date_in_database <= Time.current
  end

  def finished?
    persisted? && end_date_in_database <= Time.current
  end

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

    def editable
      return unless changed?

      errors.add(:base, :not_editable) if status_in_database == "cancelled" || finished?
    end

    def start_unchanged_once_started
      errors.add(:start_date, :already_started) if will_save_change_to_start_date? && started?
    end
end
