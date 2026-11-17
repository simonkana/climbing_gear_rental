# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_17_062925) do
  create_table "equipment", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "public_id", limit: 36, null: false, collation: "ascii_bin"
    t.string "name", limit: 120, null: false
    t.text "description"
    t.integer "capacity", null: false
    t.integer "turnaround_minutes", default: 60, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_equipment_on_public_id", unique: true
    t.check_constraint "`capacity` > 0", name: "equipment_capacity_positive"
    t.check_constraint "`turnaround_minutes` >= 0", name: "equipment_turnaround_non_negative"
  end
end
