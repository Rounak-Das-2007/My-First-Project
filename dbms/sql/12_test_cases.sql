-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 12_test_cases.sql
-- Purpose: Positive and negative test cases. Every negative test is expected
-- to raise an error (SIGNAL or constraint violation) and change nothing.
-- Run each block independently and inspect the result/error shown.
-- =============================================================================

USE railflow_db;

-- =============================================================================
-- SECTION 1 — POSITIVE TESTS
-- =============================================================================

-- T01. Create user
INSERT INTO users (full_name, email, phone, password_hash, role)
VALUES ('Test User One', 'test.positive.user@demo.com', '+919811111101', '$2b$12$testhashvalue0000000000000000001', 'CUSTOMER');
SELECT user_id, email, role FROM users WHERE email = 'test.positive.user@demo.com';

-- T02. Create passenger
INSERT INTO passengers (user_id, full_name, date_of_birth, gender, id_document_type, id_document_number)
VALUES (LAST_INSERT_ID(), 'Test Passenger One', '1994-06-15', 'FEMALE', 'AADHAAR', '999911112222');
SELECT passenger_id, full_name FROM passengers WHERE id_document_number = '999911112222';

-- T03. Create station
INSERT INTO stations (station_code, station_name, city, state)
VALUES ('TSTX', 'Test Junction', 'Test City', 'Test State');
SELECT station_id, station_code FROM stations WHERE station_code = 'TSTX';

-- T04. Create train
INSERT INTO trains (train_number, train_name, train_type, source_station_id, destination_station_id)
SELECT '99999', 'Test Express', 'EXPRESS', 1, station_id FROM stations WHERE station_code = 'TSTX';
SELECT train_id, train_number FROM trains WHERE train_number = '99999';

-- T05. Create route
INSERT INTO train_routes (train_id, station_id, sequence_order, departure_time, distance_from_origin_km)
SELECT train_id, 1, 1, '10:00:00', 0.00 FROM trains WHERE train_number = '99999';
INSERT INTO train_routes (train_id, station_id, sequence_order, arrival_time, distance_from_origin_km)
SELECT t.train_id, s.station_id, 2, '14:00:00', 250.00
  FROM trains t JOIN stations s ON s.station_code = 'TSTX' WHERE t.train_number = '99999';
SELECT route_id, sequence_order FROM train_routes WHERE train_id = (SELECT train_id FROM trains WHERE train_number = '99999');

-- T06. Create schedule
INSERT INTO train_schedules (train_id, journey_date, departure_datetime, arrival_datetime)
SELECT train_id, CURDATE() + INTERVAL 20 DAY,
       CONCAT(CURDATE() + INTERVAL 20 DAY, ' 10:00:00'),
       CONCAT(CURDATE() + INTERVAL 20 DAY, ' 14:00:00')
  FROM trains WHERE train_number = '99999';
SELECT schedule_id, journey_date FROM train_schedules WHERE train_id = (SELECT train_id FROM trains WHERE train_number = '99999');

-- T07. Create coach
INSERT INTO coaches (train_id, coach_number, coach_type, total_seats)
SELECT train_id, 'T1', 'SL', 4 FROM trains WHERE train_number = '99999';
SELECT coach_id, coach_number FROM coaches WHERE coach_number = 'T1'
  AND train_id = (SELECT train_id FROM trains WHERE train_number = '99999');

-- T08. Create seats
INSERT INTO seats (coach_id, seat_number, seat_type, seat_category)
SELECT coach_id, '1', 'LOWER', 'REGULAR' FROM coaches WHERE coach_number = 'T1'
  AND train_id = (SELECT train_id FROM trains WHERE train_number = '99999');
INSERT INTO seats (coach_id, seat_number, seat_type, seat_category)
SELECT coach_id, '2', 'UPPER', 'REGULAR' FROM coaches WHERE coach_number = 'T1'
  AND train_id = (SELECT train_id FROM trains WHERE train_number = '99999');
SELECT COUNT(*) AS seats_created FROM seats WHERE coach_id = (
    SELECT coach_id FROM coaches WHERE coach_number = 'T1'
      AND train_id = (SELECT train_id FROM trains WHERE train_number = '99999'));

-- (fare row needed before a booking can be made against this test train)
INSERT INTO fares (train_id, coach_type, source_station_id, destination_station_id, base_fare, reservation_charge, gst_charge, effective_from)
SELECT t.train_id, 'SL', 1, s.station_id, 500.00, 20.00, 20.00, '2026-01-01'
  FROM trains t JOIN stations s ON s.station_code = 'TSTX' WHERE t.train_number = '99999';

