-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 1
-- 05_constraint_tests.sql — every constraint that MUST FAIL
-- =============================================================================
-- Each bad INSERT runs inside _p1_test(), which catches the error and prints
-- PASS (the database rejected the bad row) or FAIL (the bad row was
-- accepted — a bug). Every test builds its OWN data (a test trip 60 days
-- ahead, test passengers, one valid booking + payment) so it never depends on
-- the bulk data, and the WHOLE script runs inside BEGIN … ROLLBACK, so the
-- 50k+ generated rows are left exactly as they were.
--
-- The script exits with an error (so run_p1.sh stops) if any test FAILS.
--
-- Run:
--   sudo runuser -u postgres -- psql -d roadlink -f 05_constraint_tests.sql
-- =============================================================================

\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TEMP TABLE p1_results (n serial, label text, result text, message text);

CREATE OR REPLACE FUNCTION pg_temp._p1_test(label text, sql text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE sql;
        -- if we got here, the bad row was ACCEPTED — that is a FAILURE
        INSERT INTO p1_results(label, result, message)
        VALUES (label, 'FAIL', 'bad row was accepted!');
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO p1_results(label, result, message)
        VALUES (label, 'PASS', SQLERRM);
    END;
END$$;

-- -----------------------------------------------------------------------------
-- Test fixtures (built here, rolled back at the end)
-- -----------------------------------------------------------------------------
SELECT (SELECT route_id FROM route ORDER BY route_id LIMIT 1)                AS route_id,
       (SELECT from_terminal_id FROM route ORDER BY route_id LIMIT 1)        AS from_tid,
       (SELECT to_terminal_id   FROM route ORDER BY route_id LIMIT 1)        AS to_tid,
       (SELECT bus_id FROM bus ORDER BY bus_id LIMIT 1)                      AS bus_id,
       (SELECT bus_id FROM bus ORDER BY bus_id LIMIT 1 OFFSET 1)             AS bus2_id,
       (SELECT seat_capacity FROM bus ORDER BY bus_id LIMIT 1)               AS capacity,
       (SELECT driver_id FROM driver ORDER BY driver_id LIMIT 1)             AS driver_id,
       (SELECT driver_id FROM driver ORDER BY driver_id LIMIT 1 OFFSET 1)    AS driver2_id,
       date_trunc('hour', now()) + interval '60 days'                        AS t0
\gset

-- a terminal pair that has NO route yet (so test 9a fails only on the fare)
SELECT f.terminal_id AS free_from, t.terminal_id AS free_to
FROM terminal f CROSS JOIN terminal t
WHERE f.terminal_id <> t.terminal_id
  AND NOT EXISTS (SELECT 1 FROM route r
                  WHERE r.from_terminal_id = f.terminal_id AND r.to_terminal_id = t.terminal_id)
ORDER BY 1, 2 LIMIT 1
\gset

INSERT INTO passenger(full_name, phone, email) VALUES
    ('Test Passenger One', '+234-000-000-0001', 'p1test.one@example.com'),
    ('Test Passenger Two', '+234-000-000-0002', 'p1test.two@example.com');
SELECT (SELECT passenger_id FROM passenger WHERE email = 'p1test.one@example.com') AS pid1,
       (SELECT passenger_id FROM passenger WHERE email = 'p1test.two@example.com') AS pid2
\gset

-- a clean test trip 60 days ahead (no generated trip is that far out)
INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at)
VALUES (:route_id, :bus_id, :driver_id, :'t0', :'t0'::timestamptz + interval '6 hours')
RETURNING trip_id AS test_trip
\gset

-- one VALID booking (seat 1, passenger 1) + its payment, so the "duplicate"
-- tests below really are duplicates
INSERT INTO booking (trip_id, passenger_id, seat_number)
VALUES (:test_trip, :pid1, 1)
RETURNING booking_id AS test_bk
\gset
INSERT INTO payment (booking_id, amount_ngn, channel)
VALUES (:test_bk, 6500, 'CARD');

\echo ''
\echo 'Test context: trip' :test_trip '(bus' :bus_id ', capacity' :capacity ', driver' :driver_id ') departs' :'t0'
\echo 'Valid booking' :test_bk 'holds seat 1 for passenger' :pid1 'and is paid ₦6,500'
\echo ''

\o /dev/null
-- (output of the 16 test calls is hidden; the results table is printed below)

-- 1. one passenger per seat per trip
SELECT pg_temp._p1_test('1. UNIQUE seat: seat 1 sold again to another passenger',
    format('INSERT INTO booking (trip_id, passenger_id, seat_number) VALUES (%s, %s, 1)',
           :test_trip, :pid2));

-- 2. one confirmed seat per passenger per trip
SELECT pg_temp._p1_test('2. UNIQUE passenger: passenger 1 takes a 2nd seat',
    format('INSERT INTO booking (trip_id, passenger_id, seat_number) VALUES (%s, %s, 2)',
           :test_trip, :pid1));

-- 3. seat-capacity trigger
SELECT pg_temp._p1_test('3a. trigger: seat number above bus capacity',
    format('INSERT INTO booking (trip_id, passenger_id, seat_number) VALUES (%s, %s, %s)',
           :test_trip, :pid2, :capacity + 1));
SELECT pg_temp._p1_test('3b. trigger + CHECK: seat 0 (below range)',
    format('INSERT INTO booking (trip_id, passenger_id, seat_number) VALUES (%s, %s, 0)',
           :test_trip, :pid2));

