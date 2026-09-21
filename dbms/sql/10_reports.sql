-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 10_reports.sql
-- Purpose: Analytical queries for operations and finance reporting. These
-- are ad-hoc SELECTs meant to be run individually, not a schema change.
-- =============================================================================

USE railflow_db;

-- 1. Booking funnel: total / confirmed / RAC / waitlisted / cancelled ---------
SELECT
    COUNT(*)                                         AS total_bookings,
    SUM(booking_status = 'CONFIRMED')                AS confirmed_bookings,
    SUM(booking_status = 'RAC')                       AS rac_bookings,
    SUM(booking_status = 'WAITLISTED')                 AS waitlisted_bookings,
    SUM(booking_status = 'CANCELLED')                   AS cancelled_bookings,
    SUM(booking_status = 'COMPLETED')                     AS completed_bookings
FROM bookings;

-- 2. Revenue summary: gross revenue, refunds issued, net revenue -------------
SELECT
    COALESCE((SELECT SUM(amount) FROM payments WHERE payment_status = 'SUCCESS'), 0)      AS gross_revenue,
    COALESCE((SELECT SUM(refund_amount) FROM refunds WHERE refund_status = 'PROCESSED'), 0) AS total_refunds,
    COALESCE((SELECT SUM(amount) FROM payments WHERE payment_status = 'SUCCESS'), 0)
        - COALESCE((SELECT SUM(refund_amount) FROM refunds WHERE refund_status = 'PROCESSED'), 0) AS net_revenue;

-- 3. Train-wise occupancy (latest schedule per train) -------------------------
SELECT
    train_number,
    train_name,
    journey_date,
    total_capacity,
    total_occupied,
    occupancy_percent
FROM train_occupancy_view
ORDER BY journey_date, train_number;

-- 4. Coach-wise occupancy for a specific schedule (example: schedule_id = 1) --
SELECT
    coach_number,
    coach_type,
    total_seats,
    available_seats,
    occupancy_percent
FROM available_seats_view
WHERE schedule_id = 1
ORDER BY coach_type;

-- 5. Route popularity — most-booked source/destination pairs ------------------
SELECT
    source_station,
    destination_station,
    total_bookings,
    gross_revenue
FROM route_revenue_view
ORDER BY total_bookings DESC, gross_revenue DESC;

-- 6. Station-wise passenger volume (as a source station) ---------------------
SELECT
    st.station_code,
    st.station_name,
    COUNT(*) AS departing_passengers
FROM bookings b
JOIN stations st ON st.station_id = b.source_station_id
JOIN booking_passengers bp ON bp.booking_id = b.booking_id
WHERE bp.passenger_status IN ('CONFIRMED', 'RAC')
GROUP BY st.station_code, st.station_name
ORDER BY departing_passengers DESC;

-- 7. Class-wise revenue --------------------------------------------------------
SELECT
    b.coach_type,
    COUNT(DISTINCT b.booking_id) AS bookings,
    SUM(p.amount)                 AS revenue
FROM bookings b
JOIN payments p ON p.booking_id = b.booking_id AND p.payment_status = 'SUCCESS'
GROUP BY b.coach_type
ORDER BY revenue DESC;

-- 8. Daily revenue trend --------------------------------------------------------
SELECT revenue_date, successful_payments, gross_revenue
FROM daily_revenue_view
ORDER BY revenue_date;

-- 9. Monthly revenue trend -------------------------------------------------------
SELECT
    DATE_FORMAT(payment_datetime, '%Y-%m') AS revenue_month,
    COUNT(*)                                AS successful_payments,
    SUM(amount)                              AS gross_revenue
FROM payments
WHERE payment_status = 'SUCCESS'
GROUP BY DATE_FORMAT(payment_datetime, '%Y-%m')
ORDER BY revenue_month;

-- 10. Top 5 routes by revenue -----------------------------------------------------
SELECT source_station, destination_station, gross_revenue
FROM route_revenue_view
ORDER BY gross_revenue DESC
LIMIT 5;

-- 11. Most-used trains by confirmed+RAC passenger count ---------------------------
SELECT
    t.train_number,
    t.train_name,
    COUNT(*) AS passengers_carried
FROM booking_passengers bp
JOIN bookings b ON b.booking_id = bp.booking_id
JOIN trains t ON t.train_id = b.train_id
WHERE bp.passenger_status IN ('CONFIRMED', 'RAC')
GROUP BY t.train_number, t.train_name
ORDER BY passengers_carried DESC;

-- 12. Cancellation rate (cancelled bookings / total bookings) ----------------------
SELECT
    COUNT(*)                                                        AS total_bookings,
    SUM(booking_status = 'CANCELLED')                                AS cancelled_bookings,
    ROUND(SUM(booking_status = 'CANCELLED') / COUNT(*) * 100, 2)      AS cancellation_rate_percent
FROM bookings;

-- 13. Waiting-list conversion rate (promoted / total ever waitlisted) --------------
SELECT
    COUNT(*)                                              AS total_waitlisted,
    SUM(status = 'PROMOTED')                                AS promoted,
    SUM(status = 'WAITING')                                  AS still_waiting,
    SUM(status IN ('CANCELLED', 'EXPIRED'))                    AS lost,
    ROUND(SUM(status = 'PROMOTED') / COUNT(*) * 100, 2)          AS conversion_rate_percent
FROM waiting_list;

-- 14. Cancellation summary with refund detail --------------------------------------
SELECT pnr, cancellation_datetime, refundable_amount, cancellation_charge, refund_status, refund_amount
FROM cancellation_summary_view
ORDER BY cancellation_datetime DESC;

-- 15. Passenger-level travel history (example: passenger_id = 3) ------------------
SELECT pnr, train_number, train_name, journey_date, coach_type, passenger_status, seat_number
FROM passenger_booking_history_view
WHERE passenger_id = 3
ORDER BY journey_date DESC;

-- 16. Current waiting-list queue, per schedule and class ---------------------------
SELECT journey_date, train_number, coach_type, waitlist_position, passenger_name, pnr, status
FROM waiting_list_status_view
WHERE status = 'WAITING'
ORDER BY journey_date, train_number, coach_type, waitlist_position;

-- 17. RAC passengers currently holding a shared berth -------------------------------
SELECT b.pnr, p.full_name AS passenger_name, t.train_number, ts.journey_date, s.seat_number
FROM booking_passengers bp
JOIN passengers p ON p.passenger_id = bp.passenger_id
JOIN bookings b ON b.booking_id = bp.booking_id
JOIN trains t ON t.train_id = b.train_id
JOIN train_schedules ts ON ts.schedule_id = b.schedule_id
JOIN seat_allocations sa ON sa.booking_passenger_id = bp.booking_passenger_id AND sa.allocation_status = 'ACTIVE'
JOIN seats s ON s.seat_id = sa.seat_id
WHERE bp.passenger_status = 'RAC'
ORDER BY ts.journey_date;

-- 18. Payment method mix -------------------------------------------------------------
SELECT payment_method, COUNT(*) AS transactions, SUM(amount) AS total_amount
FROM payments
WHERE payment_status = 'SUCCESS'
GROUP BY payment_method
ORDER BY total_amount DESC;
