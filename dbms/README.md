# RailFlow — Railway Train Ticket Reservation & Management Database

A production-style, **database-only** railway reservation system built entirely in
**MySQL 8.0+**. There is no application layer: every business rule — booking, seat
allocation, fare calculation, cancellation, refund, and waiting-list promotion —
is implemented and enforced inside the database itself, through stored procedures,
functions, triggers, and constraints.

All data shipped with this project (stations, trains, routes, users, bookings, etc.)
is **fictional demo/sample data** styled after the Indian railway network for
realism. It does not represent live railway information.

---

## 1. Project Overview

RailFlow models the full lifecycle of a railway ticket:

`search → book → allocate a seat (or RAC / waiting list) → pay → travel → cancel → refund → re-allocate to the next passenger in line`

Every one of those steps is a real, tested operation against a live MySQL 8.0
instance — not a schema diagram with untested procedures. See §11 for exactly
what was verified and how.

## 2. Objectives

- Model a railway reservation domain to Third Normal Form wherever practical.
- Guarantee data integrity with the database itself as the final authority —
  not application code — using PRIMARY/FOREIGN KEYs, UNIQUE constraints, CHECK
  constraints, generated columns, and triggers.
- Make double-booking of a seat structurally impossible, not just unlikely.
- Implement real transactional business logic (booking, cancellation, refund,
  waiting-list promotion) as atomic, all-or-nothing stored procedures.
- Provide reporting views and analytical queries useful to real operations and
  finance teams.

## 3. Architecture

19 tables, organized into five layers:

| Layer | Tables |
|---|---|
| Identity | `users`, `passengers` |
| Network & Inventory | `stations`, `trains`, `train_routes`, `train_schedules`, `coaches`, `seats`, `fares` |
| Reservation | `bookings`, `booking_passengers`, `seat_allocations`, `waiting_list` |
| Money | `payments`, `cancellations`, `refunds` |
| Operations | `notifications`, `audit_logs`, `pnr_counter` |

See `ER_DIAGRAM.md` for the full entity-relationship diagram and
`DATABASE_DOCUMENTATION.md` for a column-by-column reference.

## 4. Requirements

- MySQL **8.0.17+** (generated columns, window-function-free design but relies
  on functional/generated-column features available from 8.0.13; CHECK
  constraints enforced from 8.0.16 — 8.0.17+ recommended, tested on 8.0.46).
- A user with rights to create databases, tables, routines (procedures,
  functions, triggers), and to run `SET GLOBAL log_bin_trust_function_creators`
  (or an equivalent already-configured server).
- No frontend, backend, ORM, or other language runtime is required or used.

## 5. Installation & Execution Order

Run the files in numeric order from the `sql/` directory. Each file is
idempotent against a **fresh** database (re-running against a populated
database will hit expected UNIQUE-constraint errors — that is by design,
see `12_test_cases.sql`).

```bash
mysql -u root -p < sql/01_create_database.sql
mysql -u root -p < sql/02_create_tables.sql
mysql -u root -p < sql/03_constraints.sql
mysql -u root -p < sql/04_indexes.sql
mysql -u root -p < sql/05_seed_data.sql
mysql -u root -p < sql/06_functions.sql
mysql -u root -p < sql/07_procedures.sql
mysql -u root -p < sql/08_triggers.sql
mysql -u root -p < sql/09_views.sql
mysql -u root -p < sql/10_reports.sql
mysql -u root -p < sql/11_transactions.sql
mysql -u root -p --force < sql/12_test_cases.sql   # --force: negative tests are SUPPOSED to fail
mysql -u root -p < sql/13_cleanup.sql               # optional: removes only the 12_test_cases.sql artifacts
```

`06_functions.sql` issues `SET GLOBAL log_bin_trust_function_creators = 1;`
so that functions which read/write data can be created under binary logging
without requiring the (less safe) `DETERMINISTIC` label on functions that
aren't truly deterministic. This requires the `SUPER` (or
`SYSTEM_VARIABLES_ADMIN`) privilege; a typical local/root installation has it.

