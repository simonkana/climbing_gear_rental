# Demo data for trying the app right after `bin/rails db:setup`.
# Idempotent: it replaces all equipment and reservations (development data only).
# All times are relative to tomorrow in Prague time, so the data never expires.

Reservation.delete_all
Equipment.delete_all

gear = {
  rope: Equipment.create!(name: "Rope 60 m", capacity: 3, turnaround_minutes: 120,
    description: "Dynamic single rope, 9.8 mm. Inspected for core damage after every rental."),
  harness: Equipment.create!(name: "Harness M", capacity: 4,
    description: "Sport climbing harness, size M."),
  grigri: Equipment.create!(name: "GriGri", capacity: 2,
    description: "Assisted-braking belay device."),
  shoes: Equipment.create!(name: "Climbing shoes EU 42", capacity: 2,
    description: "All-round climbing shoes, EU size 42."),
  quickdraws: Equipment.create!(name: "Quickdraw set 12 pcs", capacity: 3,
    description: "Twelve 12 cm quickdraws."),
  helmet: Equipment.create!(name: "Helmet", capacity: 5,
    description: "Climbing helmet, adjustable 54-62 cm."),
  crashpad: Equipment.create!(name: "Crashpad", capacity: 1,
    description: "Large bouldering crashpad, 120 x 100 cm.")
}

puts "Seeded #{gear.size} equipment items."
