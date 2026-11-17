class Equipment < ApplicationRecord
  include HasPublicId

  has_many :reservations, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }
  validates :capacity, numericality: { only_integer: true, in: 1..100 }
  validates :turnaround_minutes, numericality: { only_integer: true, in: 0..1440 }

  # Optional photo, hotlinked (D17). Blank input is stored as nil.
  normalizes :image_url, with: ->(url) { url.strip.presence }
  validates :image_url, length: { maximum: 2048 }, allow_nil: true
  validate :image_url_is_https_link

  # Units not blocked at a single instant (display only; bookings are checked
  # in ReservationBooking). A reservation blocks [start_date, end_date + turnaround).
  def units_free_at(time = Time.current)
    in_use = reservations.active
      .where(start_date: ..time)
      .where(Reservation.arel_table[:end_date].gt(time - turnaround_minutes.minutes))
      .count

    [ capacity - in_use, 0 ].max
  end

  private
    # Only absolute https links: rules out javascript:, data: and mixed content.
    def image_url_is_https_link
      return if image_url.nil?

      uri = URI.parse(image_url)
      errors.add(:image_url, :not_https_url) unless uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:image_url, :not_https_url)
    end
end
