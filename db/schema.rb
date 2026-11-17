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

ActiveRecord::Schema[8.1].define(version: 2026_11_17_091512) do
  create_table "equipment", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "public_id", limit: 36, null: false, collation: "ascii_bin"
    t.string "name", limit: 120, null: false
    t.text "description"
    t.integer "capacity", null: false
    t.integer "turnaround_minutes", default: 60, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url", limit: 2048
    t.index ["public_id"], name: "index_equipment_on_public_id", unique: true
    t.check_constraint "(`image_url` is null) or (`image_url` like _utf8mb4'https://%')", name: "equipment_image_url_https"
    t.check_constraint "`capacity` > 0", name: "equipment_capacity_positive"
    t.check_constraint "`turnaround_minutes` >= 0", name: "equipment_turnaround_non_negative"
  end

  create_table "reservations", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "public_id", limit: 36, null: false, collation: "ascii_bin"
    t.bigint "equipment_id", null: false
    t.string "customer_name", limit: 100, null: false
    t.string "customer_email", null: false
    t.string "customer_phone", limit: 30
    t.datetime "start_date", null: false
    t.datetime "end_date", null: false
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["equipment_id", "status", "start_date"], name: "index_reservations_on_equipment_id_and_status_and_start_date"
    t.index ["public_id"], name: "index_reservations_on_public_id", unique: true
    t.check_constraint "`end_date` > `start_date`", name: "reservations_end_after_start"
    t.check_constraint "`status` in (_utf8mb4'active',_utf8mb4'cancelled')", name: "reservations_status_valid"
  end

  add_foreign_key "reservations", "equipment"
end
