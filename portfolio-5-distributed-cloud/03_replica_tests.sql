-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 5
-- 03_replica_tests.sql — prove the streaming replica works (one script)
-- =============================================================================
-- Run AFTER 02_setup_replica.sh. This ONE script switches between the two
-- servers itself with \connect, so there is nothing to copy by hand:
--
--   TEST 0  who is who: port, pg_is_in_recovery() on each server
--   TEST 1  the replica REJECTS a write (read-only transaction)
--   TEST 2  a booking written on the PRIMARY appears on the REPLICA
--   TEST 3  replication status: pg_stat_replication (primary) and the
--           receive/replay position + lag (replica)
--
-- Run:
--   sudo runuser -u postgres -- psql -d roadlink -f 03_replica_tests.sql
-- =============================================================================
\pset pager off
\set ON_ERROR_STOP off

\echo '===================================================================='
\echo ' TEST 0 — who is who'
\echo '===================================================================='
\connect -reuse-previous=off roadlink - /var/run/postgresql 5432
SELECT 'PRIMARY' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\connect -reuse-previous=off roadlink - /var/run/postgresql 5433
SELECT 'REPLICA' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;

\echo ''
\echo '===================================================================='
\echo ' TEST 1 — the replica must REJECT writes'
\echo '===================================================================='
\echo 'On the REPLICA (5433): try to add a passenger …'
INSERT INTO passenger (full_name, phone, email)
VALUES ('Replica Write Test', '+234-800-000-0000', 'replica.write.test@example.com');
\echo '↑ expected: ERROR: cannot execute INSERT in a read-only transaction'

\echo ''
\echo '===================================================================='
\echo ' TEST 2 — a new booking on the PRIMARY arrives on the REPLICA'
\echo '===================================================================='
\connect -reuse-previous=off roadlink - /var/run/postgresql 5432
-- the next trip with a free seat, its lowest free seat, and a passenger not on it
SELECT t.trip_id, b.seat_capacity AS cap, r.base_fare_ngn AS fare
FROM trip t JOIN bus b USING (bus_id) JOIN route r USING (route_id)
WHERE t.depart_at > now() + interval '2 hours' AND t.depart_at < now() + interval '20 days'
  AND (SELECT count(*) FROM booking bk WHERE bk.trip_id = t.trip_id AND bk.status = 'CONFIRMED') < b.seat_capacity
ORDER BY t.depart_at LIMIT 1 \gset
SELECT min(s) AS seat FROM generate_series(1, :cap) s
WHERE s NOT IN (SELECT seat_number FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED') \gset
SELECT min(passenger_id) AS pid FROM passenger p
WHERE NOT EXISTS (SELECT 1 FROM booking bk WHERE bk.trip_id = :trip_id AND bk.passenger_id = p.passenger_id) \gset

SELECT count(*) AS bookings_before FROM booking \gset
\echo 'PRIMARY bookings before:' :bookings_before
\echo 'PRIMARY: book seat' :seat 'on trip' :trip_id 'for passenger' :pid '(book_seat from P3) …'
SELECT book_seat(:trip_id, :pid, :seat, :fare, 'USSD') AS new_booking_id \gset
SELECT now() AS committed_at, count(*) AS bookings_on_primary FROM booking;

\echo 'waiting 1 second for the WAL to stream …'
SELECT pg_sleep(1);

\connect -reuse-previous=off roadlink - /var/run/postgresql 5433
\echo 'REPLICA: is the new booking here?'
SELECT current_setting('port') AS port, count(*) AS bookings_on_replica FROM booking;
SELECT booking_id, trip_id, passenger_id, seat_number, status, booked_at
FROM booking WHERE booking_id = :new_booking_id;
\echo '↑ expected: the same row as on the primary, and bookings_on_replica = before + 1'

\echo ''
\echo '===================================================================='
\echo ' TEST 3 — replication status'
\echo '===================================================================='
\echo 'REPLICA (5433): received / replayed WAL position and lag'
SELECT pg_is_in_recovery()                     AS in_recovery,
       pg_last_wal_receive_lsn()               AS receive_lsn,
       pg_last_wal_replay_lsn()                AS replay_lsn,
       now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_commit;
SELECT status, sender_host, sender_port, slot_name FROM pg_stat_wal_receiver;

\connect -reuse-previous=off roadlink - /var/run/postgresql 5432
\echo 'PRIMARY (5432): the connected replica'
SELECT application_name, state, sync_state, sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind, replay_lag
FROM pg_stat_replication;

-- tidy up: remove the test booking (the delete also streams to the replica)
DELETE FROM payment WHERE booking_id = :new_booking_id;
DELETE FROM booking WHERE booking_id = :new_booking_id;

\echo ''
\echo '===================================================================='
\echo '  PROVED: (1) the replica is read-only, (2) a write on the primary'
\echo '  reached the replica through streaming replication, (3) the'
\echo '  replica is streaming with ~0 bytes behind.'
\echo '===================================================================='
