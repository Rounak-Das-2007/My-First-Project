-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 05_seed_data.sql
-- Purpose: DEMO / SAMPLE reference data only (users, passengers, stations,
-- trains, routes, schedules, coaches, seats, fares). This data is fictional
-- and styled after the Indian railway network for realism; it does not
-- represent live railway information. Transactional sample records (bookings,
-- payments, cancellations, refunds, waiting-list entries) are produced later
-- by the actual stored procedures in 11_transactions.sql so that the demo
-- data is a true, verifiable product of the business logic, not a shortcut.
-- =============================================================================

USE railflow_db;

-- -----------------------------------------------------------------------------
-- users
-- -----------------------------------------------------------------------------
INSERT INTO users (
    full_name, email, phone, password_hash, role, account_status
)
VALUES
    ('System Administrator', 'admin@railflow.demo',    '+919810000001', '$2b$12$placeholderhash0000000000000000000000000001', 'ADMIN',    'ACTIVE'),
    ('Reservation Staff One', 'staff1@railflow.demo',   '+919810000002', '$2b$12$placeholderhash0000000000000000000000000002', 'STAFF',    'ACTIVE'),
    ('Aarav Sharma',          'aarav.sharma@demo.com',  '+919810000011', '$2b$12$placeholderhash0000000000000000000000000003', 'CUSTOMER', 'ACTIVE'),
    ('Diya Patel',            'diya.patel@demo.com',    '+919810000012', '$2b$12$placeholderhash0000000000000000000000000004', 'CUSTOMER', 'ACTIVE'),
    ('Vihaan Reddy',          'vihaan.reddy@demo.com',  '+919810000013', '$2b$12$placeholderhash0000000000000000000000000005', 'CUSTOMER', 'ACTIVE'),
    ('Ishita Nair',           'ishita.nair@demo.com',   '+919810000014', '$2b$12$placeholderhash0000000000000000000000000006', 'CUSTOMER', 'ACTIVE'),
    ('Kabir Mehta',           'kabir.mehta@demo.com',   '+919810000015', '$2b$12$placeholderhash0000000000000000000000000007', 'CUSTOMER', 'ACTIVE'),
    ('Saanvi Iyer',           'saanvi.iyer@demo.com',   '+919810000016', '$2b$12$placeholderhash0000000000000000000000000008', 'CUSTOMER', 'ACTIVE'),
    ('Rohan Kapoor',          'rohan.kapoor@demo.com',  '+919810000017', '$2b$12$placeholderhash0000000000000000000000000009', 'CUSTOMER', 'INACTIVE');

-- -----------------------------------------------------------------------------
-- passengers (some linked to a user account, some booked on their behalf)
-- -----------------------------------------------------------------------------
INSERT INTO passengers (
    user_id, full_name, date_of_birth, gender, phone, email,
    id_document_type, id_document_number, status
)
VALUES
    (3, 'Aarav Sharma',   '1990-04-12', 'MALE',   '+919810000011', 'aarav.sharma@demo.com', 'AADHAAR', '111122223333', 'ACTIVE'),
    (4, 'Diya Patel',     '1995-08-23', 'FEMALE', '+919810000012', 'diya.patel@demo.com',   'AADHAAR', '222233334444', 'ACTIVE'),
    (5, 'Vihaan Reddy',   '1988-01-05', 'MALE',   '+919810000013', 'vihaan.reddy@demo.com', 'PASSPORT','K1234567',     'ACTIVE'),
    (6, 'Ishita Nair',    '2000-11-30', 'FEMALE', '+919810000014', 'ishita.nair@demo.com',  'AADHAAR', '333344445555', 'ACTIVE'),
    (7, 'Kabir Mehta',    '1975-06-18', 'MALE',   '+919810000015', 'kabir.mehta@demo.com',  'VOTER_ID','ABC1234567',   'ACTIVE'),
    (8, 'Saanvi Iyer',    '1992-03-09', 'FEMALE', '+919810000016', 'saanvi.iyer@demo.com',  'AADHAAR', '444455556666', 'ACTIVE'),
    (3, 'Meera Sharma',   '1962-09-14', 'FEMALE', NULL,            NULL,                    'AADHAAR', '555566667777', 'ACTIVE'),
    (3, 'Aryan Sharma',   '2015-02-20', 'MALE',   NULL,            NULL,                    'AADHAAR', '666677778888', 'ACTIVE'),
    (4, 'Rahul Patel',    '1993-07-02', 'MALE',   '+919810000018', NULL,                    'DRIVING_LICENSE','DL9988776655', 'ACTIVE'),
    (NULL, 'Guest Traveler One', '1985-05-05', 'MALE', NULL, NULL, 'PAN', 'ABCDE1234F', 'ACTIVE');

