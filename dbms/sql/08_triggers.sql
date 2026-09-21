-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 08_triggers.sql
-- Purpose: Triggers that provide genuine database-level protection beyond
-- what CHECK constraints and procedures already guarantee. Kept minimal and
-- non-chaining by design.
-- =============================================================================

USE railflow_db;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- Date-of-birth validity cannot be expressed as a CHECK constraint because
-- MySQL forbids non-deterministic functions such as CURDATE() there.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_passengers_validate_dob_bi
BEFORE INSERT ON passengers
FOR EACH ROW
BEGIN
    IF NEW.date_of_birth > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
    IF NEW.date_of_birth < DATE_SUB(CURDATE(), INTERVAL 130 YEAR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger date of birth is not plausible.';
    END IF;
END $$

CREATE TRIGGER trg_passengers_validate_dob_bu
BEFORE UPDATE ON passengers
FOR EACH ROW
BEGIN
    IF NEW.date_of_birth > CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
    IF NEW.date_of_birth < DATE_SUB(CURDATE(), INTERVAL 130 YEAR) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Passenger date of birth is not plausible.';
    END IF;
END $$

-- -----------------------------------------------------------------------------
-- Once a booking is CANCELLED or COMPLETED it is a closed historical record;
-- this is a final database-level barrier independent of which client or
-- procedure attempts the update.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_bookings_prevent_invalid_transition
BEFORE UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF OLD.booking_status = 'CANCELLED' AND NEW.booking_status <> 'CANCELLED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change the status of a cancelled booking.';
    END IF;
    IF OLD.booking_status = 'COMPLETED' AND NEW.booking_status NOT IN ('COMPLETED', 'CANCELLED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot revert a completed booking to a pre-travel status.';
    END IF;
END $$

-- -----------------------------------------------------------------------------
-- Append-only audit trail of booking status transitions.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_bookings_audit_au
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF NEW.booking_status <> OLD.booking_status OR NEW.payment_status <> OLD.payment_status THEN
        INSERT INTO audit_logs (table_name, record_id, action_type, performed_by, old_value, new_value)
        VALUES (
            'bookings', NEW.booking_id, 'UPDATE', NULL,
            JSON_OBJECT('booking_status', OLD.booking_status, 'payment_status', OLD.payment_status),
            JSON_OBJECT('booking_status', NEW.booking_status, 'payment_status', NEW.payment_status)
        );
    END IF;
END $$

-- -----------------------------------------------------------------------------
-- Audit trail for cancellations, independent of the bookings-status audit
-- above, since a cancellation carries financial fields worth preserving.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_cancellations_audit_ai
AFTER INSERT ON cancellations
FOR EACH ROW
BEGIN
    INSERT INTO audit_logs (table_name, record_id, action_type, performed_by, old_value, new_value)
    VALUES (
        'cancellations', NEW.cancellation_id, 'INSERT', NEW.cancelled_by,
        NULL,
        JSON_OBJECT('booking_id', NEW.booking_id, 'refundable_amount', NEW.refundable_amount, 'cancellation_charge', NEW.cancellation_charge)
    );
END $$

-- -----------------------------------------------------------------------------
-- Notify the customer the moment a payment succeeds or fails.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_payments_notify_au
AFTER UPDATE ON payments
FOR EACH ROW
BEGIN
    IF NEW.payment_status <> OLD.payment_status AND NEW.payment_status IN ('SUCCESS', 'FAILED') THEN
        INSERT INTO notifications (user_id, booking_id, notification_type, message)
        SELECT b.user_id, b.booking_id, 'PAYMENT',
               CONCAT('Payment ', NEW.payment_status, ' for booking ', b.pnr, ' (amount ', NEW.amount, ').')
          FROM bookings b
         WHERE b.booking_id = NEW.booking_id;
    END IF;
END $$

CREATE TRIGGER trg_payments_notify_ai
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    IF NEW.payment_status IN ('SUCCESS', 'FAILED') THEN
        INSERT INTO notifications (user_id, booking_id, notification_type, message)
        SELECT b.user_id, b.booking_id, 'PAYMENT',
               CONCAT('Payment ', NEW.payment_status, ' for booking ', b.pnr, ' (amount ', NEW.amount, ').')
          FROM bookings b
         WHERE b.booking_id = NEW.booking_id;
    END IF;
END $$

-- -----------------------------------------------------------------------------
-- Final database-level barrier against allocating an inactive seat or a seat
-- in an inactive coach, independent of whatever application code performed
-- the INSERT (sp_book_ticket already filters these out when searching, but
-- this trigger protects direct/administrative inserts too).
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_seat_allocations_validate_bi
BEFORE INSERT ON seat_allocations
FOR EACH ROW
BEGIN
    DECLARE v_seat_status VARCHAR(10);
    DECLARE v_coach_status VARCHAR(10);

    IF NEW.allocation_status = 'ACTIVE' THEN
        SELECT s.status, c.status INTO v_seat_status, v_coach_status
          FROM seats s
          JOIN coaches c ON c.coach_id = s.coach_id
         WHERE s.seat_id = NEW.seat_id;

        IF v_seat_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot allocate an inactive seat.';
        END IF;
        IF v_coach_status <> 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot allocate a seat in an inactive coach.';
        END IF;
    END IF;
END $$

DELIMITER ;
