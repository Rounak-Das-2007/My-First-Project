-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 13_cleanup.sql
-- Purpose: Removes ONLY the artifacts created by 12_test_cases.sql (the
-- 'TSTX' test station, its train/route/schedule/coach/seats/fare, the test
-- user and passenger, and any bookings made against them) so the database
-- is left in the clean state produced by 01–11. It does not touch the demo
-- reference or transactional data. Run manually and only when needed —
-- never as part of the standard install sequence.
-- =============================================================================

USE railflow_db;

SET @test_train_id  = (SELECT train_id FROM trains WHERE train_number = '99999');
SET @test_station_id = (SELECT station_id FROM stations WHERE station_code = 'TSTX');
SET @test_user_id    = (SELECT user_id FROM users WHERE email = 'test.positive.user@demo.com');

-- Children of bookings first, in dependency order.
DELETE r FROM refunds r
  JOIN cancellations c ON c.cancellation_id = r.cancellation_id
  JOIN bookings b ON b.booking_id = c.booking_id
 WHERE b.train_id = @test_train_id;

DELETE c FROM cancellations c
  JOIN bookings b ON b.booking_id = c.booking_id
 WHERE b.train_id = @test_train_id;

DELETE wl FROM waiting_list wl
  JOIN booking_passengers bp ON bp.booking_passenger_id = wl.booking_passenger_id
  JOIN bookings b ON b.booking_id = bp.booking_id
 WHERE b.train_id = @test_train_id;

DELETE sa FROM seat_allocations sa
  JOIN booking_passengers bp ON bp.booking_passenger_id = sa.booking_passenger_id
  JOIN bookings b ON b.booking_id = bp.booking_id
 WHERE b.train_id = @test_train_id;

DELETE p FROM payments p
  JOIN bookings b ON b.booking_id = p.booking_id
 WHERE b.train_id = @test_train_id;

DELETE bp FROM booking_passengers bp
  JOIN bookings b ON b.booking_id = bp.booking_id
 WHERE b.train_id = @test_train_id;

DELETE FROM bookings WHERE train_id = @test_train_id;

DELETE FROM notifications WHERE user_id = @test_user_id;

DELETE FROM fares WHERE train_id = @test_train_id;
DELETE FROM seats WHERE coach_id IN (SELECT coach_id FROM coaches WHERE train_id = @test_train_id);
DELETE FROM coaches WHERE train_id = @test_train_id;
DELETE FROM train_schedules WHERE train_id = @test_train_id;
DELETE FROM train_routes WHERE train_id = @test_train_id;
DELETE FROM trains WHERE train_id = @test_train_id;
DELETE FROM stations WHERE station_id = @test_station_id;

DELETE FROM passengers WHERE id_document_number IN ('999911112222', '000000000001');
DELETE FROM users WHERE user_id = @test_user_id;

-- -----------------------------------------------------------------------------
-- Full teardown (destructive, commented out by default). Uncomment to drop
-- the entire database — the seed and transactional demo data are not
-- reproducible from this file alone; re-run 01 through 11 to rebuild.
-- -----------------------------------------------------------------------------
-- DROP DATABASE IF EXISTS railflow_db;
