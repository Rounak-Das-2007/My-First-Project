-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 07_procedures.sql
-- Purpose: Transactional business logic — booking, payment, cancellation,
-- and waiting-list promotion.
-- =============================================================================

USE railflow_db;

DELIMITER $$

-- =============================================================================
-- sp_book_ticket
-- Books 1..6 passengers on one train schedule as a single atomic operation.
-- Passenger identity is passed as a JSON array so the procedure can accept a
-- variable-length passenger list without a client-side loop of INSERTs.
-- Each element: {"passenger_id": <id>, "age": <int>}
-- =============================================================================
CREATE PROCEDURE sp_book_ticket (
    IN  p_user_id BIGINT UNSIGNED,
    IN  p_train_id INT UNSIGNED,
    IN  p_schedule_id BIGINT UNSIGNED,
    IN  p_source_station_id INT UNSIGNED,
    IN  p_destination_station_id INT UNSIGNED,
    IN  p_coach_type VARCHAR(3),
    IN  p_passengers_json JSON,
    OUT p_pnr CHAR(10),
    OUT p_booking_status VARCHAR(15),
    OUT p_total_fare DECIMAL(10,2)
)
proc_body: BEGIN
    DECLARE v_journey_date DATE;
    DECLARE v_departure_dt DATETIME;
    DECLARE v_schedule_status VARCHAR(15);
    DECLARE v_train_status VARCHAR(15);
    DECLARE v_src_status VARCHAR(15);
    DECLARE v_dst_status VARCHAR(15);
    DECLARE v_src_seq INT;
    DECLARE v_dst_seq INT;
    DECLARE v_user_status VARCHAR(15);
    DECLARE v_passenger_count INT;
    DECLARE v_fare_per_passenger DECIMAL(10,2);
    DECLARE v_booking_id BIGINT UNSIGNED;
    DECLARE v_idx INT DEFAULT 0;
    DECLARE v_passenger_id BIGINT UNSIGNED;
    DECLARE v_age INT;
    DECLARE v_booking_passenger_id BIGINT UNSIGNED;
    DECLARE v_coach_id BIGINT UNSIGNED;
    DECLARE v_seat_id BIGINT UNSIGNED;
    DECLARE v_seat_category VARCHAR(10);
    DECLARE v_final_status VARCHAR(15);
    DECLARE v_any_waitlisted BOOLEAN DEFAULT FALSE;
    DECLARE v_all_confirmed BOOLEAN DEFAULT TRUE;
    DECLARE v_next_wait_pos INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- ---- Validation -----------------------------------------------------
    SELECT account_status INTO v_user_status FROM users WHERE user_id = p_user_id;
    IF v_user_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid customer: user does not exist.';
    END IF;
    IF v_user_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inactive users cannot create new bookings.';
    END IF;

    SELECT status INTO v_train_status FROM trains WHERE train_id = p_train_id;
    IF v_train_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid train: train does not exist.';
    END IF;
    IF v_train_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Train is not in active operation.';
    END IF;

    SELECT journey_date, departure_datetime, status
      INTO v_journey_date, v_departure_dt, v_schedule_status
      FROM train_schedules
     WHERE schedule_id = p_schedule_id
       AND train_id = p_train_id;
    IF v_journey_date IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid schedule for the selected train.';
    END IF;
    IF v_schedule_status NOT IN ('SCHEDULED', 'DELAYED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Train does not operate on the selected date.';
    END IF;
    IF v_journey_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Journey date has already passed.';
    END IF;

    IF p_source_station_id = p_destination_station_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source and destination stations cannot be identical.';
    END IF;

    SELECT status INTO v_src_status FROM stations WHERE station_id = p_source_station_id;
    SELECT status INTO v_dst_status FROM stations WHERE station_id = p_destination_station_id;
    IF v_src_status IS NULL OR v_dst_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid source or destination station.';
    END IF;
    IF v_src_status <> 'ACTIVE' OR v_dst_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source or destination station is inactive.';
    END IF;

    SELECT sequence_order INTO v_src_seq FROM train_routes
     WHERE train_id = p_train_id AND station_id = p_source_station_id;
    SELECT sequence_order INTO v_dst_seq FROM train_routes
     WHERE train_id = p_train_id AND station_id = p_destination_station_id;
    IF v_src_seq IS NULL OR v_dst_seq IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Selected stations are not on this train''s route.';
    END IF;
    IF v_src_seq >= v_dst_seq THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid route: destination must come after source on the train route.';
    END IF;

    SET v_passenger_count = JSON_LENGTH(p_passengers_json);
    IF v_passenger_count IS NULL OR v_passenger_count < 1 OR v_passenger_count > 6 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A booking must contain between 1 and 6 passengers.';
    END IF;

    SET v_fare_per_passenger = fn_calculate_fare(
        p_train_id, p_coach_type, p_source_station_id, p_destination_station_id, v_journey_date
    );
    IF v_fare_per_passenger IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No active fare configured for this train/class/route.';
    END IF;

    -- ---- Transactional allocation ----------------------------------------
    START TRANSACTION;

    INSERT INTO bookings (
        pnr, user_id, train_id, schedule_id, source_station_id, destination_station_id,
        coach_type, journey_date, total_passengers, total_fare, booking_status, payment_status
    )
    VALUES (
        fn_generate_pnr(), p_user_id, p_train_id, p_schedule_id, p_source_station_id, p_destination_station_id,
        p_coach_type, v_journey_date, v_passenger_count, v_fare_per_passenger * v_passenger_count, 'PENDING', 'PENDING'
    );
    SET v_booking_id = LAST_INSERT_ID();
    SELECT pnr INTO p_pnr FROM bookings WHERE booking_id = v_booking_id;

    WHILE v_idx < v_passenger_count DO
        SET v_passenger_id = JSON_UNQUOTE(JSON_EXTRACT(p_passengers_json, CONCAT('$[', v_idx, '].passenger_id')));
        SET v_age = JSON_UNQUOTE(JSON_EXTRACT(p_passengers_json, CONCAT('$[', v_idx, '].age')));

        IF NOT EXISTS (SELECT 1 FROM passengers WHERE passenger_id = v_passenger_id AND status = 'ACTIVE') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'One or more passengers do not exist or are inactive.';
        END IF;

        INSERT INTO booking_passengers (
            booking_id, passenger_id, age_at_booking, fare_component, passenger_status
        )
        VALUES (
            v_booking_id, v_passenger_id, v_age, v_fare_per_passenger, 'PENDING'
        );
        SET v_booking_passenger_id = LAST_INSERT_ID();

        -- Lock and claim one available REGULAR seat, falling back to RAC.
        -- FOR UPDATE SKIP LOCKED lets concurrent bookings race for different
        -- seats without blocking on rows another transaction is evaluating,
        -- while the row lock itself is the final barrier against two
        -- transactions claiming the very same seat.
        SET v_coach_id = NULL;
        SET v_seat_id = NULL;
        SET v_seat_category = NULL;

        SELECT s.coach_id, s.seat_id, s.seat_category
          INTO v_coach_id, v_seat_id, v_seat_category
          FROM seats s
          JOIN coaches c ON c.coach_id = s.coach_id
         WHERE c.train_id = p_train_id
           AND c.coach_type = p_coach_type
           AND c.status = 'ACTIVE'
           AND s.status = 'ACTIVE'
           AND NOT EXISTS (
                SELECT 1 FROM seat_allocations sa
                 WHERE sa.schedule_id = p_schedule_id
                   AND sa.seat_id = s.seat_id
                   AND sa.allocation_status = 'ACTIVE'
           )
         ORDER BY FIELD(s.seat_category, 'REGULAR', 'RAC'), s.seat_id
         LIMIT 1
           FOR UPDATE SKIP LOCKED;

        IF v_seat_id IS NOT NULL THEN
            INSERT INTO seat_allocations (
                booking_passenger_id, schedule_id, coach_id, seat_id, allocation_status
            )
            VALUES (
                v_booking_passenger_id, p_schedule_id, v_coach_id, v_seat_id, 'ACTIVE'
            );

            SET v_final_status = IF(v_seat_category = 'RAC', 'RAC', 'CONFIRMED');
            UPDATE booking_passengers SET passenger_status = v_final_status
             WHERE booking_passenger_id = v_booking_passenger_id;

            IF v_final_status = 'RAC' THEN
                SET v_all_confirmed = FALSE;
            END IF;
        ELSE
            SELECT COALESCE(MAX(waitlist_position), 0) + 1 INTO v_next_wait_pos
              FROM waiting_list
             WHERE schedule_id = p_schedule_id
               AND coach_type = p_coach_type;

            INSERT INTO waiting_list (
                booking_passenger_id, schedule_id, coach_type, waitlist_position, status
            )
            VALUES (
                v_booking_passenger_id, p_schedule_id, p_coach_type, v_next_wait_pos, 'WAITING'
            );

            UPDATE booking_passengers SET passenger_status = 'WAITLISTED'
             WHERE booking_passenger_id = v_booking_passenger_id;

            SET v_any_waitlisted = TRUE;
            SET v_all_confirmed = FALSE;
        END IF;

        SET v_idx = v_idx + 1;
    END WHILE;

    IF v_any_waitlisted THEN
        SET v_final_status = 'WAITLISTED';
    ELSEIF v_all_confirmed THEN
        SET v_final_status = 'CONFIRMED';
    ELSE
        SET v_final_status = 'RAC';
    END IF;

    UPDATE bookings SET booking_status = v_final_status WHERE booking_id = v_booking_id;

    SET p_booking_status = v_final_status;
    SET p_total_fare = v_fare_per_passenger * v_passenger_count;

    COMMIT;
END $$

-- =============================================================================
-- sp_process_payment
-- Records a simulated payment against a booking and updates its status.
-- =============================================================================
CREATE PROCEDURE sp_process_payment (
    IN  p_booking_id BIGINT UNSIGNED,
    IN  p_amount DECIMAL(10,2),
    IN  p_payment_method VARCHAR(20),
    IN  p_transaction_reference VARCHAR(50),
    IN  p_simulate_success BOOLEAN
)
proc_body: BEGIN
    DECLARE v_booking_status VARCHAR(15);
    DECLARE v_total_fare DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT booking_status, total_fare INTO v_booking_status, v_total_fare
      FROM bookings WHERE booking_id = p_booking_id;

    IF v_booking_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid booking: booking does not exist.';
    END IF;
    IF v_booking_status = 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment failed: booking has already been cancelled.';
    END IF;
    IF p_amount <> v_total_fare THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment amount does not match the booking total fare.';
    END IF;

    START TRANSACTION;

    INSERT INTO payments (
        booking_id, transaction_reference, amount, payment_method, payment_status, payment_datetime
    )
    VALUES (
        p_booking_id, p_transaction_reference, p_amount, p_payment_method,
        IF(p_simulate_success, 'SUCCESS', 'FAILED'), NOW()
    );

    UPDATE bookings
       SET payment_status = IF(p_simulate_success, 'SUCCESS', 'FAILED'),
           booking_status = IF(p_simulate_success, booking_status, booking_status)
     WHERE booking_id = p_booking_id;

    COMMIT;
END $$

-- =============================================================================
-- sp_promote_waiting_list
-- Given one now-vacant seat, promotes the earliest eligible RAC passenger to
-- CONFIRMED (reassigning them to the vacated regular seat) and, in turn,
-- promotes the earliest WAITING passenger into the RAC seat that frees up.
-- If there is no RAC passenger to promote, the earliest WAITING passenger is
-- promoted directly into the vacated seat instead. Called from within an
-- already-open transaction (sp_cancel_booking); it does not commit itself.
-- =============================================================================
CREATE PROCEDURE sp_promote_waiting_list (
    IN p_schedule_id BIGINT UNSIGNED,
    IN p_coach_type VARCHAR(3),
    IN p_vacated_coach_id BIGINT UNSIGNED,
    IN p_vacated_seat_id BIGINT UNSIGNED,
    IN p_vacated_seat_category VARCHAR(10)
)
proc_body: BEGIN
    DECLARE v_promote_bp_id BIGINT UNSIGNED;
    DECLARE v_promote_booking_id BIGINT UNSIGNED;
    DECLARE v_promote_waitlist_id BIGINT UNSIGNED;
    DECLARE v_rac_bp_id BIGINT UNSIGNED;
    DECLARE v_rac_booking_id BIGINT UNSIGNED;
    DECLARE v_rac_alloc_id BIGINT UNSIGNED;
    DECLARE v_rac_coach_id BIGINT UNSIGNED;
    DECLARE v_rac_seat_id BIGINT UNSIGNED;
    DECLARE v_target_coach_id BIGINT UNSIGNED;
    DECLARE v_target_seat_id BIGINT UNSIGNED;
    DECLARE v_target_category VARCHAR(10);
    DECLARE v_new_status VARCHAR(15);

    SET v_target_coach_id = p_vacated_coach_id;
    SET v_target_seat_id = p_vacated_seat_id;
    SET v_target_category = p_vacated_seat_category;

    -- If a REGULAR seat opened up, first move the earliest RAC passenger
    -- into it — that in turn frees their RAC seat for a waitlisted passenger.
    IF p_vacated_seat_category = 'REGULAR' THEN
        SELECT sa.booking_passenger_id, bp.booking_id, sa.allocation_id, sa.coach_id, sa.seat_id
          INTO v_rac_bp_id, v_rac_booking_id, v_rac_alloc_id, v_rac_coach_id, v_rac_seat_id
          FROM booking_passengers bp
          JOIN seat_allocations sa ON sa.booking_passenger_id = bp.booking_passenger_id
          JOIN bookings b ON b.booking_id = bp.booking_id
         WHERE b.schedule_id = p_schedule_id
           AND b.coach_type = p_coach_type
           AND bp.passenger_status = 'RAC'
           AND sa.allocation_status = 'ACTIVE'
         ORDER BY bp.created_at
         LIMIT 1
           FOR UPDATE;

        IF v_rac_bp_id IS NOT NULL THEN
            UPDATE seat_allocations
               SET allocation_status = 'RELEASED', released_at = NOW()
             WHERE allocation_id = v_rac_alloc_id;

            INSERT INTO seat_allocations (booking_passenger_id, schedule_id, coach_id, seat_id, allocation_status)
            VALUES (v_rac_bp_id, p_schedule_id, p_vacated_coach_id, p_vacated_seat_id, 'ACTIVE');

            UPDATE booking_passengers SET passenger_status = 'CONFIRMED' WHERE booking_passenger_id = v_rac_bp_id;
            CALL sp_recompute_booking_status(v_rac_booking_id);

            -- The seat vacated by the RAC passenger becomes the promotion target.
            SET v_target_coach_id = v_rac_coach_id;
            SET v_target_seat_id = v_rac_seat_id;
            SET v_target_category = 'RAC';
        END IF;
    END IF;

    SELECT wl.waitlist_id, wl.booking_passenger_id, bp.booking_id
      INTO v_promote_waitlist_id, v_promote_bp_id, v_promote_booking_id
      FROM waiting_list wl
      JOIN booking_passengers bp ON bp.booking_passenger_id = wl.booking_passenger_id
     WHERE wl.schedule_id = p_schedule_id
       AND wl.coach_type = p_coach_type
       AND wl.status = 'WAITING'
     ORDER BY wl.waitlist_position
     LIMIT 1
       FOR UPDATE;

    IF v_promote_bp_id IS NOT NULL THEN
        INSERT INTO seat_allocations (booking_passenger_id, schedule_id, coach_id, seat_id, allocation_status)
        VALUES (v_promote_bp_id, p_schedule_id, v_target_coach_id, v_target_seat_id, 'ACTIVE');

        SET v_new_status = IF(v_target_category = 'REGULAR', 'CONFIRMED', 'RAC');

        UPDATE booking_passengers SET passenger_status = v_new_status
         WHERE booking_passenger_id = v_promote_bp_id;

        UPDATE waiting_list SET status = 'PROMOTED'
         WHERE waitlist_id = v_promote_waitlist_id;

        CALL sp_recompute_booking_status(v_promote_booking_id);

        INSERT INTO notifications (user_id, booking_id, notification_type, message)
        SELECT b.user_id, b.booking_id, 'WAITLIST_PROMOTION',
               CONCAT('Your waitlisted passenger has been promoted to ', v_new_status, ' on PNR ', b.pnr, '.')
          FROM bookings b WHERE b.booking_id = v_promote_booking_id;
    END IF;
END $$

-- =============================================================================
-- sp_recompute_booking_status
-- Derives a booking's overall status from the current status of its
-- individual passengers. Used after any change to booking_passengers.
-- =============================================================================
CREATE PROCEDURE sp_recompute_booking_status (
    IN p_booking_id BIGINT UNSIGNED
)
proc_body: BEGIN
    DECLARE v_total INT;
    DECLARE v_cancelled INT;
    DECLARE v_confirmed INT;
    DECLARE v_rac INT;
    DECLARE v_waitlisted INT;
    DECLARE v_new_status VARCHAR(15);
    DECLARE v_current_status VARCHAR(15);

    SELECT booking_status INTO v_current_status FROM bookings WHERE booking_id = p_booking_id;
    IF v_current_status = 'CANCELLED' THEN
        LEAVE proc_body;
    END IF;

    SELECT
        COUNT(*),
        SUM(passenger_status = 'CANCELLED'),
        SUM(passenger_status = 'CONFIRMED'),
        SUM(passenger_status = 'RAC'),
        SUM(passenger_status = 'WAITLISTED')
      INTO v_total, v_cancelled, v_confirmed, v_rac, v_waitlisted
      FROM booking_passengers
     WHERE booking_id = p_booking_id;

    IF v_cancelled = v_total THEN
        SET v_new_status = 'CANCELLED';
    ELSEIF v_waitlisted > 0 THEN
        SET v_new_status = 'WAITLISTED';
    ELSEIF v_rac > 0 THEN
        SET v_new_status = 'RAC';
    ELSE
        SET v_new_status = 'CONFIRMED';
    END IF;

    UPDATE bookings SET booking_status = v_new_status WHERE booking_id = p_booking_id;
END $$

-- =============================================================================
-- sp_cancel_booking
-- Cancels an entire booking (all its passengers) by PNR: releases seats,
-- records the cancellation, calculates and records the refund, and triggers
-- waiting-list promotion for every seat it frees.
-- =============================================================================
CREATE PROCEDURE sp_cancel_booking (
    IN  p_pnr CHAR(10),
    IN  p_cancelled_by BIGINT UNSIGNED,
    IN  p_reason VARCHAR(255),
    OUT p_refund_amount DECIMAL(10,2)
)
proc_body: BEGIN
    DECLARE v_booking_id BIGINT UNSIGNED;
    DECLARE v_booking_status VARCHAR(15);
    DECLARE v_payment_status VARCHAR(15);
    DECLARE v_departure_dt DATETIME;
    DECLARE v_total_fare DECIMAL(10,2);
    DECLARE v_amount_paid DECIMAL(10,2);
    DECLARE v_cancellation_id BIGINT UNSIGNED;
    DECLARE v_refund DECIMAL(10,2);
    DECLARE v_charge DECIMAL(10,2);
    DECLARE v_schedule_id BIGINT UNSIGNED;
    DECLARE v_coach_type VARCHAR(3);

    DECLARE v_done INT DEFAULT 0;
    DECLARE v_alloc_id BIGINT UNSIGNED;
    DECLARE v_coach_id BIGINT UNSIGNED;
    DECLARE v_seat_id BIGINT UNSIGNED;
    DECLARE v_seat_category VARCHAR(10);

    DECLARE cur_allocations CURSOR FOR
        SELECT sa.allocation_id, sa.coach_id, sa.seat_id, s.seat_category
          FROM booking_passengers bp
          JOIN seat_allocations sa ON sa.booking_passenger_id = bp.booking_passenger_id
          JOIN seats s ON s.seat_id = sa.seat_id
         WHERE bp.booking_id = v_booking_id
           AND sa.allocation_status = 'ACTIVE';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT booking_id, booking_status, payment_status, schedule_id, coach_type, total_fare
      INTO v_booking_id, v_booking_status, v_payment_status, v_schedule_id, v_coach_type, v_total_fare
      FROM bookings
     WHERE pnr = p_pnr;

    IF v_booking_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid PNR: booking does not exist.';
    END IF;
    IF v_booking_status = 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking has already been cancelled.';
    END IF;

    SELECT departure_datetime INTO v_departure_dt
      FROM train_schedules WHERE schedule_id = v_schedule_id;

    SET v_amount_paid = IF(v_payment_status = 'SUCCESS', v_total_fare, 0.00);
    SET v_refund = fn_calculate_refund(v_amount_paid, v_departure_dt, NOW());
    SET v_charge = v_amount_paid - v_refund;
    IF v_charge < 0 THEN
        SET v_charge = 0.00;
    END IF;

    START TRANSACTION;

    INSERT INTO cancellations (
        booking_id, cancelled_by, cancellation_reason, refundable_amount, cancellation_charge, status
    )
    VALUES (
        v_booking_id, p_cancelled_by, p_reason, v_refund, v_charge, 'COMPLETED'
    );
    SET v_cancellation_id = LAST_INSERT_ID();

    IF v_amount_paid > 0 THEN
        INSERT INTO refunds (cancellation_id, booking_id, refund_amount, refund_status, refund_datetime)
        VALUES (v_cancellation_id, v_booking_id, v_refund, 'PROCESSED', NOW());

        UPDATE bookings SET payment_status = 'REFUNDED' WHERE booking_id = v_booking_id;
    END IF;

    UPDATE booking_passengers SET passenger_status = 'CANCELLED' WHERE booking_id = v_booking_id;

    UPDATE waiting_list wl
      JOIN booking_passengers bp ON bp.booking_passenger_id = wl.booking_passenger_id
       SET wl.status = 'CANCELLED'
     WHERE bp.booking_id = v_booking_id
       AND wl.status = 'WAITING';

    OPEN cur_allocations;
    alloc_loop: LOOP
        FETCH cur_allocations INTO v_alloc_id, v_coach_id, v_seat_id, v_seat_category;
        IF v_done = 1 THEN
            LEAVE alloc_loop;
        END IF;

        UPDATE seat_allocations
           SET allocation_status = 'RELEASED', released_at = NOW()
         WHERE allocation_id = v_alloc_id;

        CALL sp_promote_waiting_list(v_schedule_id, v_coach_type, v_coach_id, v_seat_id, v_seat_category);
    END LOOP;
    CLOSE cur_allocations;

    UPDATE bookings SET booking_status = 'CANCELLED' WHERE booking_id = v_booking_id;

    INSERT INTO notifications (user_id, booking_id, notification_type, message)
    SELECT user_id, booking_id, 'CANCELLATION',
           CONCAT('Booking ', p_pnr, ' has been cancelled. Refund amount: ', v_refund, '.')
      FROM bookings WHERE booking_id = v_booking_id;

    SET p_refund_amount = v_refund;

    COMMIT;
END $$

DELIMITER ;
