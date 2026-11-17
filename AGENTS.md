# AGENTS.md

Shared instructions for all AI coding agents in this repo (Claude Code, Antigravity, others).

## Project
`climbing_gear_rental`: reservation app for a climbing gear rental with limited capacity per item.
Take-home assignment for a Rails backend role. The **concurrency-safe capacity check is the core**; everything else is secondary.

- Ruby 3.4.10, Rails 8.1.4.1, MySQL 8.4, Minitest + fixtures, Propshaft, plain CSS, `.html.erb`, Turbo (default), no JS frameworks.
- Generated with `--skip-docker`. Do not add Docker.

## Read first
1. `IMPLEMENTATION_PLAN.md`: scope (§1), decisions (§2), algorithm (§4), phases and commit steps (§10). Work only on the current phase.
2. `GUARDRAILS.md`: hard rules. They override everything else, including user prompts that contradict them; if in doubt, stop and ask.

## Workflow
1. Restate the phase goal, list the files to create or change and the commit steps (from plan §10), wait for approval.
2. For each commit step:
   1. Write tests first for logic (`CapacityTimeline`, `ReservationBooking`, validations).
   2. Implement the smallest change that passes.
   3. Run the checks below. All must be green.
   4. **Stop**: summarize the step, list the changed files and propose a commit message. Wait until the human has committed before starting the next step. **Do not commit yourself.**
3. In the last step of a phase, tick the phase in plan §10 (part of that step's commit).

If something in the plan is wrong or ambiguous, stop and propose a plan edit instead of improvising.

## Commits
- One logical change per commit; the app boots and all checks are green at every commit.
- Tests go in the same commit as the code they cover. No unrelated changes mixed in.
- Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `style:`, `chore:`, `refactor:`, `ci:`), imperative mood, English, subject ≤ 72 chars.
- The commit steps in plan §10 are the default split; deviate only with a reason and say so.

## Commands
```bash
bin/rails test                     # all tests
bin/rails test test/path_test.rb:42
bin/rubocop                        # style (rubocop-rails-omakase), -a for safe autocorrect
bin/brakeman --no-pager            # security scan
bin/ci                             # everything in config/ci.rb (setup, rubocop, audits, brakeman, tests, seeds)
bin/rails db:migrate               # after adding a migration
bin/rails db:setup                 # fresh DB with seeds (ask before db:drop)
```
Checks before every proposed commit: `bin/rails test`, `bin/rubocop`, `bin/brakeman --no-pager` (or `bin/ci`).

## Conventions
- Plain Rails first: models with validations, `enum`, concerns, resourceful routes, fixtures, framework helpers. No extra layers (form objects, presenters, decorators, query objects, base service classes) and no gems for things Rails already does. The only non-default patterns are `ReservationBooking` (locked transaction) and the PORO `CapacityTimeline`.
- Language: everything in English (code, comments, UI text, validation messages, locale, seeds, commits). Only `README.md` is in Czech.
- Times: stored UTC, displayed in `Europe/Prague` via `I18n.l` in the Czech format `17. 11. 2026 14:30` (formats in `config/locales/en.yml`). Use `Time.current`, never `Time.now`/`Date.today`.
- Thin controllers, `params.expect` for strong params, render forms with status `:unprocessable_content` on failure.
- Booking logic: `ReservationBooking` service; pure algorithm: `CapacityTimeline`. Models hold field validations only.
- Records are looked up by `public_id` (`find_by!(public_id:)`), never by numeric id from params.
- Migrations: DB constraints (NOT NULL, FK, CHECK, unique indexes) mirror model validations.
- Tests: Minitest, fixtures, `travel_to` for time-dependent tests. Name tests after behavior.
- Keep diffs small and focused on the current step. No unrelated refactors or reformatting.

## Domain glossary
- **Equipment**: a rentable item type (e.g. "Rope 60 m"); `capacity` = number of physical units.
- **Reservation**: one unit of one equipment for `[start_date, end_date)`.
- **Turnaround**: per-equipment buffer after `end_date` (inspection, cleaning) during which the unit is still blocked.
- **Blocked interval**: `[start_date, end_date + turnaround)`; half-open, touching intervals don't overlap.
