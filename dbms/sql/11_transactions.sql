-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 11_transactions.sql
-- Purpose: End-to-end DEMO / SAMPLE transactional data (bookings, payments,
-- cancellations, refunds, waiting-list activity), produced by actually
-- calling the stored procedures in 07_procedures.sql rather than being
-- inserted directly — this is the real business logic in action, not a
-- shortcut. This data is fictional and does not represent live railway
-- information.
-- =============================================================================

USE railflow_db;

-- -----------------------------------------------------------------------------
-- Scenario A — Mumbai Rajdhani (train 1), schedule 1, class 3A, capacity 8
-- (6 REGULAR + 2 RAC seats per the seed data). Booking 9 passengers here
-- deliberately exhausts REGULAR and RAC capacity so the system produces a
-- real CONFIRMED / RAC / WAITLISTED mix, not hand-picked statuses.
-- -----------------------------------------------------------------------------
CALL sp_book_ticket(3, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),  @a_pnr1, @a_st1, @a_fare1);
CALL sp_book_ticket(4, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 2, 'age', 31)),  @a_pnr2, @a_st2, @a_fare2);
CALL sp_book_ticket(5, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 3, 'age', 38)),  @a_pnr3, @a_st3, @a_fare3);
CALL sp_book_ticket(6, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 4, 'age', 26)),  @a_pnr4, @a_st4, @a_fare4);
CALL sp_book_ticket(7, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 5, 'age', 51)),  @a_pnr5, @a_st5, @a_fare5);
CALL sp_book_ticket(8, 1, 1, 2, 1, '3A',
     JSON_ARRAY(JSON_OBJECT('passenger_id', 7, 'age', 64), JSON_OBJECT('passenger_id', 8, 'age', 11)),
     @a_pnr6, @a_st6, @a_fare6);
CALL sp_book_ticket(3, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 9, 'age', 33)),  @a_pnr7, @a_st7, @a_fare7);
CALL sp_book_ticket(4, 1, 1, 2, 1, '3A', JSON_ARRAY(JSON_OBJECT('passenger_id', 10, 'age', 41)), @a_pnr8, @a_st8, @a_fare8);

-- Successful payments for the CONFIRMED bookings, one deliberately FAILED.
CALL sp_process_payment(1, @a_fare1, 'UPI',         'TXN-A0001-UPI', TRUE);
CALL sp_process_payment(2, @a_fare2, 'CREDIT_CARD', 'TXN-A0002-CC',  TRUE);
CALL sp_process_payment(3, @a_fare3, 'DEBIT_CARD',  'TXN-A0003-DC',  TRUE);
CALL sp_process_payment(4, @a_fare4, 'NET_BANKING', 'TXN-A0004-NB',  FALSE);
CALL sp_process_payment(4, @a_fare4, 'UPI',         'TXN-A0004-UPI-RETRY', TRUE);
CALL sp_process_payment(5, @a_fare5, 'WALLET',      'TXN-A0005-WAL', TRUE);

-- Cancel booking 2 (unpaid at cancellation time is not the case here — it is
-- paid — this is the scenario that exercises a real refund calculation) and
-- let the cancellation cascade promote the RAC and waiting-list passengers.
CALL sp_cancel_booking('PNR0000002', 4, 'Change of travel plans', @a_refund2);

-- -----------------------------------------------------------------------------
-- Scenario B — Howrah Rajdhani (train 2), schedule 3, class 2A: a simple
-- confirmed multi-passenger family booking, fully paid, no cancellation.
-- -----------------------------------------------------------------------------
CALL sp_book_ticket(
    5, 2, 3, 4, 1, '2A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 3, 'age', 38), JSON_OBJECT('passenger_id', 9, 'age', 33)),
    @b_pnr, @b_status, @b_fare
);
CALL sp_process_payment(9, @b_fare, 'CREDIT_CARD', 'TXN-B0001-CC', TRUE);

-- -----------------------------------------------------------------------------
-- Scenario C — Tamil Nadu Express (train 3), schedule 4, class SL: a booking
-- that is made, paid, and then cancelled well in advance (>48h), producing a
-- low cancellation charge to show the refund-policy tiers in the data.
-- -----------------------------------------------------------------------------
CALL sp_book_ticket(6, 3, 4, 1, 3, 'SL', JSON_ARRAY(JSON_OBJECT('passenger_id', 4, 'age', 26)), @c_pnr, @c_status, @c_fare);
CALL sp_process_payment(10, @c_fare, 'UPI', 'TXN-C0001-UPI', TRUE);
CALL sp_cancel_booking(@c_pnr, 6, 'Illness in the family', @c_refund);

-- -----------------------------------------------------------------------------
-- Scenario D — Bhopal Shatabdi (train 4), schedule 5, class CC: confirmed,
-- unpaid booking (demonstrates PENDING payment_status coexisting with a
-- CONFIRMED seat allocation, which is a valid, expected intermediate state).
-- -----------------------------------------------------------------------------
CALL sp_book_ticket(7, 4, 5, 1, 10, 'CC', JSON_ARRAY(JSON_OBJECT('passenger_id', 5, 'age', 51)), @d_pnr, @d_status, @d_fare);

-- -----------------------------------------------------------------------------
-- Scenario E — KSR Bengaluru Rajdhani (train 5), schedule 6, class 3A: a
-- second family-style multi-passenger confirmed and paid booking.
-- -----------------------------------------------------------------------------
CALL sp_book_ticket(
    8, 5, 6, 5, 1, '3A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 6, 'age', 34), JSON_OBJECT('passenger_id', 3, 'age', 38)),
    @e_pnr, @e_status, @e_fare
);
CALL sp_process_payment(12, @e_fare, 'DEBIT_CARD', 'TXN-E0001-DC', TRUE);

-- -----------------------------------------------------------------------------
-- Verification snapshot — printed for anyone running this file interactively.
-- -----------------------------------------------------------------------------
SELECT 'Scenario A cancellation refund' AS label, @a_refund2 AS value
UNION ALL SELECT 'Scenario C cancellation refund', @c_refund;

SELECT pnr, booking_status, payment_status, total_fare FROM bookings ORDER BY booking_id;
SELECT waitlist_id, booking_passenger_id, coach_type, waitlist_position, status FROM waiting_list ORDER BY waitlist_id;
