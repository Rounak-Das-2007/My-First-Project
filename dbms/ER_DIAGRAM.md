# RailFlow — Entity-Relationship Diagram

Mermaid ER diagram of all 19 tables. `||--o{` reads "one ... to zero-or-many",
`||--||` reads "one to exactly one". PK = primary key, FK = foreign key,
UK = unique key.

```mermaid
erDiagram
    USERS ||--o{ PASSENGERS : "may link"
    USERS ||--o{ BOOKINGS : places
    USERS ||--o{ CANCELLATIONS : cancels
    USERS ||--o{ NOTIFICATIONS : receives
    USERS ||--o{ AUDIT_LOGS : "performs (nullable)"

    STATIONS ||--o{ TRAINS : "source of"
    STATIONS ||--o{ TRAINS : "destination of"
    STATIONS ||--o{ TRAIN_ROUTES : "stop on"
    STATIONS ||--o{ FARES : "source of"
    STATIONS ||--o{ FARES : "destination of"
    STATIONS ||--o{ BOOKINGS : "source of"
    STATIONS ||--o{ BOOKINGS : "destination of"

    TRAINS ||--o{ TRAIN_ROUTES : follows
    TRAINS ||--o{ TRAIN_SCHEDULES : runs
    TRAINS ||--o{ COACHES : has
    TRAINS ||--o{ FARES : priced
    TRAINS ||--o{ BOOKINGS : "booked on"

    TRAIN_SCHEDULES ||--o{ BOOKINGS : "journey on"
    TRAIN_SCHEDULES ||--o{ SEAT_ALLOCATIONS : "seats for"
    TRAIN_SCHEDULES ||--o{ WAITING_LIST : "queue for"

    COACHES ||--o{ SEATS : contains
    COACHES ||--o{ SEAT_ALLOCATIONS : "allocated in"

    SEATS ||--o{ SEAT_ALLOCATIONS : "allocated as"

    PASSENGERS ||--o{ BOOKING_PASSENGERS : travels
    BOOKINGS ||--o{ BOOKING_PASSENGERS : contains
    BOOKINGS ||--o{ PAYMENTS : "paid via"
    BOOKINGS ||--|| CANCELLATIONS : "cancelled by (0/1)"
    BOOKINGS ||--o{ NOTIFICATIONS : triggers
    BOOKINGS ||--o{ REFUNDS : "refunded via"

    BOOKING_PASSENGERS ||--|| SEAT_ALLOCATIONS : "seated by (0/1 active)"
    BOOKING_PASSENGERS ||--|| WAITING_LIST : "queued as (0/1)"

    CANCELLATIONS ||--|| REFUNDS : "produces (0/1)"

    USERS {
        bigint user_id PK
        varchar full_name
        varchar email UK
        varchar phone
        varchar password_hash
        enum role
        enum account_status
        timestamp created_at
        timestamp updated_at
    }

    PASSENGERS {
        bigint passenger_id PK
        bigint user_id FK "nullable"
        varchar full_name
        date date_of_birth
        enum gender
        varchar phone
        varchar email
        enum id_document_type
        varchar id_document_number "UK with id_document_type"
        enum status
    }

    STATIONS {
        int station_id PK
        varchar station_code UK
        varchar station_name
        varchar city
        varchar state
        enum status
    }

    TRAINS {
        int train_id PK
        varchar train_number UK
        varchar train_name
        enum train_type
        int source_station_id FK
        int destination_station_id FK
        enum status
    }

    TRAIN_ROUTES {
        bigint route_id PK
        int train_id FK
        int station_id FK
        smallint sequence_order "UK with train_id"
        time arrival_time
        time departure_time
        decimal distance_from_origin_km
        smallint halt_minutes
    }

    TRAIN_SCHEDULES {
        bigint schedule_id PK
        int train_id FK
        date journey_date "UK with train_id"
        datetime departure_datetime
        datetime arrival_datetime
        enum status
    }

    COACHES {
        bigint coach_id PK
        int train_id FK
        varchar coach_number "UK with train_id"
        enum coach_type
        smallint total_seats
        enum status
    }

    SEATS {
        bigint seat_id PK
        bigint coach_id FK
        varchar seat_number "UK with coach_id"
        enum seat_type
        enum seat_category "REGULAR or RAC"
        enum status
    }

    FARES {
        bigint fare_id PK
        int train_id FK
        enum coach_type
        int source_station_id FK
        int destination_station_id FK
        decimal base_fare
        decimal reservation_charge
        decimal gst_charge
        date effective_from
        date effective_to
        enum status
    }

    PNR_COUNTER {
        bigint counter_id PK
    }

    BOOKINGS {
        bigint booking_id PK
        char pnr UK
        bigint user_id FK
        int train_id FK
        bigint schedule_id FK
        int source_station_id FK
        int destination_station_id FK
        enum coach_type
        date journey_date
        tinyint total_passengers
        decimal total_fare
        enum booking_status
        enum payment_status
    }

    BOOKING_PASSENGERS {
        bigint booking_passenger_id PK
        bigint booking_id FK "UK with passenger_id"
        bigint passenger_id FK
        tinyint age_at_booking
        decimal fare_component
        enum passenger_status
    }

    SEAT_ALLOCATIONS {
        bigint allocation_id PK
        bigint booking_passenger_id FK
        bigint schedule_id FK
        bigint coach_id FK
        bigint seat_id FK
        enum allocation_status
        bigint active_seat_key "generated, UK with schedule_id"
        bigint active_bp_key "generated, UK"
    }

    PAYMENTS {
        bigint payment_id PK
        bigint booking_id FK
        varchar transaction_reference UK
        decimal amount
        enum payment_method
        enum payment_status
        datetime payment_datetime
    }

    CANCELLATIONS {
        bigint cancellation_id PK
        bigint booking_id FK "UK"
        bigint cancelled_by FK
        datetime cancellation_datetime
        varchar cancellation_reason
        decimal refundable_amount
        decimal cancellation_charge
        enum status
    }

    REFUNDS {
        bigint refund_id PK
        bigint cancellation_id FK "UK"
        bigint booking_id FK
        decimal refund_amount
        enum refund_status
        datetime refund_datetime
    }

    WAITING_LIST {
        bigint waitlist_id PK
        bigint booking_passenger_id FK "UK"
        bigint schedule_id FK
        enum coach_type
        int waitlist_position "UK with schedule_id, coach_type"
        enum status
    }

    NOTIFICATIONS {
        bigint notification_id PK
        bigint user_id FK
        bigint booking_id FK "nullable"
        enum notification_type
        varchar message
        tinyint is_read
    }

    AUDIT_LOGS {
        bigint audit_id PK
        varchar table_name
        bigint record_id
        enum action_type
        bigint performed_by FK "nullable"
        json old_value
        json new_value
    }
```

