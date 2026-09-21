-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 03_constraints.sql
-- Purpose: Business-rule CHECK constraints layered on top of the schema.
-- =============================================================================

USE railflow_db;

-- users --------------------------------------------------------------------
ALTER TABLE users
    ADD CONSTRAINT chk_users_phone CHECK (phone REGEXP '^[+]?[0-9]{10,15}$');

ALTER TABLE users
    ADD CONSTRAINT chk_users_email_format CHECK (email REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$');

-- passengers -----------------------------------------------------------------
ALTER TABLE passengers
    ADD CONSTRAINT chk_passenger_phone CHECK (phone IS NULL OR phone REGEXP '^[+]?[0-9]{10,15}$');

-- Date-of-birth validity (not in the future, not implausibly old) is enforced
-- by trg_passengers_validate_dob in 08_triggers.sql: MySQL CHECK constraints
-- must be deterministic and cannot call CURDATE(), so a trigger is required.

-- stations ---------------------------------------------------------------------
ALTER TABLE stations
    ADD CONSTRAINT chk_station_code_format CHECK (station_code REGEXP '^[A-Z0-9]{2,10}$');

-- trains -----------------------------------------------------------------------
ALTER TABLE trains
    ADD CONSTRAINT chk_train_source_dest_diff CHECK (source_station_id <> destination_station_id);

-- train_routes -------------------------------------------------------------------
ALTER TABLE train_routes
    ADD CONSTRAINT chk_route_sequence_positive CHECK (sequence_order > 0);

ALTER TABLE train_routes
    ADD CONSTRAINT chk_route_distance_non_negative CHECK (distance_from_origin_km >= 0);

ALTER TABLE train_routes
    ADD CONSTRAINT chk_route_halt_non_negative CHECK (halt_minutes >= 0);

ALTER TABLE train_routes
    ADD CONSTRAINT chk_route_departure_after_arrival
        CHECK (arrival_time IS NULL OR departure_time IS NULL OR departure_time >= arrival_time);

-- train_schedules ----------------------------------------------------------------
ALTER TABLE train_schedules
    ADD CONSTRAINT chk_schedule_arrival_after_departure CHECK (arrival_datetime > departure_datetime);

-- coaches ----------------------------------------------------------------------
ALTER TABLE coaches
    ADD CONSTRAINT chk_coach_capacity_positive CHECK (total_seats > 0);

-- fares ------------------------------------------------------------------------
ALTER TABLE fares
    ADD CONSTRAINT chk_fare_base_non_negative CHECK (base_fare >= 0);

ALTER TABLE fares
    ADD CONSTRAINT chk_fare_reservation_non_negative CHECK (reservation_charge >= 0);

ALTER TABLE fares
    ADD CONSTRAINT chk_fare_gst_non_negative CHECK (gst_charge >= 0);

ALTER TABLE fares
    ADD CONSTRAINT chk_fare_source_dest_diff CHECK (source_station_id <> destination_station_id);

ALTER TABLE fares
    ADD CONSTRAINT chk_fare_validity_window CHECK (effective_to IS NULL OR effective_to >= effective_from);

-- bookings ---------------------------------------------------------------------
ALTER TABLE bookings
    ADD CONSTRAINT chk_booking_source_dest_diff CHECK (source_station_id <> destination_station_id);

ALTER TABLE bookings
    ADD CONSTRAINT chk_booking_passengers_positive CHECK (total_passengers > 0 AND total_passengers <= 6);

ALTER TABLE bookings
    ADD CONSTRAINT chk_booking_fare_non_negative CHECK (total_fare >= 0);

-- booking_passengers -------------------------------------------------------------
ALTER TABLE booking_passengers
    ADD CONSTRAINT chk_bp_age_range CHECK (age_at_booking BETWEEN 0 AND 125);

ALTER TABLE booking_passengers
    ADD CONSTRAINT chk_bp_fare_component_non_negative CHECK (fare_component >= 0);

-- payments ---------------------------------------------------------------------
ALTER TABLE payments
    ADD CONSTRAINT chk_payment_amount_non_negative CHECK (amount >= 0);

-- cancellations ------------------------------------------------------------------
ALTER TABLE cancellations
    ADD CONSTRAINT chk_cancel_refundable_non_negative CHECK (refundable_amount >= 0);

ALTER TABLE cancellations
    ADD CONSTRAINT chk_cancel_charge_non_negative CHECK (cancellation_charge >= 0);

-- refunds ----------------------------------------------------------------------
ALTER TABLE refunds
    ADD CONSTRAINT chk_refund_amount_non_negative CHECK (refund_amount >= 0);

-- waiting_list -------------------------------------------------------------------
ALTER TABLE waiting_list
    ADD CONSTRAINT chk_waitlist_position_positive CHECK (waitlist_position > 0);
