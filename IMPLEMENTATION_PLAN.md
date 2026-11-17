# Implementation Plan: climbing_gear_rental

Reservation app for a climbing gear rental; take-home assignment for a Ruby on Rails backend position.
Stack: Ruby 3.4.10, Rails 8.1.4.1 (`--skip-docker`), MySQL 8.4, Minitest, Propshaft, plain CSS, `.html.erb` views.

This file says *what* to build and *in which order*. `AGENTS.md` says *how* agents work (workflow, commits, commands, conventions), `GUARDRAILS.md` what they must never do.

---

## 0. How to use this plan

One phase at a time, in order, following the workflow in `AGENTS.md`. If reality contradicts the plan (API changed, gem incompatible, spec gap), stop, explain, and propose a plan edit.

Suggested per-phase prompt:

> Read IMPLEMENTATION_PLAN.md §10 Phase N and the sections it references. Restate the goal, list the files and commit steps, and wait for my approval. Then implement step by step; after each step run the checks from AGENTS.md and propose a commit message.

---

## 1. Scope

### Must-have (mirrors the original assignment)
Budget ≈ 4–6 h. A well-reasoned logic part and an honest README matter more than polish.

1. Two models with an association: `Equipment` (resource, has `capacity`) and `Reservation` (has `start_date`, `end_date`).
2. Meaningful required fields and validations.
3. **Core:** a reservation can be saved only if at no instant the number of concurrent active reservations of the equipment exceeds its capacity. Must hold under concurrent requests.
4. CRUD: `index`, `show`, `new/create` for both models; `edit/update` for reservations. Equipment `show` lists its reservations.
5. CSS in separate files, no frontend framework, `.html.erb` views.
6. Rails 7+, MySQL. `bin/rails db:setup` produces a usable app with seed data, including a nearly full capacity situation.
7. README (in Czech): theme, DECISIONS (model design, where the logic lives, …), 2–3 sentences why the capacity algorithm works, what I would do differently with more time.
8. Pushed to GitHub, committed continuously: the commit history is part of the submission. Granular, green commits (see `AGENTS.md`).
9. No Docker.

### Out of scope (mention in README "more time" section)
Authentication and user accounts, payments, emails, admin panel, Equipment edit/destroy, per-unit (serial number) tracking, quantity > 1 per reservation, JS calendar widgets, API endpoints.

---

## 2. Decisions (final)

🧑 = decided by Šimon during design consultation; the rest were proposed defaults, confirmed by Šimon.