## Notes on non-obvious relationships

- **`TRAINS` → `STATIONS` (twice)**: `source_station_id` and
  `destination_station_id` are two separate foreign keys to the same table —
  a train's overall origin/terminus, independent of its detailed
  `TRAIN_ROUTES` stop list.
- **`SEAT_ALLOCATIONS` → `BOOKING_PASSENGERS` is one-to-*history*, not
  one-to-one.** A passenger can accumulate several allocation rows over time
  (e.g. RAC seat → released → reallocated to a regular seat on promotion),
  but only one may be `ACTIVE` at once — enforced by the generated
  `active_bp_key` column plus a `UNIQUE` index, not by a plain
  `UNIQUE(booking_passenger_id)`.
- **`SEAT_ALLOCATIONS` → seat double-booking guarantee**: the generated
  `active_seat_key` column (`seat_id` when `ACTIVE`, else `NULL`) combined
  with `UNIQUE(schedule_id, active_seat_key)` is what makes double-booking a
  *seat_id* on a given *schedule_id* structurally impossible at the storage
  engine level.
- **`CANCELLATIONS` → `REFUNDS` is 0-or-1**: a cancellation only produces a
  refund row if money had actually been paid; an unpaid, cancelled booking
  has a `CANCELLATIONS` row but no `REFUNDS` row.
- **`WAITING_LIST` → `BOOKING_PASSENGERS` is 0-or-1**: only passengers who
  couldn't be seated at booking time get a waiting-list row at all.