-- 4. booking after departure (trigger)
SELECT pg_temp._p1_test('4. trigger: booking made after the trip departed',
    format('INSERT INTO booking (trip_id, passenger_id, seat_number, booked_at) '
           'VALUES (%s, %s, 3, %L::timestamptz + interval ''1 hour'')',
           :test_trip, :pid2, :'t0'));

-- 5. bus overlap
SELECT pg_temp._p1_test('5. EXCLUDE bus overlap: same bus, overlapping time',
    format('INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at) '
           'VALUES (%s, %s, %s, %L::timestamptz + interval ''2 hours'', '
           '%L::timestamptz + interval ''9 hours'')',
           :route_id, :bus_id, :driver2_id, :'t0', :'t0'));

-- 6. driver overlap
SELECT pg_temp._p1_test('6. EXCLUDE driver overlap: same driver, other bus',
    format('INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at) '
           'VALUES (%s, %s, %s, %L::timestamptz + interval ''1 hour'', '
           '%L::timestamptz + interval ''5 hours'')',
           :route_id, :bus2_id, :driver_id, :'t0', :'t0'));

-- 7. arrival after departure
SELECT pg_temp._p1_test('7. CHECK arrival after departure',
    format('INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at) '
           'VALUES (%s, %s, %s, %L::timestamptz + interval ''10 days'', '
           '%L::timestamptz + interval ''10 days'' - interval ''2 hours'')',
           :route_id, :bus2_id, :driver2_id, :'t0', :'t0'));

-- 8. route terminals must differ / route pair unique
SELECT pg_temp._p1_test('8a. CHECK route terminals differ: from = to',
    format('INSERT INTO route (from_terminal_id, to_terminal_id, distance_km, base_fare_ngn) '
           'VALUES (%s, %s, 5, 1000)', :from_tid, :from_tid));
SELECT pg_temp._p1_test('8b. UNIQUE route pair: same route twice',
    format('INSERT INTO route (from_terminal_id, to_terminal_id, distance_km, base_fare_ngn) '
           'VALUES (%s, %s, 130, 6500)', :from_tid, :to_tid));

-- 9. fare and payment must be > 0
SELECT pg_temp._p1_test('9a. CHECK route fare > 0: fare = -1',
    format('INSERT INTO route (from_terminal_id, to_terminal_id, distance_km, base_fare_ngn) '
           'VALUES (%s, %s, 50, -1)', :free_from, :free_to));
SELECT pg_temp._p1_test('9b. CHECK payment > 0: amount = 0',
    format('INSERT INTO payment (booking_id, amount_ngn, channel) VALUES (%s, 0, ''CARD'')',
           :test_bk));

-- 10. one payment per booking
SELECT pg_temp._p1_test('10. UNIQUE payment.booking_id: second payment',
    format('INSERT INTO payment (booking_id, amount_ngn, channel) VALUES (%s, 6500, ''USSD'')',
           :test_bk));

-- 11. refunds
SELECT pg_temp._p1_test('11a. CHECK refund >= 0: refund = -1',
    format('INSERT INTO cancellation (booking_id, reason, refund_ngn) VALUES (%s, ''test'', -1)',
           :test_bk));
SELECT pg_temp._p1_test('11b. trigger: refund more than amount paid',
    format('INSERT INTO cancellation (booking_id, reason, refund_ngn) VALUES (%s, ''test'', 9999)',
           :test_bk));

-- 12. trip_window must match depart/arrive
SELECT pg_temp._p1_test('12. CHECK trip_window matches depart/arrive',
    format('INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at, trip_window) '
           'VALUES (%s, %s, %s, %L::timestamptz + interval ''20 days'', '
           '%L::timestamptz + interval ''20 days 3 hours'', '
           'tstzrange(%L::timestamptz + interval ''21 days'', %L::timestamptz + interval ''22 days'', ''[)''))',
           :route_id, :bus2_id, :driver2_id, :'t0', :'t0', :'t0', :'t0'));

\o
\echo '====================================================================='
\echo '                    CONSTRAINT TESTS (every bad row must be rejected)'
\echo '====================================================================='
SELECT label AS test, result, message AS database_said FROM p1_results ORDER BY n;

SELECT count(*) FILTER (WHERE result = 'PASS') AS passed,
       count(*)                               AS total,
       count(*) FILTER (WHERE result = 'FAIL') > 0 AS any_failed
FROM p1_results
\gset

-- positive control: a cancelled seat can be sold again (partial unique index)
INSERT INTO cancellation (booking_id, reason, refund_ngn) VALUES (:test_bk, 'test', 5525);
INSERT INTO booking (trip_id, passenger_id, seat_number) VALUES (:test_trip, :pid2, 1);
\echo ''
\echo 'Positive check: after booking' :test_bk 'was cancelled, seat 1 was resold to passenger' :pid2 '(accepted, as it should be).'
SELECT bk.booking_id, bk.passenger_id, bk.seat_number, bk.status, p.status AS payment_status
FROM booking bk LEFT JOIN payment p USING (booking_id)
WHERE bk.trip_id = :test_trip ORDER BY bk.booking_id;

ROLLBACK;   -- remove every test row; the generated data is untouched

\echo ''
\echo 'Result:' :passed 'of' :total 'bad inserts were rejected. (All test rows rolled back.)'
\if :any_failed
  \echo 'SOME CONSTRAINT TESTS FAILED (see FAIL rows above)'
  SELECT 1/0 AS constraint_tests_failed;
\endif
