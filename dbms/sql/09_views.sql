-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 09_views.sql
-- Purpose: Reporting views with clear, business-friendly column names.
-- =============================================================================

USE railflow_db;

-- -----------------------------------------------------------------------------
-- available_seats_view — per coach, per schedule, current availability
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW available_seats_view AS
SELECT
    ts.schedule_id,
    ts.journey_date,
    t.train_id,
    t.train_number,
    t.train_name,
    c.coach_id,
    c.coach_number,
    c.coach_type,
    c.total_seats,
    fn_available_seats(ts.schedule_id, c.coach_id) AS available_seats,
    fn_occupancy_percentage(ts.schedule_id, c.coach_id) AS occupancy_percent
FROM train_schedules ts
JOIN trains t ON t.train_id = ts.train_id
JOIN coaches c ON c.train_id = t.train_id
WHERE c.status = 'ACTIVE';

-- -----------------------------------------------------------------------------
-- booking_details_view — one row per booking with route/train context
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW booking_details_view AS
SELECT
    b.booking_id,
    b.pnr,
    u.full_name        AS booked_by,
    u.email             AS booked_by_email,
    t.train_number,
    t.train_name,
    src.station_name    AS source_station,
    dst.station_name    AS destination_station,
    b.coach_type,
    b.journey_date,
    b.booking_datetime,
    b.total_passengers,
    b.total_fare,
    b.booking_status,
    b.payment_status
FROM bookings b
JOIN users u ON u.user_id = b.user_id
JOIN trains t ON t.train_id = b.train_id
JOIN stations src ON src.station_id = b.source_station_id
JOIN stations dst ON dst.station_id = b.destination_station_id;

-- -----------------------------------------------------------------------------
-- passenger_booking_history_view — every journey a passenger has taken/booked
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW passenger_booking_history_view AS
SELECT
    p.passenger_id,
    p.full_name        AS passenger_name,
    b.pnr,
    t.train_number,
    t.train_name,
    b.journey_date,
    b.coach_type,
    bp.fare_component,
    bp.passenger_status,
    sa.seat_id,
    s.seat_number,
    s.seat_type
FROM booking_passengers bp
JOIN passengers p ON p.passenger_id = bp.passenger_id
JOIN bookings b ON b.booking_id = bp.booking_id
JOIN trains t ON t.train_id = b.train_id
LEFT JOIN seat_allocations sa
       ON sa.booking_passenger_id = bp.booking_passenger_id
      AND sa.allocation_status = 'ACTIVE'
LEFT JOIN seats s ON s.seat_id = sa.seat_id;

-- -----------------------------------------------------------------------------
-- train_occupancy_view — occupancy per train per schedule (all classes combined)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW train_occupancy_view AS
SELECT
    ts.schedule_id,
    ts.journey_date,
    t.train_id,
    t.train_number,
    t.train_name,
    SUM(c.total_seats) AS total_capacity,
    SUM(fn_available_seats(ts.schedule_id, c.coach_id)) AS total_available,
    SUM(c.total_seats) - SUM(fn_available_seats(ts.schedule_id, c.coach_id)) AS total_occupied,
    ROUND(
        (SUM(c.total_seats) - SUM(fn_available_seats(ts.schedule_id, c.coach_id))) / SUM(c.total_seats) * 100,
        2
    ) AS occupancy_percent
FROM train_schedules ts
JOIN trains t ON t.train_id = ts.train_id
JOIN coaches c ON c.train_id = t.train_id
WHERE c.status = 'ACTIVE'
GROUP BY ts.schedule_id, ts.journey_date, t.train_id, t.train_number, t.train_name;

-- -----------------------------------------------------------------------------
-- route_revenue_view — revenue collected per source/destination pair
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW route_revenue_view AS
SELECT
    src.station_code    AS source_code,
    src.station_name    AS source_station,
    dst.station_code    AS destination_code,
    dst.station_name    AS destination_station,
    COUNT(DISTINCT b.booking_id) AS total_bookings,
    SUM(p.amount)                AS gross_revenue
FROM bookings b
JOIN stations src ON src.station_id = b.source_station_id
JOIN stations dst ON dst.station_id = b.destination_station_id
JOIN payments p ON p.booking_id = b.booking_id AND p.payment_status = 'SUCCESS'
GROUP BY src.station_code, src.station_name, dst.station_code, dst.station_name;

-- -----------------------------------------------------------------------------
-- daily_revenue_view — successful payments collected per calendar day
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW daily_revenue_view AS
SELECT
    DATE(p.payment_datetime) AS revenue_date,
    COUNT(*)                  AS successful_payments,
    SUM(p.amount)              AS gross_revenue
FROM payments p
WHERE p.payment_status = 'SUCCESS'
GROUP BY DATE(p.payment_datetime);

-- -----------------------------------------------------------------------------
-- waiting_list_status_view — current waiting-list queue per schedule/class
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW waiting_list_status_view AS
SELECT
    wl.waitlist_id,
    ts.journey_date,
    t.train_number,
    t.train_name,
    wl.coach_type,
    wl.waitlist_position,
    wl.status,
    p.full_name        AS passenger_name,
    b.pnr
FROM waiting_list wl
JOIN booking_passengers bp ON bp.booking_passenger_id = wl.booking_passenger_id
JOIN bookings b ON b.booking_id = bp.booking_id
JOIN passengers p ON p.passenger_id = bp.passenger_id
JOIN train_schedules ts ON ts.schedule_id = wl.schedule_id
JOIN trains t ON t.train_id = ts.train_id;

-- -----------------------------------------------------------------------------
-- cancellation_summary_view — cancellation and refund detail per booking
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW cancellation_summary_view AS
SELECT
    c.cancellation_id,
    b.pnr,
    u.full_name        AS cancelled_by_customer,
    c.cancellation_datetime,
    c.cancellation_reason,
    c.refundable_amount,
    c.cancellation_charge,
    r.refund_status,
    r.refund_amount,
    r.refund_datetime
FROM cancellations c
JOIN bookings b ON b.booking_id = c.booking_id
JOIN users u ON u.user_id = b.user_id
LEFT JOIN refunds r ON r.cancellation_id = c.cancellation_id;