Or, on a Unix shell, run the whole sequence in one go:

```bash
for f in sql/0[1-9]*.sql sql/1[01]*.sql; do mysql -u root -p railflow_db < "$f" || break; done
mysql -u root -p --force railflow_db < sql/12_test_cases.sql
```

### File-by-file purpose

| File | Purpose |
|---|---|
| `01_create_database.sql` | Creates `railflow_db` (utf8mb4). |
| `02_create_tables.sql` | All 19 tables — PK / FK / UNIQUE / NOT NULL / DEFAULT. |
| `03_constraints.sql` | CHECK constraints for every business rule that can be expressed declaratively. |
| `04_indexes.sql` | Secondary indexes matched to real query patterns. |
| `05_seed_data.sql` | Reference/master demo data only (users, passengers, stations, trains, routes, schedules, coaches, seats, fares). |
| `06_functions.sql` | `fn_generate_pnr`, `fn_calculate_fare`, `fn_available_seats`, `fn_occupancy_percentage`, `fn_calculate_refund`. |
| `07_procedures.sql` | `sp_book_ticket`, `sp_process_payment`, `sp_cancel_booking`, `sp_promote_waiting_list`, `sp_recompute_booking_status`. |
| `08_triggers.sql` | DOB validation, booking-status-transition guard, audit logging, payment notifications, seat/coach-active guard. |
| `09_views.sql` | 8 reporting views (see §8). |
| `10_reports.sql` | 18 ready-to-run analytical SELECT queries (see §9). |
| `11_transactions.sql` | The **actual demo transactional dataset** — bookings, payments, cancellations, refunds, and waiting-list activity, produced by *calling the real stored procedures*, not by hand-inserting rows. |
| `12_test_cases.sql` | 14 positive tests + 20 negative tests. |
| `13_cleanup.sql` | Removes only what `12_test_cases.sql` created. |

## 6. Schema Overview

- **Money** is always `DECIMAL(10,2)`. Never `FLOAT`/`DOUBLE`.
- **Dates** are `DATE`; **date+time** are `DATETIME` or `TIMESTAMP` as appropriate.
- **Fixed value sets** (roles, statuses, coach/seat types) use `ENUM`.
- Every table is `InnoDB`.
- `created_at`/`updated_at` are maintained automatically by
  `DEFAULT CURRENT_TIMESTAMP` / `ON UPDATE CURRENT_TIMESTAMP` — no trigger
  needed for that alone.

## 7. Major Operations

### 7.1 Booking (`sp_book_ticket`)
Validates the customer, train, schedule, route direction, and station status;
computes fare via `fn_calculate_fare`; then, **per passenger**, locks and
claims one available seat with `SELECT ... FOR UPDATE SKIP LOCKED` — trying a
REGULAR seat first, then an RAC-designated seat, and finally falling back to
the waiting list if the class is completely full. The whole operation is one
transaction: either every passenger gets a definitive status (CONFIRMED / RAC
/ WAITLISTED) and the booking commits, or nothing is written at all.

### 7.2 Payment (`sp_process_payment`)
Records a simulated payment (no real card data is ever stored) and updates
the booking's `payment_status`. Rejects payment against an already-cancelled
booking or an amount that does not match the booking total.

### 7.3 Cancellation (`sp_cancel_booking`)
Given a PNR: validates it hasn't already been cancelled, computes the refund
via `fn_calculate_refund` (a tiered, time-to-departure-based policy), writes
`cancellations` and `refunds` records, marks every passenger `CANCELLED`,
releases every active seat allocation, and — for **each seat that becomes
free** — calls `sp_promote_waiting_list`.

### 7.4 Waiting-list / RAC promotion (`sp_promote_waiting_list`)
This is the most realistic piece of business logic in the project:

