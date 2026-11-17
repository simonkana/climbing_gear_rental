# GUARDRAILS.md

Hard rules for every agent. They are not negotiable within a session. If a task seems to require breaking one, stop and ask the human.

## Core invariant: capacity
1. Every write that creates a reservation or changes its `start_date`, `end_date`, `status` to `active`, or `equipment_id` goes through `ReservationBooking`. No `update_column(s)`, `update_all`, `insert_all`, `upsert`, raw SQL or `save(validate: false)` on reservations outside it. Only exceptions: past reservations in `db/seeds.rb` (with a comment), test fixtures, and tests that deliberately insert invalid rows to prove DB constraints.
2. Never remove, weaken, reorder or move the equipment row lock in `ReservationBooking`. The lock must stay the **first statement** of the transaction (InnoDB snapshot timing, see plan §4.4).
3. Never add a capacity check to model validations or callbacks as a replacement for the locked check.
4. Never change transaction isolation level, lock strategy or the overlap definition (half-open intervals with turnaround) without an explicit plan edit approved by the human.
5. Cancelled reservations never count toward capacity.

## Tests
6. Never delete, skip, or loosen an existing test (assertions, counts, time windows) to make a change pass. If a test seems wrong, explain why and ask.
7. The concurrency test must stay non-transactional, multi-threaded and barrier-synchronized. Do not replace it with a sequential test or a stubbed lock. Removing the lock is a local, manual mutation check only; never commit it.

## Scope and dependencies
8. Work only on the current phase of `IMPLEMENTATION_PLAN.md`. No unrequested features, refactors or renames.
9. Ask before adding, removing or upgrading any gem or npm package. Never add RSpec, FactoryBot, DatabaseCleaner, Devise, Tailwind, Sass build tools, React or any JS framework.
10. Do not add Docker, Kamal deploy config changes or CI services beyond what the plan lists.
11. Decisions in plan §2 are final; changing one needs a plan edit approved by the human.

## Data, security, git
12. Never expose numeric ids in URLs, forms, or rendered HTML; use `public_id`. `public_id`, `status`, `equipment_id` are never mass-assignable from params.
13. Never edit `config/credentials*`, `config/master.key` or any secret, never print secrets, never commit `.env` files.
14. Never run `db:drop`, `db:reset`, `db:schema:load` against development, or any destructive shell command (`rm -rf`, `git reset --hard`, `git push --force`, `git clean`) without explicit approval.
15. Do not commit, push, rebase or amend. Propose the commit message; the human commits.
16. Do not edit an already-run migration; add a new one.

## Communication
17. Report honestly: what was done, what was not, which checks ran and their result. Never claim tests pass without running them.
18. If unsure about Rails 8.1 or MySQL 8.4 behaviour, say so and check the official docs instead of guessing.
