class EquipmentController < ApplicationController
  def index
    @equipment = Equipment.order(:name)
  end

  def show
    @equipment = Equipment.find_by!(public_id: params.expect(:id))
    reservations = @equipment.reservations
    # Active and not yet finished (includes reservations in progress).
    @upcoming = reservations.active
      .where(Reservation.arel_table[:end_date].gt(Time.current))
      .order(:start_date)
    @past = reservations.where.not(id: @upcoming).order(start_date: :desc)
  end
end