-- -----------------------------------------------------------------------------
-- stations
-- -----------------------------------------------------------------------------
INSERT INTO stations (
    station_code, station_name, city, state, status
)
VALUES
    ('NDLS', 'New Delhi',        'New Delhi',  'Delhi',          'ACTIVE'),
    ('BCT',  'Mumbai Central',   'Mumbai',     'Maharashtra',    'ACTIVE'),
    ('MAS',  'Chennai Central',  'Chennai',    'Tamil Nadu',     'ACTIVE'),
    ('HWH',  'Howrah Junction',  'Kolkata',    'West Bengal',    'ACTIVE'),
    ('SBC',  'KSR Bengaluru',    'Bengaluru',  'Karnataka',      'ACTIVE'),
    ('PUNE', 'Pune Junction',    'Pune',       'Maharashtra',    'ACTIVE'),
    ('ADI',  'Ahmedabad Junction','Ahmedabad', 'Gujarat',        'ACTIVE'),
    ('JP',   'Jaipur Junction',  'Jaipur',     'Rajasthan',      'ACTIVE'),
    ('LKO',  'Lucknow Charbagh', 'Lucknow',    'Uttar Pradesh',  'ACTIVE'),
    ('BPL',  'Bhopal Junction',  'Bhopal',     'Madhya Pradesh', 'ACTIVE'),
    ('OLDJN','Retired Junction', 'Nowhere',    'Nowhere',        'INACTIVE');

-- -----------------------------------------------------------------------------
-- trains
-- -----------------------------------------------------------------------------
INSERT INTO trains (
    train_number, train_name, train_type, source_station_id, destination_station_id, status
)
VALUES
    ('12951', 'Mumbai Rajdhani Express',   'RAJDHANI',  2, 1, 'ACTIVE'),
    ('12302', 'Howrah Rajdhani Express',   'RAJDHANI',  4, 1, 'ACTIVE'),
    ('12622', 'Tamil Nadu Express',        'SUPERFAST', 1, 3, 'ACTIVE'),
    ('12002', 'Bhopal Shatabdi Express',   'SHATABDI',  1, 10, 'ACTIVE'),
    ('22692', 'KSR Bengaluru Rajdhani',    'RAJDHANI',  5, 1, 'ACTIVE'),
    ('19012', 'Retired Passenger Train',   'PASSENGER', 2, 7, 'INACTIVE');

-- -----------------------------------------------------------------------------
-- train_routes
-- -----------------------------------------------------------------------------
INSERT INTO train_routes (
    train_id, station_id, sequence_order, arrival_time, departure_time, distance_from_origin_km, halt_minutes
)
VALUES
    -- 12951 Mumbai Rajdhani: BCT(2) -> ADI(7) -> JP(8) -> NDLS(1)
    (1, 2, 1, NULL,       '16:35:00', 0.00,    0),
    (1, 7, 2, '22:40:00', '22:45:00', 491.00,  5),
    (1, 8, 3, '05:15:00', '05:20:00', 1027.00, 5),
    (1, 1, 4, '08:35:00', NULL,       1384.00, 0),

    -- 12302 Howrah Rajdhani: HWH(4) -> BPL(10) -> NDLS(1)
    (2, 4, 1, NULL,       '16:55:00', 0.00,    0),
    (2, 10, 2, '05:44:00', '05:49:00', 1155.00, 5),
    (2, 1, 3, '10:00:00', NULL,       1441.00, 0),

    -- 12622 Tamil Nadu Express: NDLS(1) -> BPL(10) -> MAS(3)
    (3, 1, 1, NULL,       '22:30:00', 0.00,    0),
    (3, 10, 2, '06:05:00', '06:15:00', 707.00,  10),
    (3, 3, 3, '07:15:00', NULL,       2194.00, 0),

    -- 12002 Bhopal Shatabdi: NDLS(1) -> JP... skip; NDLS(1) -> BPL(10)
    (4, 1, 1, NULL,       '06:00:00', 0.00,   0),
    (4, 10, 2, '14:05:00', NULL,      707.00, 0),

    -- 22692 KSR Bengaluru Rajdhani: SBC(5) -> PUNE(6) -> NDLS(1)
    (5, 5, 1, NULL,       '20:00:00', 0.00,    0),
    (5, 6, 2, '08:20:00', '08:25:00', 837.00,  5),
    (5, 1, 3, '05:30:00', NULL,       2365.00, 0);

