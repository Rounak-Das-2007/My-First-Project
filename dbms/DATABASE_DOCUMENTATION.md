# RailFlow — Database Documentation

Companion reference to `README.md` and `ER_DIAGRAM.md`. Covers every table,
every routine, and the reasoning behind non-obvious design decisions.

---

## 1. Tables

### 1.1 `users`
Login/account identity. `role` gates who can do what (`ADMIN`, `STAFF`,
`CUSTOMER`); `account_status` gates whether the account can book at all —
`sp_book_ticket` rejects any user whose `account_status <> 'ACTIVE'`.
`email` is globally unique; `phone` is validated by
`chk_users_phone` (`^[+]?[0-9]{10,15}$`).

### 1.2 `passengers`
The person who actually travels — reusable across many bookings, and
optionally linked to a `users` row (`user_id` is nullable: a customer can
book for a spouse, child, or guest who has no account). `date_of_birth`
cannot be validated with a `CHECK` constraint (MySQL forbids non-deterministic
functions like `CURDATE()` there), so `trg_passengers_validate_dob_bi/bu`
enforce it instead. `(id_document_type, id_document_number)` is unique —
the same identity document cannot be registered as two different passenger
records.

### 1.3 `stations`
`station_code` is unique and indexed; `station_name`/`city` are indexed for
search. `status = 'INACTIVE'` is checked by `sp_book_ticket` before a booking
can use that station as source or destination.

### 1.4 `trains`
`train_number` is unique. `source_station_id`/`destination_station_id` are
two independent FKs to `stations`; `chk_train_source_dest_diff` forbids them
being equal.

### 1.5 `train_routes`
The ordered stop list for a train, independent of any specific calendar date.
`sequence_order` is unique per train (`uq_route_train_sequence`) and a
station may not appear twice on the same train's route
(`uq_route_train_station`). `chk_route_departure_after_arrival` prevents a
physically impossible halt. `sp_book_ticket` reads this table to confirm the
requested source/destination are both on the train's route and in the
correct order (`v_src_seq < v_dst_seq`).

### 1.6 `train_schedules`
One row per train per calendar journey date — the thing a passenger actually
books against. `(train_id, journey_date)` is unique, so a train cannot be
scheduled twice on the same day. `chk_schedule_arrival_after_departure`
guards chronology. `status` (`SCHEDULED`/`DELAYED`/`CANCELLED`/`COMPLETED`)
gates bookability in `sp_book_ticket`.

### 1.7 `coaches`
Physical coaches belonging to a train. `coach_number` unique per train;
`total_seats` must be positive. `status = 'INACTIVE'` coaches are excluded
from every seat search.

### 1.8 `seats`
Individual seats within a coach. `seat_number` unique per coach.
`seat_category` (`REGULAR`/`RAC`) drives the RAC-fallback logic in
`sp_book_ticket` — regular seats are always offered first
(`ORDER BY FIELD(seat_category, 'REGULAR', 'RAC')`). `status = 'INACTIVE'`
seats can never receive an allocation — enforced twice: once by
`sp_book_ticket`'s own `WHERE s.status = 'ACTIVE'` filter, and again,
independently, by `trg_seat_allocations_validate_bi`, which blocks *any*
insert (including a manual/administrative one) of an `ACTIVE` allocation
against an inactive seat or coach.

### 1.9 `fares`
The deterministic fare matrix: one active row per
`(train_id, coach_type, source_station_id, destination_station_id,
effective_from)`. `fn_calculate_fare` looks up the most recent row whose
validity window covers the journey date. All three fare components
(`base_fare`, `reservation_charge`, `gst_charge`) are non-negative by CHECK
constraint.

### 1.10 `pnr_counter`
A single-purpose, InnoDB auto-increment counter. `fn_generate_pnr` inserts a
throwaway row and reads back `LAST_INSERT_ID()`, so PNR uniqueness is
guaranteed by the storage engine's own auto-increment mechanism — no
retry-on-collision loop is needed anywhere.

### 1.11 `bookings`
The reservation header: one row per `sp_book_ticket` call, covering 1–6
passengers (`chk_booking_passengers_positive`). `pnr` is globally unique.
`booking_status` is a derived value, kept in sync by
`sp_recompute_booking_status` from the individual `booking_passengers.
passenger_status` values, and protected from being reverted out of
`CANCELLED`/`COMPLETED` by `trg_bookings_prevent_invalid_transition`.

