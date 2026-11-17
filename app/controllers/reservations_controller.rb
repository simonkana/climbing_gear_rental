# Every create/update goes through ReservationBooking (GUARDRAILS #1).
class ReservationsController < ApplicationController
  before_action :set_reservation, only: %i[show]

  def index
    reservations = Reservation.includes(:equipment)
    # Active and not yet finished (includes reservations in progress).
    @upcoming = reservations.active
      .where(Reservation.arel_table[:end_date].gt(Time.current))
      .order(:start_date)
    @past = reservations.where.not(id: @upcoming).order(start_date: :desc)
  end

  def show
  end

  private
    def set_reservation
      @reservation = Reservation.find_by!(public_id: params.expect(:id))
    end
end