-- -----------------------------------------------------------------------------
-- train_schedules — a small rolling window of demo journey dates
-- -----------------------------------------------------------------------------
INSERT INTO train_schedules (
    train_id, journey_date, departure_datetime, arrival_datetime, status
)
VALUES
    (1, CURDATE() + INTERVAL 3 DAY,  CONCAT(CURDATE() + INTERVAL 3 DAY, ' 16:35:00'),  CONCAT(CURDATE() + INTERVAL 4 DAY,  ' 08:35:00'), 'SCHEDULED'),
    (1, CURDATE() + INTERVAL 10 DAY, CONCAT(CURDATE() + INTERVAL 10 DAY, ' 16:35:00'), CONCAT(CURDATE() + INTERVAL 11 DAY, ' 08:35:00'), 'SCHEDULED'),
    (2, CURDATE() + INTERVAL 5 DAY,  CONCAT(CURDATE() + INTERVAL 5 DAY, ' 16:55:00'),  CONCAT(CURDATE() + INTERVAL 6 DAY,  ' 10:00:00'), 'SCHEDULED'),
    (3, CURDATE() + INTERVAL 4 DAY,  CONCAT(CURDATE() + INTERVAL 4 DAY, ' 22:30:00'),  CONCAT(CURDATE() + INTERVAL 5 DAY,  ' 07:15:00'), 'SCHEDULED'),
    (4, CURDATE() + INTERVAL 2 DAY,  CONCAT(CURDATE() + INTERVAL 2 DAY, ' 06:00:00'),  CONCAT(CURDATE() + INTERVAL 2 DAY,  ' 14:05:00'), 'SCHEDULED'),
    (5, CURDATE() + INTERVAL 7 DAY,  CONCAT(CURDATE() + INTERVAL 7 DAY, ' 20:00:00'),  CONCAT(CURDATE() + INTERVAL 8 DAY,  ' 05:30:00'), 'SCHEDULED'),
    (1, CURDATE() - INTERVAL 5 DAY,  CONCAT(CURDATE() - INTERVAL 5 DAY, ' 16:35:00'),  CONCAT(CURDATE() - INTERVAL 4 DAY,  ' 08:35:00'), 'COMPLETED');

-- -----------------------------------------------------------------------------
-- coaches — kept deliberately small so waiting-list/RAC demos are reachable
-- -----------------------------------------------------------------------------
INSERT INTO coaches (
    train_id, coach_number, coach_type, total_seats, status
)
VALUES
    (1, 'A1', '3A', 8, 'ACTIVE'),
    (1, 'H1', '1A', 4, 'ACTIVE'),
    (2, 'B1', '3A', 8, 'ACTIVE'),
    (2, 'A1', '2A', 6, 'ACTIVE'),
    (3, 'S1', 'SL', 10, 'ACTIVE'),
    (3, 'B1', '3A', 8, 'ACTIVE'),
    (4, 'C1', 'CC', 10, 'ACTIVE'),
    (5, 'A1', '2A', 6, 'ACTIVE'),
    (5, 'B1', '3A', 8, 'ACTIVE'),
    (6, 'S1', 'SL', 10, 'INACTIVE');

-- -----------------------------------------------------------------------------
-- seats — last two seats of every coach are reserved as the RAC pool
-- -----------------------------------------------------------------------------
INSERT INTO seats (coach_id, seat_number, seat_type, seat_category, status)
SELECT
    c.coach_id,
    n.seat_number,
    ELT(1 + (n.seat_number MOD 4), 'LOWER', 'MIDDLE', 'UPPER', 'SIDE_LOWER'),
    CASE WHEN n.seat_number > c.total_seats - 2 THEN 'RAC' ELSE 'REGULAR' END,
    'ACTIVE'
FROM coaches c
JOIN (
    SELECT 1 AS seat_number UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
    UNION ALL SELECT 9 UNION ALL SELECT 10
) n ON n.seat_number <= c.total_seats
WHERE c.status = 'ACTIVE';

-- Give the deliberately-retired coach seats too, so "inactive coach" tests
-- have real seat rows to attempt against.
INSERT INTO seats (coach_id, seat_number, seat_type, seat_category, status)
SELECT c.coach_id, n.seat_number, 'LOWER', 'REGULAR', 'INACTIVE'
FROM coaches c
JOIN (SELECT 1 AS seat_number UNION ALL SELECT 2 UNION ALL SELECT 3) n
WHERE c.status = 'INACTIVE';

-- -----------------------------------------------------------------------------
-- fares — deterministic base fare matrix for the routes above
-- -----------------------------------------------------------------------------
INSERT INTO fares (
    train_id, coach_type, source_station_id, destination_station_id,
    base_fare, reservation_charge, gst_charge, effective_from, effective_to, status
)
VALUES
    (1, '3A', 2, 1, 2200.00, 40.00, 106.00, '2026-01-01', NULL, 'ACTIVE'),
    (1, '1A', 2, 1, 4500.00, 60.00, 228.00, '2026-01-01', NULL, 'ACTIVE'),
    (2, '3A', 4, 1, 2350.00, 40.00, 111.00, '2026-01-01', NULL, 'ACTIVE'),
    (2, '2A', 4, 1, 3350.00, 50.00, 156.00, '2026-01-01', NULL, 'ACTIVE'),
    (3, 'SL', 1, 3, 950.00,  20.00, 39.00,  '2026-01-01', NULL, 'ACTIVE'),
    (3, '3A', 1, 3, 2450.00, 40.00, 116.00, '2026-01-01', NULL, 'ACTIVE'),
    (4, 'CC', 1, 10, 1150.00, 25.00, 47.00, '2026-01-01', NULL, 'ACTIVE'),
    (5, '2A', 5, 1, 3600.00, 50.00, 164.00, '2026-01-01', NULL, 'ACTIVE'),
    (5, '3A', 5, 1, 2550.00, 40.00, 121.00, '2026-01-01', NULL, 'ACTIVE');