-- T09. Create booking (single passenger)
CALL sp_book_ticket(
    (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com'),
    (SELECT train_id FROM trains WHERE train_number = '99999'),
    (SELECT schedule_id FROM train_schedules WHERE train_id = (SELECT train_id FROM trains WHERE train_number = '99999')),
    1,
    (SELECT station_id FROM stations WHERE station_code = 'TSTX'),
    'SL',
    JSON_ARRAY(JSON_OBJECT('passenger_id', (SELECT passenger_id FROM passengers WHERE id_document_number = '999911112222'), 'age', 31)),
    @t09_pnr, @t09_status, @t09_fare
);
SELECT @t09_pnr AS pnr, @t09_status AS status, @t09_fare AS fare;

-- T10. Multi-passenger booking (reuses passenger 1 and 2 from seed data)
CALL sp_book_ticket(
    (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com'),
    (SELECT train_id FROM trains WHERE train_number = '99999'),
    (SELECT schedule_id FROM train_schedules WHERE train_id = (SELECT train_id FROM trains WHERE train_number = '99999')),
    1,
    (SELECT station_id FROM stations WHERE station_code = 'TSTX'),
    'SL',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36), JSON_OBJECT('passenger_id', 2, 'age', 31)),
    @t10_pnr, @t10_status, @t10_fare
);
SELECT @t10_pnr AS pnr, @t10_status AS status, @t10_fare AS fare;

-- T11. Successful payment
CALL sp_process_payment(
    (SELECT booking_id FROM bookings WHERE pnr = @t09_pnr),
    @t09_fare, 'UPI', CONCAT('TXN-T09-', UNIX_TIMESTAMP()), TRUE
);
SELECT payment_status FROM bookings WHERE pnr = @t09_pnr;

