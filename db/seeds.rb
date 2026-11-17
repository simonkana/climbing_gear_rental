# Demo data for trying the app right after `bin/rails db:setup`.
# Idempotent: it replaces all equipment and reservations (development data only).
# All times are relative to the day the seeds run (Prague time), so the data never
# expires. The scenarios are one week ahead, which leaves the reviewer several
# days to try them before they turn into past reservations.

Reservation.delete_all
Equipment.delete_all

# Photos: hotlinked Wikimedia Commons thumbnails (D17), all freely licensed:
#   Rope       "Climbing Rope.jpg", Climber.Ben.Johnson, CC BY-SA 4.0
#   Harness    "Baudrier.jpg", Savant-fou, CC BY-SA 3.0
#   GriGri     "Petzl Grigri 2.jpg", Climber.Ben.Johnson, CC BY-SA 4.0
#   Shoes      "Climbing shoes Rockempire.jpg", Malis, public domain
#   Quickdraws "Quickdraw Singingrock 1.jpg", Malis, public domain
#   Helmet     "Climbing helmet Petzl Meteor - 1.jpg", Malis, public domain
#   Crashpad   "Bouldering Crash Pad.jpg", Mark Donoher, CC BY 2.0
# Source pages: https://commons.wikimedia.org/wiki/File:<file name>
commons = ->(path) { "https://thumb.wikimedia.org/wikipedia/commons/thumb/#{path}" }

gear = {
  rope: Equipment.create!(name: "Rope 60 m", capacity: 3, turnaround_minutes: 120,
    description: "Dynamic single rope, 9.8 mm. Inspected for core damage after every rental.",
    image_url: commons.("e/e4/Climbing_Rope.jpg/960px-Climbing_Rope.jpg")),
  harness: Equipment.create!(name: "Harness M", capacity: 4,
    description: "Sport climbing harness, size M.",
    image_url: commons.("f/fd/Baudrier.jpg/960px-Baudrier.jpg")),
  grigri: Equipment.create!(name: "GriGri", capacity: 2,
    description: "Assisted-braking belay device.",
    image_url: commons.("5/5f/Petzl_Grigri_2.jpg/960px-Petzl_Grigri_2.jpg")),
  shoes: Equipment.create!(name: "Climbing shoes EU 42", capacity: 2,
    description: "All-round climbing shoes, EU size 42.",
    image_url: commons.("c/c4/Climbing_shoes_Rockempire.jpg/960px-Climbing_shoes_Rockempire.jpg")),
  quickdraws: Equipment.create!(name: "Quickdraw set 12 pcs", capacity: 3,
    description: "Twelve 12 cm quickdraws.",
    image_url: commons.("a/a6/Quickdraw_Singingrock_1.jpg/960px-Quickdraw_Singingrock_1.jpg")),
  helmet: Equipment.create!(name: "Helmet", capacity: 5,
    description: "Climbing helmet, adjustable 54-62 cm.",
    image_url: commons.("9/9b/Climbing_helmet_Petzl_Meteor_-_1.jpg/960px-Climbing_helmet_Petzl_Meteor_-_1.jpg")),
  crashpad: Equipment.create!(name: "Crashpad", capacity: 1,
    description: "Large bouldering crashpad, 120 x 100 cm.",
    image_url: commons.("8/86/Bouldering_Crash_Pad.jpg/960px-Bouldering_Crash_Pad.jpg"))
}

today = Time.zone.now.beginning_of_day
scenario_day = today + 7.days

# The scenario day (or `day` days after it) at the given Prague time.
# Lambdas instead of methods/constants keep the helpers local to this file.
at = ->(hour, min = 0, day: 0) { (scenario_day + day.days).change(hour: hour, min: min) }

customers = [ "Alex Novak", "Petra Svobodova", "Jakub Dvorak", "Tereza Kralova", "Martin Horak", "Eva Prochazkova" ].cycle

build = lambda do |equipment, from, to|
  name = customers.next
  Reservation.new(equipment: equipment, start_date: from, end_date: to,
    customer_name: name, customer_email: "#{name.split.first.downcase}@example.com")
end

# Future reservations go through the real booking logic (capacity check under lock).
book = lambda do |equipment, from, to|
  reservation = build.(equipment, from, to)
  ReservationBooking.new(reservation).call ||
    raise("Seed booking failed for #{equipment.name}: #{reservation.errors.full_messages.to_sentence}")
  reservation
end

# S1: Crashpad (capacity 1, turnaround 60 min)
book.(gear[:crashpad], at.(10), at.(18))

# S2: GriGri (capacity 2): both units taken 13:00-17:00
book.(gear[:grigri], at.(9), at.(17))
book.(gear[:grigri], at.(13), at.(20))

# S3: Rope (capacity 3, turnaround 2 h): fully booked 13:00-14:00
book.(gear[:rope], at.(8), at.(12))
book.(gear[:rope], at.(10), at.(14))
book.(gear[:rope], at.(13), at.(17))

# S4: Shoes (capacity 2): two bookings that never overlap each other
book.(gear[:shoes], at.(8), at.(10))
book.(gear[:shoes], at.(12), at.(14))

# S5: Harness (capacity 4): four bookings, one of them cancelled
4.times { book.(gear[:harness], at.(10), at.(14)) }
gear[:harness].reservations.first.update!(status: :cancelled)

# S6: Helmet: finished reservations. Past start dates cannot pass validation, so
# they are written directly. This is the only documented exception to
# "every reservation write goes through ReservationBooking" (GUARDRAILS #1).
[ 1, 7 ].each do |days_ago|
  date = today - days_ago.days
  past = build.(gear[:helmet], date.change(hour: 10), date.change(hour: 16))
  past.public_id = SecureRandom.uuid_v7 # callbacks do not run with validate: false
  past.save!(validate: false)
end

# Filler so no equipment page is empty.
book.(gear[:quickdraws], at.(9, day: 1), at.(17, day: 1))

puts <<~GUIDE
  Seeded #{gear.size} equipment items and #{Reservation.count} reservations.

  Scenarios to try, all on #{I18n.l(scenario_day.to_date)} (one week from today, Prague time):
    S1 Crashpad (capacity 1, 60 min turnaround): booked 10:00-18:00.
       A booking from 18:30 is rejected (still in turnaround), from 19:00 it is accepted.
    S2 GriGri (capacity 2): booked 09:00-17:00 and 13:00-20:00.
       15:00-16:00 is rejected (full), 10:00-12:00 is accepted.
    S3 Rope 60 m (capacity 3, 2 h turnaround): nearly full, all 3 units taken 13:00-14:00.
       12:00-15:00 is rejected, 09:00-11:00 is accepted.
    S4 Climbing shoes EU 42 (capacity 2): booked 08:00-10:00 and 12:00-14:00.
       09:00-13:00 is accepted: it overlaps both, but never more than 2 units are in use.
    S5 Harness M (capacity 4): 4 bookings 10:00-14:00, one cancelled.
       One more 10:00-14:00 booking is accepted; the cancelled one does not count.
    S6 Helmet: two past reservations, listed as finished and no longer editable.

  Start the app with bin/rails server and open http://localhost:3000
GUIDE
