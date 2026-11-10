-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 4
-- 00_export_from_postgres.sql — export the REAL trips + bookings from P1
-- =============================================================================
-- One JSON line per trip (route, bus, driver, times, and the CONFIRMED
-- passengers with their seat and payment). 02_seed.js reads this file and
-- turns each line into a MongoDB trip-manifest document, and writes reviews
-- only for passengers who really travelled — so the NoSQL data describes the
-- same trips and people as the PostgreSQL database.
--
-- Run (run_p4.sh does this for you):
--   sudo runuser -u postgres -- psql -d roadlink -f 00_export_from_postgres.sql
-- =============================================================================
\set ON_ERROR_STOP on
\copy (SELECT json_build_object('tripId', t.trip_id, 'fromCity', tf.city, 'fromTerminal', tf.name, 'toCity', tt.city, 'toTerminal', tt.name, 'km', r.distance_km, 'fare', r.base_fare_ngn, 'plate', b.plate_number, 'cap', b.seat_capacity, 'model', b.model, 'driver', d.full_name, 'licence', d.license_no, 'departAt', t.depart_at, 'arriveAt', t.arrive_at, 'cancelled', (SELECT count(*) FROM booking c WHERE c.trip_id = t.trip_id AND c.status = 'CANCELLED'), 'passengers', COALESCE((SELECT json_agg(json_build_object('id', bk.passenger_id, 'name', p.full_name, 'phone', p.phone, 'seat', bk.seat_number, 'fare', pay.amount_ngn, 'channel', pay.channel) ORDER BY bk.seat_number) FROM booking bk JOIN passenger p ON p.passenger_id = bk.passenger_id LEFT JOIN payment pay ON pay.booking_id = bk.booking_id WHERE bk.trip_id = t.trip_id AND bk.status = 'CONFIRMED'), '[]'::json)) FROM trip t JOIN route r ON r.route_id = t.route_id JOIN terminal tf ON tf.terminal_id = r.from_terminal_id JOIN terminal tt ON tt.terminal_id = r.to_terminal_id JOIN bus b ON b.bus_id = t.bus_id JOIN driver d ON d.driver_id = t.driver_id WHERE t.depart_at < now() + interval '20 days' ORDER BY t.trip_id) TO '/tmp/roadlink_trips.jsonl'
SELECT count(*) AS trips_exported FROM trip WHERE depart_at < now() + interval '20 days';
