-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 06_functions.sql
-- Purpose: Reusable, deterministic-where-possible stored functions.
-- =============================================================================

USE railflow_db;

-- Stored functions that read/write data must declare that fact; enabling this
-- session-independent server flag allows their creation under binary logging.
SET GLOBAL log_bin_trust_function_creators = 1;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- fn_generate_pnr — derives a collision-free 10-character PNR from an
-- InnoDB auto-increment value, so uniqueness is guaranteed by the storage
-- engine rather than by an application-side retry loop.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fn_generate_pnr()
RETURNS CHAR(10)
MODIFIES SQL DATA
BEGIN
    DECLARE v_seq BIGINT UNSIGNED;

    INSERT INTO pnr_counter (counter_id) VALUES (NULL);
    SET v_seq = LAST_INSERT_ID();

    RETURN CONCAT('PNR', LPAD(v_seq, 7, '0'));
END $$

-- -----------------------------------------------------------------------------
-- fn_calculate_fare — deterministic fare lookup for one passenger given the
-- active fare row for the train/class/route on the journey date.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fn_calculate_fare(
    p_train_id INT UNSIGNED,
    p_coach_type VARCHAR(3),
    p_source_station_id INT UNSIGNED,
    p_destination_station_id INT UNSIGNED,
    p_journey_date DATE
)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_fare DECIMAL(10,2);

    SELECT (base_fare + reservation_charge + gst_charge)
      INTO v_fare
      FROM fares
     WHERE train_id = p_train_id
       AND coach_type = p_coach_type
       AND source_station_id = p_source_station_id
       AND destination_station_id = p_destination_station_id
       AND status = 'ACTIVE'
       AND effective_from <= p_journey_date
       AND (effective_to IS NULL OR effective_to >= p_journey_date)
     ORDER BY effective_from DESC
     LIMIT 1;

    RETURN v_fare;
END $$

-- -----------------------------------------------------------------------------
-- fn_available_seats — count of seats in a coach not currently held by an
-- ACTIVE seat allocation for the given schedule.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fn_available_seats(
    p_schedule_id BIGINT UNSIGNED,
    p_coach_id BIGINT UNSIGNED
)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    DECLARE v_occupied INT;

    SELECT COUNT(*) INTO v_total
      FROM seats
     WHERE coach_id = p_coach_id
       AND status = 'ACTIVE';

    SELECT COUNT(*) INTO v_occupied
      FROM seat_allocations
     WHERE coach_id = p_coach_id
       AND schedule_id = p_schedule_id
       AND allocation_status = 'ACTIVE';

    RETURN v_total - v_occupied;
END $$

-- -----------------------------------------------------------------------------
-- fn_occupancy_percentage — percentage of a coach's active seats occupied
-- on a given schedule.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fn_occupancy_percentage(
    p_schedule_id BIGINT UNSIGNED,
    p_coach_id BIGINT UNSIGNED
)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    DECLARE v_occupied INT;

    SELECT COUNT(*) INTO v_total
      FROM seats
     WHERE coach_id = p_coach_id
       AND status = 'ACTIVE';

    IF v_total = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COUNT(*) INTO v_occupied
      FROM seat_allocations
     WHERE coach_id = p_coach_id
       AND schedule_id = p_schedule_id
       AND allocation_status = 'ACTIVE';

    RETURN ROUND((v_occupied / v_total) * 100, 2);
END $$

-- -----------------------------------------------------------------------------
-- fn_calculate_refund — cancellation-policy-driven refund amount. Charges a
-- percentage of the fare based on how close to departure the cancellation
-- happens, and never returns a negative amount or more than was paid.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fn_calculate_refund(
    p_fare_paid DECIMAL(10,2),
    p_departure_datetime DATETIME,
    p_cancellation_datetime DATETIME
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE v_hours_before INT;
    DECLARE v_charge_pct DECIMAL(5,2);
    DECLARE v_refund DECIMAL(10,2);

    IF p_fare_paid IS NULL OR p_fare_paid <= 0 THEN
        RETURN 0.00;
    END IF;

    IF p_cancellation_datetime >= p_departure_datetime THEN
        RETURN 0.00;
    END IF;

    SET v_hours_before = TIMESTAMPDIFF(HOUR, p_cancellation_datetime, p_departure_datetime);

    IF v_hours_before >= 48 THEN
        SET v_charge_pct = 0.05;
    ELSEIF v_hours_before >= 24 THEN
        SET v_charge_pct = 0.25;
    ELSEIF v_hours_before >= 4 THEN
        SET v_charge_pct = 0.50;
    ELSE
        SET v_charge_pct = 1.00;
    END IF;

    SET v_refund = p_fare_paid * (1 - v_charge_pct);

    IF v_refund < 0 THEN
        SET v_refund = 0.00;
    END IF;
    IF v_refund > p_fare_paid THEN
        SET v_refund = p_fare_paid;
    END IF;

    RETURN ROUND(v_refund, 2);
END $$

DELIMITER ;
