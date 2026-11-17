class CreateEquipment < ActiveRecord::Migration[8.1]
  def change
    create_table :equipment do |t|
      t.string :public_id, limit: 36, null: false, collation: "ascii_bin"
      t.string :name, limit: 120, null: false
      t.text :description
      t.integer :capacity, null: false
      t.integer :turnaround_minutes, null: false, default: 60
      t.timestamps
    end

    add_index :equipment, :public_id, unique: true
    add_check_constraint :equipment, "capacity > 0", name: "equipment_capacity_positive"
    add_check_constraint :equipment, "turnaround_minutes >= 0", name: "equipment_turnaround_non_negative"
  end
end
