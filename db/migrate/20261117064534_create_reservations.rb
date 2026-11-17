class CreateReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :reservations do |t|
      t.string :public_id, limit: 36, null: false, collation: "ascii_bin"
      t.references :equipment, null: false, foreign_key: true, index: false
      t.string :customer_name, limit: 100, null: false
      t.string :customer_email, limit: 255, null: false
      t.string :customer_phone, limit: 30
      t.datetime :start_date, null: false
      t.datetime :end_date, null: false
      t.string :status, limit: 20, null: false, default: "active"
      t.timestamps
    end

    add_index :reservations, :public_id, unique: true
    # Serves the capacity overlap query; equipment_id first also satisfies the FK index requirement.
    add_index :reservations, %i[equipment_id status start_date]
    add_check_constraint :reservations, "end_date > start_date", name: "reservations_end_after_start"
    add_check_constraint :reservations, "status IN ('active', 'cancelled')", name: "reservations_status_valid"
  end
end