### 1.12 `booking_passengers`
Junction between `bookings` and `passengers` — booking data (fare, route,
train) is stored once on `bookings` and never duplicated per passenger.
`(booking_id, passenger_id)` is unique: the same passenger cannot appear
twice in one booking. `passenger_status` is the per-passenger source of
truth that everything else (seat allocation, waiting list, refund
eligibility) hangs off of.

### 1.13 `seat_allocations`
Physical seat ↔ passenger ↔ journey link — see §2 below for the generated-
column design that makes double-booking structurally impossible while still
allowing seats to be legitimately re-allocated after a cancellation.

### 1.14 `payments`
Simulated payment records — `transaction_reference` is unique;
`amount` is non-negative; no real card data is ever stored, matching the
"never store CVV/PIN/card numbers" requirement.

### 1.15 `cancellations`
One row per cancelled *booking* (booking-level, not per-passenger — see
README §15). `UNIQUE(booking_id)` doubles as a hard guard against
double-cancellation, independent of the `sp_cancel_booking` procedure's own
status check.

### 1.16 `refunds`
Zero-or-one row per `cancellations` row (`UNIQUE(cancellation_id)`) — only
created when money had actually been paid. `refund_amount` is non-negative
by CHECK; the "cannot exceed amount paid" rule is enforced in
`fn_calculate_refund` and `sp_cancel_booking`, since it requires comparing
against another table and cannot be a table-local CHECK constraint.

### 1.17 `waiting_list`
`(schedule_id, coach_type, waitlist_position)` is unique — no two passengers
share a position. `(booking_passenger_id)` is unique — a passenger is queued
at most once. Rows are never deleted, only status-transitioned
(`WAITING → PROMOTED/CANCELLED/EXPIRED`), preserving history.

### 1.18 `notifications`
Simple inbox rows written by the triggers/procedures (booking cancellation,
waiting-list promotion, payment result). `booking_id` is nullable and
`ON DELETE SET NULL` since a notification can outlive... in practice bookings
are never deleted, but the design is defensive.

### 1.19 `audit_logs`
Append-only. `old_value`/`new_value` are `JSON` snapshots of just the fields
that changed, written by `trg_bookings_audit_au` (status transitions) and
`trg_cancellations_audit_ai` (new cancellations). `performed_by` is nullable
for system-initiated changes (e.g. a promotion triggered by someone else's
cancellation).

---

## 2. The Seat Double-Booking Guarantee, In Detail

This is the single most important integrity mechanism in the schema, so it's
worth spelling out precisely.

```sql
allocation_status ENUM('ACTIVE', 'RELEASED') NOT NULL DEFAULT 'ACTIVE',
active_seat_key BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN allocation_status = 'ACTIVE' THEN seat_id ELSE NULL END
) STORED,
active_bp_key BIGINT UNSIGNED GENERATED ALWAYS AS (
    CASE WHEN allocation_status = 'ACTIVE' THEN booking_passenger_id ELSE NULL END
) STORED,
CONSTRAINT uq_allocation_active_bp UNIQUE (active_bp_key),
CONSTRAINT uq_allocation_active_seat UNIQUE (schedule_id, active_seat_key),
```

- MySQL's `UNIQUE` index treats `NULL` as distinct from every other `NULL` —
  so any number of `RELEASED` rows (where the generated column is `NULL`)
  can coexist, preserving full booking/seat history forever.
- But the moment a second row tries to be `ACTIVE` for the *same*
  `(schedule_id, seat_id)` pair, the generated column evaluates to the same
  non-null value twice, and the `UNIQUE` index rejects the `INSERT` —
  regardless of which connection, transaction, or procedure attempted it.
- The symmetric `active_bp_key` does the same for "one passenger, one active
  seat at a time," while still permitting a *second, later* allocation row
  for the same passenger once their first one is `RELEASED` (this is exactly
  what happens when a RAC passenger is promoted to a regular seat — see
  `sp_promote_waiting_list`).