-- T12. Cancellation
CALL sp_cancel_booking(@t09_pnr, (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com'), 'Positive test cancellation', @t12_refund);
SELECT @t12_refund AS refund_amount, booking_status FROM bookings WHERE pnr = @t09_pnr;

-- T13. Refund exists and is non-negative
SELECT refund_id, refund_amount, refund_status FROM refunds r
  JOIN cancellations c ON c.cancellation_id = r.cancellation_id
  JOIN bookings b ON b.booking_id = c.booking_id
 WHERE b.pnr = @t09_pnr;

-- T14. Waiting-list promotion already demonstrated end-to-end in
-- 11_transactions.sql (Scenario A cancellation promotes an active RAC
-- passenger to CONFIRMED and a waiting-list passenger into the vacated
-- RAC seat). Re-verify the resulting state here:
SELECT status, waitlist_position FROM waiting_list ORDER BY waitlist_id;


-- =============================================================================
-- SECTION 2 — NEGATIVE TESTS (each statement is expected to fail)
-- =============================================================================

-- N01. Duplicate email
INSERT INTO users (full_name, email, phone, password_hash)
VALUES ('Duplicate Email User', 'test.positive.user@demo.com', '+919811111199', '$2b$12$dupe');
-- Expected: ERROR 1062 Duplicate entry ... for key 'uq_users_email'

-- N02. Invalid phone format
INSERT INTO users (full_name, email, phone, password_hash)
VALUES ('Bad Phone User', 'bad.phone@demo.com', 'not-a-phone', '$2b$12$dupe');
-- Expected: ERROR 3819 Check constraint 'chk_users_phone' is violated

-- N03. Duplicate station code
INSERT INTO stations (station_code, station_name, city, state)
VALUES ('TSTX', 'Duplicate Code Station', 'Somewhere', 'Nowhere');
-- Expected: ERROR 1062 Duplicate entry 'TSTX' for key 'uq_station_code'

-- N04. Duplicate train number
INSERT INTO trains (train_number, train_name, train_type, source_station_id, destination_station_id)
VALUES ('99999', 'Duplicate Number Train', 'EXPRESS', 1, 3);
-- Expected: ERROR 1062 Duplicate entry '99999' for key 'uq_train_number'

-- N05. Same origin and destination
INSERT INTO trains (train_number, train_name, train_type, source_station_id, destination_station_id)
VALUES ('88888', 'Same Station Train', 'EXPRESS', 1, 1);
-- Expected: ERROR 3819 Check constraint 'chk_train_source_dest_diff' is violated

-- N06. Invalid station on a route (non-existent station_id)
INSERT INTO train_routes (train_id, station_id, sequence_order, departure_time, distance_from_origin_km)
VALUES ((SELECT train_id FROM trains WHERE train_number = '99999'), 999999, 5, '09:00:00', 0.00);
-- Expected: ERROR 1452 Cannot add or update a child row (fk_route_station)

-- N07. Reversed / invalid station order inside a booking
CALL sp_book_ticket(
    (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com'),
    (SELECT train_id FROM trains WHERE train_number = '99999'),
    (SELECT schedule_id FROM train_schedules WHERE train_id = (SELECT train_id FROM trains WHERE train_number = '99999')),
    (SELECT station_id FROM stations WHERE station_code = 'TSTX'),
    1,
    'SL',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n07_pnr, @n07_status, @n07_fare
);
-- Expected: SIGNAL 'Invalid route: destination must come after source...'

-- N08. Invalid journey date (schedule already completed / in the past)
CALL sp_book_ticket(
    3, 1,
    (SELECT schedule_id FROM train_schedules WHERE status = 'COMPLETED' LIMIT 1),
    2, 1, '3A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n08_pnr, @n08_status, @n08_fare
);
-- Expected: SIGNAL 'Train does not operate on the selected date.'

-- N09. Unavailable / inactive train
CALL sp_book_ticket(
    3, (SELECT train_id FROM trains WHERE train_number = '19012'),
    1, 2, 7, 'SL',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n09_pnr, @n09_status, @n09_fare
);
-- Expected: SIGNAL 'Train is not in active operation.'

-- N10. Inactive station used as source/destination
CALL sp_book_ticket(
    3, 1, 1,
    (SELECT station_id FROM stations WHERE station_code = 'OLDJN'),
    1, '3A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n10_pnr, @n10_status, @n10_fare
);
-- Expected: SIGNAL 'Source or destination station is inactive.'

-- N11. Inactive seat directly allocated (bypassing the procedure entirely)
INSERT INTO seat_allocations (booking_passenger_id, schedule_id, coach_id, seat_id, allocation_status)
SELECT bp.booking_passenger_id, 1, s.coach_id, s.seat_id, 'ACTIVE'
  FROM seats s
  JOIN booking_passengers bp ON bp.passenger_status IN ('WAITLISTED', 'CANCELLED')
 WHERE s.status = 'INACTIVE'
 LIMIT 1;
-- Expected: SIGNAL 'Cannot allocate an inactive seat.'

-- N12. Duplicate seat allocation (a waitlisted passenger, who holds no active
-- allocation, directly attempts to grab a seat that is already active for
-- someone else on the same schedule)
INSERT INTO seat_allocations (booking_passenger_id, schedule_id, coach_id, seat_id, allocation_status)
SELECT bp.booking_passenger_id, sa.schedule_id, sa.coach_id, sa.seat_id, 'ACTIVE'
  FROM seat_allocations sa
  JOIN booking_passengers bp ON bp.passenger_status IN ('WAITLISTED', 'CANCELLED')
 WHERE sa.allocation_status = 'ACTIVE'
 LIMIT 1;
-- Expected: ERROR 1062 Duplicate entry ... for key 'uq_allocation_active_seat'

-- N13. Negative fare
INSERT INTO fares (train_id, coach_type, source_station_id, destination_station_id, base_fare, effective_from)
VALUES ((SELECT train_id FROM trains WHERE train_number = '99999'), 'SL', 1, 3, -100.00, '2026-01-01');
-- Expected: ERROR 3819 Check constraint 'chk_fare_base_non_negative' is violated

-- N14. Duplicate PNR (direct attempt, bypassing fn_generate_pnr)
INSERT INTO bookings (
    pnr, user_id, train_id, schedule_id, source_station_id, destination_station_id,
    coach_type, journey_date, total_passengers, total_fare
)
SELECT pnr, user_id, train_id, schedule_id, source_station_id, destination_station_id,
       coach_type, journey_date, total_passengers, total_fare
  FROM bookings LIMIT 1;
-- Expected: ERROR 1062 Duplicate entry ... for key 'uq_booking_pnr'

-- N15. Cancellation of an already-cancelled booking
CALL sp_cancel_booking(@t09_pnr, 3, 'Trying to cancel again', @n15_refund);
-- Expected: SIGNAL 'Booking has already been cancelled.'

-- N16. Negative refund attempted directly
INSERT INTO refunds (cancellation_id, booking_id, refund_amount, refund_status)
SELECT cancellation_id, booking_id, -50.00, 'PENDING' FROM cancellations LIMIT 1;
-- Expected: ERROR 3819 Check constraint 'chk_refund_amount_non_negative' is violated

-- N17. Inactive user attempting to book
UPDATE users SET account_status = 'INACTIVE' WHERE email = 'test.positive.user@demo.com';
CALL sp_book_ticket(
    (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com'),
    1, 1, 2, 1, '3A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n17_pnr, @n17_status, @n17_fare
);
-- Expected: SIGNAL 'Inactive users cannot create new bookings.'

-- N18. Duplicate booking of the exact same passenger within one booking call
CALL sp_book_ticket(
    3, 1, 1, 2, 1, '3A',
    JSON_ARRAY(JSON_OBJECT('passenger_id', 1, 'age', 36), JSON_OBJECT('passenger_id', 1, 'age', 36)),
    @n18_pnr, @n18_status, @n18_fare
);
-- Expected: ERROR 1062 Duplicate entry ... for key 'uq_booking_passenger'

-- N19. Future date of birth
INSERT INTO passengers (full_name, date_of_birth, gender, id_document_type, id_document_number)
VALUES ('Time Traveler', '2099-01-01', 'MALE', 'AADHAAR', '000000000001');
-- Expected: SIGNAL 'Passenger date of birth cannot be in the future.'

-- N20. Reverting a cancelled booking's status directly
UPDATE bookings SET booking_status = 'CONFIRMED' WHERE pnr = @t09_pnr;
-- Expected: SIGNAL 'Cannot change the status of a cancelled booking.'