1. If a **REGULAR** seat was vacated, the earliest RAC passenger for that
   schedule/class is promoted into it (CONFIRMED), which frees their old RAC
   seat.
2. Whichever seat is now free (the original vacated seat if there was no RAC
   passenger to promote, or the freed RAC seat otherwise) is given to the
   earliest **WAITING** passenger, who becomes CONFIRMED or RAC accordingly.
3. `sp_recompute_booking_status` re-derives each affected booking's overall
   status from its passengers' individual statuses.
4. A notification is written for the promoted passenger.

This cascade was verified end-to-end against a real MySQL instance (see §11).

## 8. Views

| View | Purpose |
|---|---|
| `available_seats_view` | Live availability & occupancy per coach per schedule. |
| `booking_details_view` | One row per booking with train/route context. |
| `passenger_booking_history_view` | Every journey a passenger has booked. |
| `train_occupancy_view` | Whole-train occupancy per schedule. |
| `route_revenue_view` | Revenue per source/destination pair. |
| `daily_revenue_view` | Successful-payment revenue by calendar day. |
| `waiting_list_status_view` | Current waiting-list queue per schedule/class. |
| `cancellation_summary_view` | Cancellation + refund detail per booking. |

## 9. Reports (`10_reports.sql`)

18 analytical queries: booking funnel, gross/refund/net revenue, train and
coach occupancy, route popularity, station-wise passenger volume, class-wise
revenue, daily and monthly revenue trends, top routes, most-used trains,
cancellation rate, waiting-list conversion rate, RAC occupancy, and payment
method mix.

## 10. Testing (`12_test_cases.sql`)

**14 positive tests** (T01–T14) exercise every entity's happy path in order,
finishing with a full booking → payment → cancellation → refund cycle.

**20 negative tests** (N01–N20) attempt: duplicate email, invalid phone,
duplicate station code, duplicate train number, identical source/destination,
a route pointing at a non-existent station, a reversed source/destination in
a booking, a booking against a completed (past) schedule, a booking against
an inactive train, a booking through an inactive station, a direct insert of
an allocation onto an inactive seat, a direct duplicate active-seat
allocation, a negative fare, a duplicate PNR, cancelling an already-cancelled
booking, a negative refund, an inactive user attempting to book, a duplicate
passenger within one booking, a future date of birth, and reverting a cancelled booking's status. **Every one
of the 20 fails**, verified by actually running the file with
`mysql --force` and inspecting each error against its expected `ERROR`/`SIGNAL`
message. The payment procedure also rejects repeated successful/refunded
payments, and cancellation is restricted to the booking owner or an
administrator/staff user.

Run with `--force` so MySQL continues past the *expected* errors instead of
aborting the script at the first one.

## 11. What Was Actually Verified (not just written)

This project was built by executing every file against a live MySQL 8.0.46
server in a fresh container, in dependency order, and iterating on real
errors until the whole pipeline ran clean. Specifically verified:

- All 19 tables create with zero FK/constraint errors from empty.
- Booking 9 passengers into an 8-seat coach (6 REGULAR + 2 RAC seats)
  produced exactly 6 CONFIRMED, 2 RAC, 1 WAITLISTED — computed by the
  procedure, not hand-set.
- Cancelling a CONFIRMED booking correctly promoted the earliest RAC
  passenger to CONFIRMED (reassigned onto the vacated regular seat) **and**
  promoted the earliest WAITING passenger into the RAC seat that freed up —
  a genuine two-level cascade, confirmed by inspecting `seat_allocations`,
  `booking_passengers`, and `waiting_list` afterward.
- A refund on a paid, cancelled booking calculated correctly against the
  time-to-departure policy tiers (e.g. 5% charge when cancelling ≥48h
  before departure).
- All 20 negative tests fail with the documented error, and change nothing.
- A full integrity audit (orphan rows, duplicate PNR/train-number/
  station-code/seat, negative fares/refunds, invalid booking states, invalid
  route ordering, identical source/destination) returned **zero** violations
  on the populated database.
