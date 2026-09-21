-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 02_create_tables.sql
-- Purpose: Core table definitions (PK / FK / UNIQUE / NOT NULL / DEFAULT).
-- CHECK constraints live in 03_constraints.sql, indexes in 04_indexes.sql.
-- =============================================================================

USE railflow_db;

-- -----------------------------------------------------------------------------
-- users
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    user_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name      VARCHAR(100)  NOT NULL,
    email          VARCHAR(150)  NOT NULL,
    phone          VARCHAR(15)   NOT NULL,
    password_hash  VARCHAR(255)  NOT NULL,
    role           ENUM('ADMIN', 'CUSTOMER', 'STAFF') NOT NULL DEFAULT 'CUSTOMER',
    account_status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_email UNIQUE (email)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- passengers
-- A passenger record is reusable across many bookings and may optionally be
-- linked to a login account (a user can book on behalf of family members who
-- have no account of their own).
-- -----------------------------------------------------------------------------
CREATE TABLE passengers (
    passenger_id       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id            BIGINT UNSIGNED NULL,
    full_name          VARCHAR(100) NOT NULL,
    date_of_birth      DATE NOT NULL,
    gender             ENUM('MALE', 'FEMALE', 'OTHER') NOT NULL,
    phone              VARCHAR(15) NULL,
    email              VARCHAR(150) NULL,
    id_document_type   ENUM('AADHAAR', 'PASSPORT', 'VOTER_ID', 'DRIVING_LICENSE', 'PAN') NOT NULL,
    id_document_number VARCHAR(50) NOT NULL,
    status             ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_passenger_document UNIQUE (id_document_type, id_document_number),
    CONSTRAINT fk_passenger_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- stations
-- -----------------------------------------------------------------------------
CREATE TABLE stations (
    station_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    station_code VARCHAR(10)  NOT NULL,
    station_name VARCHAR(100) NOT NULL,
    city         VARCHAR(100) NOT NULL,
    state        VARCHAR(100) NOT NULL,
    status       ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_station_code UNIQUE (station_code)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- trains
-- -----------------------------------------------------------------------------
CREATE TABLE trains (
    train_id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    train_number           VARCHAR(10)  NOT NULL,
    train_name             VARCHAR(100) NOT NULL,
    train_type             ENUM('EXPRESS', 'SUPERFAST', 'PASSENGER', 'RAJDHANI', 'SHATABDI', 'DURONTO', 'MAIL') NOT NULL,
    source_station_id      INT UNSIGNED NOT NULL,
    destination_station_id INT UNSIGNED NOT NULL,
    status                 ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_train_number UNIQUE (train_number),
    CONSTRAINT fk_train_source FOREIGN KEY (source_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_train_destination FOREIGN KEY (destination_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- train_routes — ordered list of intermediate/terminal stations per train
-- -----------------------------------------------------------------------------
CREATE TABLE train_routes (
    route_id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    train_id                INT UNSIGNED NOT NULL,
    station_id              INT UNSIGNED NOT NULL,
    sequence_order          SMALLINT UNSIGNED NOT NULL,
    arrival_time            TIME NULL,
    departure_time          TIME NULL,
    distance_from_origin_km DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    halt_minutes            SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_route_train_sequence UNIQUE (train_id, sequence_order),
    CONSTRAINT uq_route_train_station UNIQUE (train_id, station_id),
    CONSTRAINT fk_route_train FOREIGN KEY (train_id)
        REFERENCES trains (train_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_route_station FOREIGN KEY (station_id)
        REFERENCES stations (station_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- train_schedules — a specific train running on a specific calendar date
-- -----------------------------------------------------------------------------
CREATE TABLE train_schedules (
    schedule_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    train_id           INT UNSIGNED NOT NULL,
    journey_date       DATE NOT NULL,
    departure_datetime DATETIME NOT NULL,
    arrival_datetime   DATETIME NOT NULL,
    status             ENUM('SCHEDULED', 'DELAYED', 'CANCELLED', 'COMPLETED') NOT NULL DEFAULT 'SCHEDULED',
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_schedule_train_date UNIQUE (train_id, journey_date),
    CONSTRAINT fk_schedule_train FOREIGN KEY (train_id)
        REFERENCES trains (train_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- coaches
-- -----------------------------------------------------------------------------
CREATE TABLE coaches (
    coach_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    train_id     INT UNSIGNED NOT NULL,
    coach_number VARCHAR(10) NOT NULL,
    coach_type   ENUM('SL', '3A', '2A', '1A', 'CC', 'EC') NOT NULL,
    total_seats  SMALLINT UNSIGNED NOT NULL,
    status       ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_coach_train_number UNIQUE (train_id, coach_number),
    CONSTRAINT fk_coach_train FOREIGN KEY (train_id)
        REFERENCES trains (train_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- seats
-- -----------------------------------------------------------------------------
CREATE TABLE seats (
    seat_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    coach_id    BIGINT UNSIGNED NOT NULL,
    seat_number VARCHAR(10) NOT NULL,
    seat_type   ENUM('LOWER', 'MIDDLE', 'UPPER', 'SIDE_LOWER', 'SIDE_UPPER', 'WINDOW', 'AISLE') NOT NULL,
    seat_category ENUM('REGULAR', 'RAC') NOT NULL DEFAULT 'REGULAR',
    status      ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_seat_coach_number UNIQUE (coach_id, seat_number),
    CONSTRAINT fk_seat_coach FOREIGN KEY (coach_id)
        REFERENCES coaches (coach_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- fares — deterministic fare matrix per train / class / station pair
-- -----------------------------------------------------------------------------
CREATE TABLE fares (
    fare_id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    train_id               INT UNSIGNED NOT NULL,
    coach_type             ENUM('SL', '3A', '2A', '1A', 'CC', 'EC') NOT NULL,
    source_station_id      INT UNSIGNED NOT NULL,
    destination_station_id INT UNSIGNED NOT NULL,
    base_fare              DECIMAL(10,2) NOT NULL,
    reservation_charge     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    gst_charge             DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    effective_from         DATE NOT NULL,
    effective_to           DATE NULL,
    status                 ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_fare_combination UNIQUE (train_id, coach_type, source_station_id, destination_station_id, effective_from),
    CONSTRAINT fk_fare_train FOREIGN KEY (train_id)
        REFERENCES trains (train_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_fare_source FOREIGN KEY (source_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_fare_destination FOREIGN KEY (destination_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- pnr_counter — single-row-per-call InnoDB auto-increment counter used to
-- derive collision-free PNRs without needing application-side coordination.
-- -----------------------------------------------------------------------------
CREATE TABLE pnr_counter (
    counter_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- bookings — header record for one reservation transaction (1..N passengers)
-- -----------------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    pnr                    CHAR(10) NOT NULL,
    user_id                BIGINT UNSIGNED NOT NULL,
    train_id               INT UNSIGNED NOT NULL,
    schedule_id            BIGINT UNSIGNED NOT NULL,
    source_station_id      INT UNSIGNED NOT NULL,
    destination_station_id INT UNSIGNED NOT NULL,
    coach_type             ENUM('SL', '3A', '2A', '1A', 'CC', 'EC') NOT NULL,
    journey_date           DATE NOT NULL,
    booking_datetime       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_passengers       TINYINT UNSIGNED NOT NULL,
    total_fare             DECIMAL(10,2) NOT NULL,
    booking_status         ENUM('PENDING', 'CONFIRMED', 'RAC', 'WAITLISTED', 'CANCELLED', 'COMPLETED') NOT NULL DEFAULT 'PENDING',
    payment_status         ENUM('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED') NOT NULL DEFAULT 'PENDING',
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_booking_pnr UNIQUE (pnr),
    CONSTRAINT fk_booking_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_booking_train FOREIGN KEY (train_id)
        REFERENCES trains (train_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_booking_schedule FOREIGN KEY (schedule_id)
        REFERENCES train_schedules (schedule_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_booking_source FOREIGN KEY (source_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_booking_destination FOREIGN KEY (destination_station_id)
        REFERENCES stations (station_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- booking_passengers — junction: which passengers belong to which booking
-- -----------------------------------------------------------------------------
CREATE TABLE booking_passengers (
    booking_passenger_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id           BIGINT UNSIGNED NOT NULL,
    passenger_id         BIGINT UNSIGNED NOT NULL,
    age_at_booking       TINYINT UNSIGNED NOT NULL,
    fare_component       DECIMAL(10,2) NOT NULL,
    passenger_status     ENUM('PENDING', 'CONFIRMED', 'RAC', 'WAITLISTED', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_booking_passenger UNIQUE (booking_id, passenger_id),
    CONSTRAINT fk_bp_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bp_passenger FOREIGN KEY (passenger_id)
        REFERENCES passengers (passenger_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- seat_allocations — physical seat assigned to a booked passenger for a
-- specific train schedule. active_seat_key / active_bp_key are generated
-- columns that are NULL whenever the allocation has been released, which
-- lets the two unique indexes below block (a) a concurrent duplicate ACTIVE
-- allocation of the same seat on the same journey, and (b) a passenger
-- holding two ACTIVE allocations at once — while still permitting the seat
-- to be re-allocated to someone else afterwards, and preserving full history.
-- -----------------------------------------------------------------------------
CREATE TABLE seat_allocations (
    allocation_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_passenger_id BIGINT UNSIGNED NOT NULL,
    schedule_id          BIGINT UNSIGNED NOT NULL,
    coach_id             BIGINT UNSIGNED NOT NULL,
    seat_id              BIGINT UNSIGNED NOT NULL,
    allocation_status    ENUM('ACTIVE', 'RELEASED') NOT NULL DEFAULT 'ACTIVE',
    active_seat_key      BIGINT UNSIGNED GENERATED ALWAYS AS (
        CASE WHEN allocation_status = 'ACTIVE' THEN seat_id ELSE NULL END
    ) STORED,
    active_bp_key        BIGINT UNSIGNED GENERATED ALWAYS AS (
        CASE WHEN allocation_status = 'ACTIVE' THEN booking_passenger_id ELSE NULL END
    ) STORED,
    allocated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    released_at          TIMESTAMP NULL,
    CONSTRAINT uq_allocation_active_bp UNIQUE (active_bp_key),
    CONSTRAINT uq_allocation_active_seat UNIQUE (schedule_id, active_seat_key),
    CONSTRAINT fk_alloc_bp FOREIGN KEY (booking_passenger_id)
        REFERENCES booking_passengers (booking_passenger_id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_alloc_schedule FOREIGN KEY (schedule_id)
        REFERENCES train_schedules (schedule_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_alloc_coach FOREIGN KEY (coach_id)
        REFERENCES coaches (coach_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_alloc_seat FOREIGN KEY (seat_id)
        REFERENCES seats (seat_id) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- payments
-- -----------------------------------------------------------------------------
CREATE TABLE payments (
    payment_id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id            BIGINT UNSIGNED NOT NULL,
    transaction_reference VARCHAR(50) NOT NULL,
    amount                DECIMAL(10,2) NOT NULL,
    payment_method        ENUM('CREDIT_CARD', 'DEBIT_CARD', 'UPI', 'NET_BANKING', 'WALLET') NOT NULL,
    payment_status        ENUM('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED') NOT NULL DEFAULT 'PENDING',
    payment_datetime      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_payment_transaction_ref UNIQUE (transaction_reference),
    CONSTRAINT fk_payment_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- cancellations — one record per cancelled booking (booking-level cancel);
-- the UNIQUE on booking_id is itself a hard guard against double cancellation.
-- -----------------------------------------------------------------------------
CREATE TABLE cancellations (
    cancellation_id       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_id            BIGINT UNSIGNED NOT NULL,
    cancelled_by          BIGINT UNSIGNED NOT NULL,
    cancellation_datetime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancellation_reason   VARCHAR(255) NULL,
    refundable_amount     DECIMAL(10,2) NOT NULL,
    cancellation_charge   DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status                ENUM('INITIATED', 'COMPLETED') NOT NULL DEFAULT 'COMPLETED',
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_cancellation_booking UNIQUE (booking_id),
    CONSTRAINT fk_cancel_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_cancel_user FOREIGN KEY (cancelled_by)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- refunds
-- -----------------------------------------------------------------------------
CREATE TABLE refunds (
    refund_id       BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cancellation_id BIGINT UNSIGNED NOT NULL,
    booking_id      BIGINT UNSIGNED NOT NULL,
    refund_amount   DECIMAL(10,2) NOT NULL,
    refund_status   ENUM('PENDING', 'PROCESSED', 'FAILED') NOT NULL DEFAULT 'PENDING',
    refund_datetime DATETIME NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_refund_cancellation UNIQUE (cancellation_id),
    CONSTRAINT fk_refund_cancellation FOREIGN KEY (cancellation_id)
        REFERENCES cancellations (cancellation_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_refund_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- waiting_list
-- -----------------------------------------------------------------------------
CREATE TABLE waiting_list (
    waitlist_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    booking_passenger_id BIGINT UNSIGNED NOT NULL,
    schedule_id          BIGINT UNSIGNED NOT NULL,
    coach_type           ENUM('SL', '3A', '2A', '1A', 'CC', 'EC') NOT NULL,
    waitlist_position    INT UNSIGNED NOT NULL,
    status               ENUM('WAITING', 'PROMOTED', 'CANCELLED', 'EXPIRED') NOT NULL DEFAULT 'WAITING',
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_waitlist_bp UNIQUE (booking_passenger_id),
    CONSTRAINT uq_waitlist_position UNIQUE (schedule_id, coach_type, waitlist_position),
    CONSTRAINT fk_waitlist_bp FOREIGN KEY (booking_passenger_id)
        REFERENCES booking_passengers (booking_passenger_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_waitlist_schedule FOREIGN KEY (schedule_id)
        REFERENCES train_schedules (schedule_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- notifications
-- -----------------------------------------------------------------------------
CREATE TABLE notifications (
    notification_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id           BIGINT UNSIGNED NOT NULL,
    booking_id        BIGINT UNSIGNED NULL,
    notification_type ENUM('BOOKING_CONFIRMATION', 'CANCELLATION', 'REFUND', 'WAITLIST_PROMOTION', 'SCHEDULE_CHANGE', 'PAYMENT') NOT NULL,
    message           VARCHAR(500) NOT NULL,
    is_read           TINYINT(1) NOT NULL DEFAULT 0,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notification_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_notification_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- audit_logs — append-only trail of sensitive state transitions
-- -----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    audit_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    table_name      VARCHAR(64) NOT NULL,
    record_id       BIGINT UNSIGNED NOT NULL,
    action_type     ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    performed_by    BIGINT UNSIGNED NULL,
    old_value       JSON NULL,
    new_value       JSON NULL,
    action_datetime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_user FOREIGN KEY (performed_by)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;