- This is combined with `SELECT ... FOR UPDATE SKIP LOCKED` in
  `sp_book_ticket`'s seat search: two concurrent transactions each lock a
  *different* candidate row and never block each other, but if they somehow
  raced onto the same seat, the UNIQUE constraint is the final, storage-
  engine-level backstop — not a `SELECT`-then-`INSERT` race condition.

**Caveat honestly noted**: `ON UPDATE CASCADE` cannot be used on
`seat_allocations.seat_id` or `.booking_passenger_id` because MySQL refuses
to create a foreign key with a cascading action on a column that a stored
generated column also depends on (verified directly — MySQL raises
`ERROR 1215 (HY000): Cannot add foreign key constraint` when attempted).
Both FKs use `ON UPDATE RESTRICT` instead, which is a non-issue in practice
since `seat_id` and `booking_passenger_id` are surrogate auto-increment keys
that are never updated.

---

## 3. Functions (`06_functions.sql`)

| Function | Signature | Notes |
|---|---|---|
| `fn_generate_pnr()` | `() → CHAR(10)` | `MODIFIES SQL DATA`. `PNR` + 7-digit zero-padded sequence, e.g. `PNR0000001`. |
| `fn_calculate_fare(...)` | `(train_id, coach_type, source, destination, journey_date) → DECIMAL(10,2)` | `READS SQL DATA`. Returns `base_fare + reservation_charge + gst_charge` for the active, date-valid fare row. |
| `fn_available_seats(...)` | `(schedule_id, coach_id) → INT` | `READS SQL DATA`. Active seats minus active allocations. |
| `fn_occupancy_percentage(...)` | `(schedule_id, coach_id) → DECIMAL(5,2)` | `READS SQL DATA`. |
| `fn_calculate_refund(...)` | `(fare_paid, departure_datetime, cancellation_datetime) → DECIMAL(10,2)` | `DETERMINISTIC`. Tiered cancellation-charge policy (see below). Never negative, never exceeds `fare_paid`. |

### Refund policy (`fn_calculate_refund`)

| Time before departure | Cancellation charge | Refund |
|---|---|---|
| ≥ 48 hours | 5% | 95% |
| 24–48 hours | 25% | 75% |
| 4–24 hours | 50% | 50% |
| < 4 hours / after departure | 100% | 0% |

---

## 4. Procedures (`07_procedures.sql`)

### `sp_book_ticket`
```
IN  p_user_id, p_train_id, p_schedule_id, p_source_station_id,
    p_destination_station_id, p_coach_type, p_passengers_json (JSON array)
OUT p_pnr, p_booking_status, p_total_fare
```
Validation order: user exists & active → train exists & active → schedule
exists, belongs to that train, is bookable, and is today-or-later → source ≠
destination → both stations exist & active → both stations on the train's
route, in the correct order → passenger count 1–6 → fare exists for the
route/class/date. Only after every check passes does it `START TRANSACTION`.
Per-passenger: validate the passenger exists & is active, insert the
`booking_passengers` row, then lock-and-claim one seat
(`FOR UPDATE SKIP LOCKED`, regular seats preferred over RAC); if none is
free, insert a `waiting_list` row instead. Finally derives and writes the
overall `booking_status` and commits.

### `sp_process_payment`
```
IN  p_booking_id, p_amount, p_payment_method, p_transaction_reference,
    p_simulate_success (boolean)
```
Rejects a cancelled booking or a mismatched amount before writing anything;
inserts the `payments` row and updates `bookings.payment_status` inside one
transaction.

### `sp_cancel_booking`
```
IN  p_pnr, p_cancelled_by, p_reason
OUT p_refund_amount
```
Rejects an unknown PNR or an already-cancelled booking before writing
anything. Computes the refund, writes `cancellations` (+ `refunds` if
anything was paid), marks every passenger `CANCELLED`, marks any still-
`WAITING` waitlist rows for this booking `CANCELLED`, releases every active
seat allocation via a cursor, and calls `sp_promote_waiting_list` once per
seat freed — all inside one transaction, so a failure partway through leaves
no partial cancellation.

