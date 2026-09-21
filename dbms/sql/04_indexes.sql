-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 04_indexes.sql
-- Purpose: Secondary indexes for real query patterns (search, filtering,
-- reporting). Columns already covered by a UNIQUE/PK/FK index are skipped.
-- =============================================================================

USE railflow_db;

-- Station search by name (city/state search reuses this composite well enough
-- for a demo dataset; a dedicated index is added if profiling shows the need).
CREATE INDEX idx_stations_name ON stations (station_name);
CREATE INDEX idx_stations_city ON stations (city);

-- Train lookup and route-based search (find trains between two stations).
CREATE INDEX idx_trains_source_dest ON trains (source_station_id, destination_station_id);

-- Route lookups drive "which stations does this train pass through" and
-- "which trains stop at this station" queries.
CREATE INDEX idx_routes_station ON train_routes (station_id);

-- Schedules are always searched by journey date, and status is a common filter.
CREATE INDEX idx_schedules_journey_date ON train_schedules (journey_date);
CREATE INDEX idx_schedules_status ON train_schedules (status);

-- Coach/seat browsing within a train and by class.
CREATE INDEX idx_coaches_type ON coaches (coach_type);

-- Fare lookup by route/class is the hot path of fare calculation.
CREATE INDEX idx_fares_lookup ON fares (train_id, coach_type, source_station_id, destination_station_id, status);

-- Booking search patterns: by customer, by date, by status.
CREATE INDEX idx_bookings_user ON bookings (user_id);
CREATE INDEX idx_bookings_journey_date ON bookings (journey_date);
CREATE INDEX idx_bookings_status ON bookings (booking_status);
CREATE INDEX idx_bookings_payment_status ON bookings (payment_status);
CREATE INDEX idx_bookings_schedule ON bookings (schedule_id);

-- Passenger-history queries join through this table by passenger.
CREATE INDEX idx_bp_passenger ON booking_passengers (passenger_id);
CREATE INDEX idx_bp_status ON booking_passengers (passenger_status);

-- Seat occupancy / availability checks filter by schedule + coach + status.
CREATE INDEX idx_alloc_schedule_coach ON seat_allocations (schedule_id, coach_id, allocation_status);

-- Payment reconciliation by status and by booking.
CREATE INDEX idx_payments_status ON payments (payment_status);

-- Waiting-list promotion always scans the next eligible position per journey/class.
CREATE INDEX idx_waitlist_schedule_class_status ON waiting_list (schedule_id, coach_type, status, waitlist_position);

-- Audit trail is queried by the entity it describes.
CREATE INDEX idx_audit_table_record ON audit_logs (table_name, record_id);

-- Notification inbox queries filter unread items per user.
CREATE INDEX idx_notifications_user_unread ON notifications (user_id, is_read);
