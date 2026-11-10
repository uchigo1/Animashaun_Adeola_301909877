-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 3
-- 02_commit_rollback_demo.sql — a failed payment releases the seat
-- =============================================================================
-- Shows that book_seat() is atomic: if the payment INSERT fails, the booking
-- INSERT that ran just before it is rolled back too, so the seat is NOT lost.
--
--   CASE 1  passenger 1 books free seat X, valid payment   → COMMIT, seat taken
--   CASE 2  passenger 2 books free seat Y, payment ₦0       → ERROR, ROLLBACK
--           → seat Y is still free afterwards
--   CASE 3  passenger 2 books the same seat Y, valid payment → COMMIT
--
-- The demo rows are deleted at the end, so it can be re-run.
--
-- Run:
--   sudo runuser -u postgres -- psql -d roadlink -f 02_commit_rollback_demo.sql
-- =============================================================================

\pset pager off
\set ON_ERROR_STOP off

\echo '===================================================================='
\echo ' COMMIT / ROLLBACK demo — failed payment releases the seat'
\echo '===================================================================='

-- next departing trip that still has at least two free seats
SELECT t.trip_id, b.seat_capacity AS capacity,
       r.base_fare_ngn AS fare,
       tf.city || ' → ' || tt.city AS route,
       to_char(t.depart_at, 'YYYY-MM-DD HH24:MI') AS departs
FROM trip t
JOIN bus b       ON b.bus_id = t.bus_id
JOIN route r     ON r.route_id = t.route_id
JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal tt ON tt.terminal_id = r.to_terminal_id
WHERE t.depart_at > now() + interval '2 hours'
  AND (SELECT count(*) FROM booking bk
        WHERE bk.trip_id = t.trip_id AND bk.status = 'CONFIRMED') <= b.seat_capacity - 2
ORDER BY t.depart_at
LIMIT 1
\gset

-- the two lowest free seat numbers on that trip
SELECT min(s) AS seat_no, max(s) AS seat_no2
FROM (SELECT s FROM generate_series(1, :capacity) AS s
      WHERE s NOT IN (SELECT seat_number FROM booking
                       WHERE trip_id = :trip_id AND status = 'CONFIRMED')
      ORDER BY s LIMIT 2) free
\gset

-- two passengers who are not on this trip
SELECT min(passenger_id) AS pass_id, max(passenger_id) AS pass_id2
FROM (SELECT passenger_id FROM passenger p
      WHERE NOT EXISTS (SELECT 1 FROM booking bk
                         WHERE bk.trip_id = :trip_id AND bk.passenger_id = p.passenger_id)
      ORDER BY passenger_id LIMIT 2) two
\gset

\echo 'Trip       :' :trip_id '(' :route ', departs' :departs ', fare ₦' :fare ')'
\echo 'Passengers :' :pass_id 'and' :pass_id2
\echo 'Free seats :' :seat_no 'and' :seat_no2
\echo ''

\echo 'BEFORE — confirmed bookings on this trip:'
SELECT count(*) AS confirmed_bookings FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';

\echo ''
\echo '--- CASE 1: passenger' :pass_id 'books seat' :seat_no 'and pays ₦' :fare '(valid) ---'
BEGIN;
SELECT book_seat(:trip_id, :pass_id, :seat_no, :fare, 'CARD') AS booking_id;
COMMIT;
SELECT bk.booking_id, bk.passenger_id, bk.seat_number, bk.status, p.amount_ngn, p.status AS payment
FROM booking bk JOIN payment p USING (booking_id)
WHERE bk.trip_id = :trip_id AND bk.seat_number = :seat_no AND bk.status = 'CONFIRMED';

\echo ''
\echo '--- CASE 2: passenger' :pass_id2 'books seat' :seat_no2 'but the payment is ₦0 (invalid) ---'
\echo '    The booking INSERT succeeds, then the payment INSERT breaks'
\echo '    CHECK (amount_ngn > 0) — so the WHOLE transaction must roll back.'
BEGIN;
SELECT book_seat(:trip_id, :pass_id2, :seat_no2, 0.00, 'CARD') AS booking_id;
ROLLBACK;
\echo 'AFTER CASE 2 — is seat' :seat_no2 'taken? (0 rows = no, it was released)'
SELECT booking_id, seat_number, status FROM booking
WHERE trip_id = :trip_id AND seat_number = :seat_no2 AND status = 'CONFIRMED';

\echo ''
\echo '--- CASE 3: passenger' :pass_id2 'tries seat' :seat_no2 'again, valid payment ---'
BEGIN;
SELECT book_seat(:trip_id, :pass_id2, :seat_no2, :fare, 'BANK_TRANSFER') AS booking_id;
COMMIT;
SELECT bk.booking_id, bk.passenger_id, bk.seat_number, bk.status, p.amount_ngn, p.status AS payment
FROM booking bk JOIN payment p USING (booking_id)
WHERE bk.trip_id = :trip_id AND bk.seat_number = :seat_no2 AND bk.status = 'CONFIRMED';

\echo ''
\echo 'AFTER — confirmed bookings on this trip (BEFORE + 2, not + 3):'
SELECT count(*) AS confirmed_bookings FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';

-- clean up the two demo bookings so the demo can be re-run
DELETE FROM payment WHERE booking_id IN (SELECT booking_id FROM booking
    WHERE trip_id = :trip_id AND passenger_id IN (:pass_id, :pass_id2));
DELETE FROM booking WHERE trip_id = :trip_id AND passenger_id IN (:pass_id, :pass_id2);

\echo ''
\echo '===================================================================='
\echo '  Conclusion: the failed payment rolled back the booking as well,'
\echo '  so the seat was released and could be sold again (atomicity).'
\echo '===================================================================='