### `sp_promote_waiting_list`
```
IN p_schedule_id, p_coach_type, p_vacated_coach_id, p_vacated_seat_id,
   p_vacated_seat_category
```
Not meant to be called standalone in normal operation (it assumes an open
transaction, typically `sp_cancel_booking`'s). Implements the two-level
RAC-then-waitlist cascade described in README §7.4.

### `sp_recompute_booking_status`
```
IN p_booking_id
```
Derives `bookings.booking_status` from the distribution of its
`booking_passengers.passenger_status` values: all cancelled → `CANCELLED`;
any waitlisted → `WAITLISTED`; else any RAC → `RAC`; else `CONFIRMED`. A
no-op on already-`CANCELLED` bookings (they're closed).

---

## 5. Triggers (`08_triggers.sql`)

| Trigger | Event | Purpose |
|---|---|---|
| `trg_passengers_validate_dob_bi` / `_bu` | `BEFORE INSERT`/`UPDATE` on `passengers` | DOB not in the future, not implausibly old — can't be a CHECK constraint (non-deterministic `CURDATE()`). |
| `trg_bookings_prevent_invalid_transition` | `BEFORE UPDATE` on `bookings` | Blocks reverting a `CANCELLED`/`COMPLETED` booking to any earlier state, from *any* writer. |
| `trg_bookings_audit_au` | `AFTER UPDATE` on `bookings` | Logs status/payment-status transitions to `audit_logs`. |
| `trg_cancellations_audit_ai` | `AFTER INSERT` on `cancellations` | Logs the financial detail of every cancellation. |
| `trg_payments_notify_au` / `_ai` | `AFTER UPDATE`/`INSERT` on `payments` | Writes a `notifications` row when a payment resolves to `SUCCESS`/`FAILED`. |
| `trg_seat_allocations_validate_bi` | `BEFORE INSERT` on `seat_allocations` | Blocks any `ACTIVE` allocation against an inactive seat or inactive coach — independent backstop beyond `sp_book_ticket`'s own filtering. |

Deliberately **not** implemented as triggers: anything the procedures
already guarantee transactionally (seat release on cancellation, waiting-
list promotion) — adding a redundant trigger for those would create a second
code path for the same rule and risk the two disagreeing.

---

## 6. Normalization Notes

- **1NF**: every column holds a single atomic value; multi-valued data
  (a booking's several passengers, a train's several route stops) lives in
  its own child table.
- **2NF**: every non-key column depends on the *whole* primary key. The
  clearest example is `booking_passengers.fare_component`, which is stored
  per `(booking_id, passenger_id)` rather than assuming it can be derived
  from `booking_id` alone (fares can legitimately differ per passenger, e.g.
  concession fares — the schema supports that even though the demo data
  doesn't exercise it).
- **3NF**: no non-key column depends on another non-key column.
  `bookings.total_fare` is a deliberate, documented exception — a sum
  derived from `booking_passengers.fare_component` at booking time — kept as
  a stored value (not recomputed on every read) because it is a *financial
  record of what was actually charged*, which must not silently change if
  fares are updated later. This is intentional denormalization for
  historical-accuracy reasons, not an oversight.
- `seat_allocations.active_seat_key` / `active_bp_key` are also, strictly
  speaking, derived (from `allocation_status` + `seat_id`/`booking_passenger_id`),
  but they exist purely as an indexing mechanism to let a `UNIQUE` constraint
  express a business rule the engine can't otherwise express declaratively —
  not as a shortcut around normalization.

---

## 7. Index Rationale (`04_indexes.sql`)

Every secondary index was added because a specific query pattern in the
views, reports, or procedures needs it — not speculatively:

- `idx_bookings_journey_date`, `idx_schedules_journey_date` — every
  availability/report query filters by date.
- `idx_fares_lookup` — the exact composite key `fn_calculate_fare` filters
  on, so its `SELECT` can use an index range scan instead of a full scan.
- `idx_alloc_schedule_coach` — `fn_available_seats`/`fn_occupancy_percentage`
  filter on exactly this triple on every call, and these functions are
  called once per coach per schedule in `available_seats_view`.
- `idx_waitlist_schedule_class_status` — `sp_promote_waiting_list`'s
  `ORDER BY wl.waitlist_position` under this exact filter is the single
  hottest query in the cancellation path.

`PRIMARY KEY`, `UNIQUE`, and `FOREIGN KEY` columns already carry an index
automatically in InnoDB and are not duplicated here.