| ID | Decision |
|----|----------|
| D1 🧑 | Theme: climbing gear rental (ropes, harnesses, belay devices, shoes, crashpads). UI in English. |
| D2 🧑 | Dual ID: internal `bigint` auto-increment PK for joins/FKs, plus public `public_id` (UUID) used in all URLs to prevent enumeration. |
| D2a | `public_id` = UUIDv7 (`SecureRandom.uuid_v7`, time-ordered, so the unique index does not fragment like v4). Stored as `VARCHAR(36)` with `ascii_bin` collation (simple, readable in SQL console). `BINARY(16)` noted in README as the more compact alternative. |
| D3 🧑 | Turnaround buffer after every reservation (inspection of ropes/harnesses, cleaning, paperwork) before the unit can be rented again. |
| D3a | Buffer stored per equipment as `turnaround_minutes` (default 60, ropes 120 in seeds). Equipment has no edit action, so the value cannot change under existing reservations. |
| D4 🧑 | Concurrency control: one DB transaction + pessimistic row lock (`SELECT … FOR UPDATE`) on the **equipment row** as the serialization point. Concurrent bookings of the same equipment run one after another; different equipment never blocks each other. Capacity failure surfaces as a validation error rendered by the controller. |
| D5 🧑 | Capacity check: sweep line (event timeline) over the reservations overlapping the requested window. |
| D6 🧑 | Update goes through exactly the same locked path as create; the reservation being edited is excluded from the overlap set. |
| D7 | One reservation = one unit. `capacity` = number of physical units. Clothing-like items (shoes, harness sizes) are separate `Equipment` records per size. |
| D8 | Intervals are half-open: blocked interval of a reservation = `[start_date, end_date + turnaround)`. Touching intervals do not overlap. |
| D9 | `status` enum `active` / `cancelled` (string column). No destroy; a `cancel` action instead. Cancelled reservations never count toward capacity. |
| D10 | Booking logic lives in a service object `ReservationBooking` (`app/services/reservation_booking.rb`), the pure algorithm in a PORO `CapacityTimeline` (`app/models/capacity_timeline.rb`). Models keep field validations, controllers stay thin. |
| D11 | Equipment cannot be changed on reservation update (cancel and book again instead). Avoids locking two equipment rows and lock-ordering deadlocks. |
| D12 | Time: stored UTC, `config.time_zone = "Prague"` (Europe/Prague), default locale `:en` (no `rails-i18n` gem needed), displayed in the Czech format `17. 11. 2026 14:30`. Times in 15-minute steps. Min duration 1 h, max 30 days. |
| D13 | No users. Reservation has `customer_name`, `customer_email`, optional `customer_phone`. The unguessable `public_id` URL works as a capability link (README point). |
| D14 | Tests: Minitest + fixtures (Rails default). No RSpec, no FactoryBot, no DatabaseCleaner. |
| D15 | Language: everything in English (code, comments, UI, validation messages, seeds, commits); only README in Czech. |
| D16 🧑 | "Nearest available slot" suggestion (Šimon's option A) and `Category` model are bonus phases, done only after the must-have phases are complete. |

---

## 3. Domain model and schema

### 3.1 `equipment` table (`Equipment` model; "equipment" is uncountable in Rails)

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | bigint PK | auto |
| `public_id` | string(36), `ascii_bin` | NOT NULL, unique index |
| `name` | string(120) | NOT NULL |
| `description` | text | nullable |
| `capacity` | integer | NOT NULL, CHECK `capacity > 0` |
| `turnaround_minutes` | integer | NOT NULL, default 60, CHECK `turnaround_minutes >= 0` |
| timestamps | | |

Model validations: `name` presence + length ≤ 120; `capacity` integer, 1..100; `turnaround_minutes` integer, 0..1440.
Association: `has_many :reservations, dependent: :restrict_with_error`.

### 3.2 `reservations` table

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | bigint PK | auto |
| `public_id` | string(36), `ascii_bin` | NOT NULL, unique index |
| `equipment_id` | bigint | NOT NULL, FK → equipment |
| `customer_name` | string(100) | NOT NULL |
| `customer_email` | string(255) | NOT NULL |
| `customer_phone` | string(30) | nullable |
| `start_date` | datetime | NOT NULL |
| `end_date` | datetime | NOT NULL, CHECK `end_date > start_date` |
| `status` | string(20) | NOT NULL, default `active` |
| timestamps | | |

Index for the overlap query: `(equipment_id, status, start_date)`.
Column names `start_date`/`end_date` follow the assignment even though they hold datetimes (README note).

Model validations:
- presence of all NOT NULL fields; `customer_email` format via `URI::MailTo::EMAIL_REGEXP`
- `end_date > start_date`; duration ≥ 1 h and ≤ 30 days; both times on a 15-minute boundary
- `start_date` in the future on create, and on update only if `start_date` changed
- an already finished or cancelled reservation is not editable
- once a reservation has started, `start_date` cannot change (extension of `end_date` is allowed)
- `equipment_id` cannot change after create (D11)
- **No capacity validation in the model.** Capacity is checked only inside `ReservationBooking`, under the lock.

### 3.3 Shared `public_id` behaviour
A concern (`HasPublicId`) used by both models: generates UUIDv7 before validation on create if blank, `to_param` returns `public_id`, `public_id` is readonly after create. Controllers look up records with `find_by!(public_id:)` so unknown IDs give a 404.

### 3.4 Bonus: `Category` (Phase B2)
`categories` (`public_id`, `name`, `slug`), `Equipment belongs_to :category, optional: false`, filter on equipment index. Justification for README: filtering, not decoration.

---

## 4. Booking algorithm (core)

### 4.1 Definitions
- Blocked interval of reservation `r`: `B(r) = [r.start_date, r.end_date + turnaround)`.
- Two reservations conflict in time iff their blocked intervals intersect: `a.start < b.blocked_end AND b.start < a.blocked_end`.
- Constraint: for every instant `t`, the number of active reservations `r` of the equipment with `t ∈ B(r)` ≤ `capacity`.

### 4.2 Why a naive "count overlaps" is wrong
Counting all reservations overlapping the new one over-rejects: capacity 2, A = 08–10, B = 12–14, new = 09–13. New overlaps both, so the naive count is 3 > 2, yet at no instant are more than 2 units used. The sweep line computes the real peak. This case must be a unit test and a seed scenario.

### 4.3 `CapacityTimeline` (pure Ruby, no DB)
Input: the candidate window `[from, to)` and a list of intervals `[start, end)` (already including turnaround).
Output: the maximum number of intervals simultaneously active at any instant **inside** `[from, to)`.
Spec:
1. Clip every interval to the window; drop empty ones.
2. Build events: `(start, +1)`, `(end, -1)`.
3. Sort by time; at equal time process `-1` before `+1` (half-open intervals, D8).
4. Running sum; the answer is the maximum running sum.

Only the peak inside the window matters: outside it nothing changes for the existing reservations. This also keeps the check correct if historical data were ever inconsistent (e.g. capacity lowered manually in DB).
Complexity O(n log n), n = reservations overlapping the window (small, thanks to the index).

### 4.4 `ReservationBooking` service
Public API: `ReservationBooking.new(reservation).call` → `true`/`false`; on failure the errors are on `reservation.errors` (capacity error on `:base`).
Used for both create and update; the controller assigns attributes first, then calls the service.

Protocol:
1. Return `false` early if `reservation.valid?` fails (no lock taken for invalid input).
2. Open a transaction.
3. **First statement in the transaction:** lock the equipment row (`SELECT … FOR UPDATE` by primary key).
   InnoDB's default REPEATABLE READ takes its read snapshot at the first *non-locking* read of the transaction. Because the lock is the first statement, the snapshot for the next query is taken after the lock is granted, i.e. after any competing booking has committed. A plain read before the lock would make the check see stale data. This ordering is load-bearing and must carry a code comment.
4. Load active reservations of the equipment whose blocked interval intersects the candidate's blocked interval, excluding the candidate itself (`id` may be nil on create).
5. Run `CapacityTimeline` over those intervals plus the candidate. If peak > `capacity`, add an error to `:base` (include the window and capacity), return `false` (transaction ends without writes).
6. Otherwise `save!` and return `true`.
7. Rescue `ActiveRecord::LockWaitTimeout` and `ActiveRecord::Deadlocked`: add a "system is busy, try again" error, return `false`. Do not retry silently in a loop.

Notes:
- Locking a row by primary key in InnoDB takes a record lock only (no gap locks), and every booking takes exactly one lock, so bookings cannot deadlock each other.
- Reads of reservations are plain (non-locking) on purpose: locking the range would add gap locks and deadlock risk for no benefit, the equipment lock already serializes writers.
- `cancel` does not need the lock: it only frees capacity.
- Every write of a reservation's dates, status `active` or equipment **must** go through this service (see GUARDRAILS.md).

### 4.5 Bonus: nearest available start (Phase B1)
When booking fails, offer the earliest start ≥ requested start where the same duration fits, prefilled into the form (option A), or go back (option B).
Claim for README: as the start moves later, a start can only become feasible when some existing blocked interval ends, so the candidates are the requested start and each `existing.blocked_end ≥ requested start`, checked in order with `CapacityTimeline`. Search horizon: 60 days. Read-only, no lock needed (the actual booking still goes through the service).

---

## 5. Routes, controllers, views

### 5.1 Routes
- `root` → `equipment#index`
- `resources :equipment, only: %i[index show new create]`, with nested `resources :reservations, only: %i[new create]`
- `resources :reservations, only: %i[index show edit update]` with member `patch :cancel`
- Uncountable gotcha: the index helper is `equipment_index_path`, the member helper `equipment_path(item)`.
- All `:id` / `:equipment_id` params carry `public_id`.

### 5.2 Controllers (thin, see AGENTS.md conventions)
- `EquipmentController`: `index` (name, capacity, units free now), `show` (detail + upcoming active reservations + past ones collapsed), `new/create`.
- `ReservationsController`: `index` (upcoming active first, then past/cancelled), `show`, `new/create` (nested, equipment preselected), `edit/update`, `cancel`.
- Failed create/update renders the form with 422 (required for Turbo to show errors); unknown `public_id` gives 404.

### 5.3 Views
- Layout with header (logo text, nav: Equipment, Reservations), flash messages, main container, footer.
- Shared `_form_errors` partial: error summary with `role="alert"`, linked to fields; `aria-invalid` and `aria-describedby` on invalid fields.
- Reservation form: `datetime-local` inputs with `step="900"`, values formatted for the input in Prague time.
- Display via `I18n.l` with the Czech format (`17. 11. 2026 14:30`).
- Equipment show: capacity, turnaround, upcoming reservations table, "Book" button.
- Reservation show: details, blocked-until time (end + turnaround) explained to the customer, edit and cancel buttons (cancel with `data-turbo-confirm`).

---

## 6. Localization and time
- `config/application.rb`: `config.time_zone = "Prague"` (maps to Europe/Prague). Default locale stays `:en`, so no extra gem.
- `config/locales/en.yml`: date/time formats in the Czech style (`date.formats.default: "%-d. %-m. %Y"`, `time.formats.default: "%-d. %-m. %Y %H:%M"`), model and attribute names, domain error messages.
- DST: durations are measured in absolute time (UTC), display is local. Add one test with a reservation spanning the last Sunday of October.

---

## 7. Styling
- Propshaft; plain CSS in `app/assets/stylesheets/application.css`, plus at most one more file if it grows. No Tailwind, no Sass, no dark mode.
- Look: minimal, lots of white space, one accent color, system font stack, cards for equipment, clear tables (inspired by mpb.com).
- Accessibility: WCAG AA contrast, visible `:focus-visible`, semantic HTML, labels on every input, skip link, `prefers-reduced-motion` respected.
- Responsive: mobile first, single breakpoint around 48rem; tables scroll horizontally inside a wrapper on small screens.

---

## 8. Seeds (`db/seeds.rb`)
- Idempotent: clears reservations and equipment first (safe because it is dev data).
- All times relative to "tomorrow" in Prague time so the data never expires.
- Future reservations are created **through `ReservationBooking`** (seeds exercise the real logic; raise if a booking fails). Past reservations use `save(validate: false)` with a comment.
- At the end, print a short guide to the console listing the scenarios below.
- Must also pass `bin/rails db:seed:replant` in the test env (a `bin/ci` step).

Equipment: Rope 60 m (cap 3, turnaround 120), Harness M (cap 4), GriGri (cap 2), Climbing shoes EU 42 (cap 2), Quickdraw set 12 pcs (cap 3), Helmet (cap 5), Crashpad (cap 1).

Scenarios:
| # | Equipment | Setup | What to try |
|---|-----------|-------|-------------|
| S1 | Crashpad, cap 1 | tomorrow 10:00–18:00 | 18:30 start is rejected (buffer), 19:00 is accepted |
| S2 | GriGri, cap 2 | 09:00–17:00 and 13:00–20:00 | 15:00–16:00 rejected (full), 10:00–12:00 accepted |
| S3 | Rope, cap 3 | three staggered bookings, 2 overlap at midday | nearly full: one more fits only in some windows |
| S4 | Shoes EU 42, cap 2 | A 08:00–10:00, B 12:00–14:00 | 09:00–13:00 accepted (sweep line vs naive count, §4.2) |
| S5 | Harness M | one cancelled booking in a window | cancelled booking does not block |
| S6 | Helmet | past reservations | listed as past, not editable |

---

## 9. Testing strategy

### 9.1 Unit: `CapacityTimeline`
Empty list; single interval; touching intervals (end == start → no overlap); nested intervals; identical intervals; tie ordering; peak outside the window ignored; the §4.2 case.

### 9.2 Models
Each validation from §3; `public_id` generation, uniqueness, immutability and `to_param`; DB CHECK constraints reject invalid rows inserted directly.

### 9.3 Service and integration
- Service: accept at capacity − 1, reject at capacity, buffer boundary (exactly at blocked end accepted, one step earlier rejected), cancelled ignored, other equipment ignored, update excludes itself, extension blocked by next reservation, extension allowed when free, DST case.
- Controllers: happy path create/update/cancel, 422 on capacity error with its message, 404 on unknown `public_id`, numeric ids do not resolve.

### 9.4 Concurrency test (the proof)
Separate file, `self.use_transactional_tests = false`, cleans up its own records in `teardown`.
- Equipment with capacity 1 (and a second case with capacity 3 and 2 already booked).
- N threads (N ≤ test DB pool size − 1; raise the test pool in `config/database.yml` if needed), each with its own connection (`connection_pool.with_connection`), all released together by a barrier (`Concurrent::CyclicBarrier`, concurrent-ruby ships with Rails).
- Each thread books the same window. Assert: exactly the free number of bookings succeeded, the rest failed with the capacity error, and the DB count of active reservations equals capacity.
- Make the race deterministic: expose a small seam in the service between the check and the write, and in the test slow it down (e.g. `sleep 0.2`) for all threads. With the lock the result is still correct; without it every thread passes the check.
- **Mutation check (manual, not committed):** temporarily remove the lock, run the test, confirm it fails, restore. Record the outcome in the README.
- **Mutation check result (2026-11-17):** with `Equipment.lock.find` replaced by `Equipment.find`, both tests failed: 8 of 8 simultaneous bookings succeeded instead of 1 (capacity 1 → 8 active reservations; capacity 3 with 2 booked → 10). With the lock restored: exactly 1 success and 7 capacity errors in each test. Only the winning thread reaches the delay before the write; the others see its commit and fail fast, so each test takes ≈ 0.3 s.

### 9.5 Checks
See `AGENTS.md` → Commands. `config/ci.rb` already has the system-test step commented out (no system tests planned); keep it that way.

---

## 10. Phases

Estimated total for must-have phases ≈ 4 h. Each bullet under a phase is one commit step (see `AGENTS.md` → Commits).

- [x] **Phase 0: Agent setup** (10 min)
  Add `AGENTS.md`, `CLAUDE.md`, `GUARDRAILS.md`, `IMPLEMENTATION_PLAN.md`.
  - `docs: add implementation plan and agent instructions`

- [x] **Phase 1: Time zone, formats, base layout** (15 min) → §6, §5.3 layout
  Accept: app boots, `I18n.l(Time.current)` prints `17. 11. 2026 14:30` style in Prague time.
  - `chore: set Prague time zone and Czech date/time formats` (application.rb, en.yml)
  - `feat: add base layout with navigation and flash messages` (layout, flash partial, stylesheet stub, root placeholder)

- [x] **Phase 2: Equipment model** (25 min) → §3.1, §3.3
  Accept: §9.2 tests for Equipment pass, `schema.rb` shows CHECK constraints and unique index.
  - `feat: add Equipment model with public UUID and DB constraints` (migration, `HasPublicId`, model, fixtures, tests)

- [x] **Phase 3: Reservation model** (30 min) → §3.2 (no capacity logic)
  - `feat: add Reservation model with time window validations` (migration, model, status enum, field/time validations, fixtures, tests; also `Equipment has_many :reservations, dependent: :restrict_with_error`, deferred from Phase 2)
  - `feat: restrict editing of started, finished and cancelled reservations` (edit rules, immutable equipment, tests)

- [x] **Phase 4: CapacityTimeline** (25 min) → §4.3, §9.1, test-first
  - `feat: add sweep-line capacity timeline`

- [x] **Phase 5: ReservationBooking service** (35 min) → §4.4, §9.3 service part
  - `feat: add locked reservation booking service` (create path: lock, overlap query, capacity error, tests)
  - `feat: support reservation updates in booking service` (exclude self, extension cases, tests)
  - `feat: handle lock timeouts and deadlocks in booking`

- [x] **Phase 6: Concurrency test** (25 min) → §9.4
  Manual mutation check afterwards; note the result for the README.
  - `test: prove booking is safe under concurrent requests` (seam, race test, test pool size if needed)

- [x] **Phase 7: Equipment UI** (25 min) → §5
  - `feat: add equipment index and detail pages` (routes, controller, views, controller tests; root → `equipment#index`, remove the Phase 1 `HomeController` placeholder and its test)
  - `feat: add equipment creation form`

- [x] **Phase 8: Reservation UI** (35 min) → §5
  - `feat: add reservation index and detail pages`
  - `feat: add reservation booking form` (nested new/create via the service, form partial, errors partial)
  - `feat: add reservation editing` (edit/update via the service)
  - `feat: add reservation cancellation`

- [ ] **Phase 9: Styling** (25 min) → §7
  - `style: add base styles and layout`
  - `style: style equipment and reservation pages`

- [ ] **Phase 10: Seeds** (20 min) → §8
  Verify with `bin/rails db:drop db:setup` (ask before dropping) and click through S1–S6.
  - `chore: add seed equipment`
  - `chore: add near-capacity seed scenarios`

- [ ] **Phase 11: README** (25 min) → §12
  Written by Šimon (Czech), agent may help with structure and proofreading only.
  - `docs: write README with decisions and algorithm explanation` (may be split per section)

### Bonus phases (only after Phase 11)
- [ ] **B1: Nearest available slot** → §4.5. `feat: suggest nearest available start time`
- [ ] **B2: Category** → §3.4. `feat: add equipment categories with filtering`
- [ ] **B3: Availability overview** on equipment show: free units per hour for the next 7 days (reuses `CapacityTimeline`). `feat: show equipment availability overview`
- [ ] **B4: GitHub Actions**: adjust the generated `.github/workflows/ci.yml` (pin `mysql:8.4` image, drop the `system-test` job). `ci: pin MySQL 8.4 and drop system-test job`

---

## 11. Definition of done
- Fresh clone → `bundle install` → `bin/rails db:setup` → `bin/rails server` works, seeds show S1–S6.
- All tests green, including the concurrency test; rubocop and brakeman clean.
- Every reservation write path goes through `ReservationBooking`.
- No numeric IDs in any URL.
- README complete; commit history consists of granular, green commits.

---

## 12. README outline (Czech, written by Šimon)
1. **Téma** – půjčovna lezeckého vybavení, proč (turnaround na kontrolu lan a úvazků).
2. **Jak spustit** – požadavky, `bin/rails db:setup`, scénáře S1–S6 k vyzkoušení.
3. **DECISIONS** – modely a dual ID, polootevřené intervaly a turnaround, umístění logiky (service + PORO), zámek na řádku vybavení a proč ne zámek rozsahu, proč se nemění vybavení při update, cancel místo destroy, čas a lokalizace.
4. **Proč algoritmus funguje** (2–3 věty) – zámek serializuje zápisy pro dané vybavení a snapshot vzniká až po jeho získání; sweep line počítá skutečné maximum souběžných výpůjček v okně nové rezervace, takže nepřijme rezervaci, která by kapacitu v kterémkoli okamžiku překročila, a neodmítne tu, která ji nepřekročí.
5. **Testy** – co pokrývají, jak concurrency test dokazuje správnost, výsledek mutační kontroly.
6. **Práce s AI** – jak byly použity Claude Code a Antigravity, co bylo rozhodnuto ručně (§2), jak byl výstup kontrolován.
7. **Co bych udělal jinak s více časem** – uživatelé a autentizace, BINARY(16) UUID, množství v rezervaci, sledování konkrétních kusů, ochrana proti snížení kapacity pod existující obsazenost, kalendářní UI, rate limiting.
