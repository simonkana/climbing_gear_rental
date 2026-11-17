# Every create/update goes through ReservationBooking (GUARDRAILS #1).
class ReservationsController < ApplicationController
  before_action :set_reservation, only: %i[show]
  before_action :set_equipment, only: %i[new create]

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

  def new
    @reservation = @equipment.reservations.build
  end

  def create
    @reservation = @equipment.reservations.build(reservation_params)

    if ReservationBooking.new(@reservation).call
      redirect_to @reservation, notice: "Reservation was created."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def set_reservation
      @reservation = Reservation.find_by!(public_id: params.expect(:id))
    end

    def set_equipment
      @equipment = Equipment.find_by!(public_id: params.expect(:equipment_id))
    end

    # equipment_id, status and public_id are never mass-assignable (GUARDRAILS #12).
    def reservation_params
      params.expect(reservation: %i[customer_name customer_email customer_phone start_date end_date])
    end
end