- `13_cleanup.sql` removes exactly the rows `12_test_cases.sql` created and
  nothing else — confirmed by row counts before/after.

## 12. Integrity Strategy

- Referential integrity: every FK is `RESTRICT` on delete (history is never
  silently destroyed) except where `CASCADE`/`SET NULL` is the only sane
  choice (e.g. deleting a train cascades to its own routes/coaches/schedules;
  deleting a user's account nulls their passenger link rather than deleting
  the passenger).
- Uniqueness: emails, phone-shaped values, station codes, train numbers,
  PNRs, transaction references, document numbers, and coach/seat numbering
  within their parent are all enforced with `UNIQUE` constraints, not just
  application checks.
- **The seat double-booking guarantee is structural, not procedural.**
  `seat_allocations.active_seat_key` is a generated column that equals
  `seat_id` while the allocation is `ACTIVE` and `NULL` once `RELEASED`.
  `UNIQUE (schedule_id, active_seat_key)` means MySQL itself refuses a second
  simultaneous ACTIVE allocation of the same seat on the same journey —
  released allocations (`NULL`) don't collide, so history is preserved and
  the seat can be legitimately re-allocated later.
- Business rules that can't be expressed as CHECK constraints (because MySQL
  forbids non-deterministic functions like `CURDATE()` in them) are enforced
  by `BEFORE INSERT/UPDATE` triggers instead (passenger date of birth).
- `sp_book_ticket`'s per-passenger seat search uses
  `SELECT ... FOR UPDATE SKIP LOCKED` inside an open transaction: two
  concurrent bookings racing for seats in the same coach will each lock and
  claim a *different* free seat rather than blocking each other or reading
  stale availability; the UNIQUE constraint above is the final backstop if
  they somehow tried to claim the same seat anyway.

## 13. Transaction Strategy

Every multi-table write path is wrapped in `START TRANSACTION … COMMIT`, with
a procedure-level `DECLARE EXIT HANDLER FOR SQLEXCEPTION` that issues
`ROLLBACK` and re-raises (`RESIGNAL`) on any error, so a failure partway
through booking, payment, or cancellation leaves **no partial rows** behind:

- `sp_book_ticket` — booking header, every passenger, every seat allocation
  or waiting-list entry are all-or-nothing.
- `sp_process_payment` — payment row + booking status update.
- `sp_cancel_booking` — cancellation, refund, passenger-status updates, seat
  releases, and the resulting waiting-list promotion cascade are one unit.

## 14. Security

- No plain-text passwords: `users.password_hash` is a placeholder hash value
  (this project has no application layer to hash real passwords with, so the
  seed data uses clearly-fake placeholder strings).
- No card numbers, CVVs, or PINs are ever stored; `payments` stores only a
  simulated `transaction_reference`, amount, and method.
- Roles (`ADMIN`, `CUSTOMER`, `STAFF`) are modeled in `users.role`; a real
  deployment would pair this with MySQL-level account privileges (e.g. a
  `railflow_app` account with `EXECUTE` on the procedures/functions but no
  direct table DML) — noted here as the intended next step, since granting
  users/roles is an environment-specific operational concern outside a
  portable SQL script.

## 15. Known Simplifications (documented, not hidden)

- RAC is modeled as a small number of dedicated RAC-category seats per coach
  (one seat per RAC passenger) rather than Indian Railways' real "two RAC
  passengers share one side-lower berth" rule — implementing genuine 2-per-berth
  sharing would require a second seat-sharing dimension that adds
  substantial complexity for demo purposes without changing the database
  concepts being demonstrated (locking, cascading promotion, transactional
  integrity).
- Cancellation operates at the whole-booking level (all passengers on a PNR
  cancel together), not per individual passenger within a multi-passenger
  booking; the schema (`booking_passengers.passenger_status`) supports
  per-passenger status and could be extended to a per-passenger cancellation
  procedure following the same pattern as `sp_cancel_booking`.
