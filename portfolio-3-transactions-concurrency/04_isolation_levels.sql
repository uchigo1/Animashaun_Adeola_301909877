-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 3
-- 04_isolation_levels.sql — READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE
-- =============================================================================
-- Isolation levels can only be shown with TWO sessions at the same time, so
-- this file is the reference list of the statements, in order. Each line is
-- marked A (Terminal A, Jibowu desk) or B (Terminal B, Ojota desk).
--
--   * Automatic:  python3 run_race_demos.py | tee race_demos_output.log
--                 (Parts 4 and 5 are the isolation demos)
--   * By hand:    03_race_condition_guide.md, Parts 4 and 5 — step tables.
--                 First run race_setup.sql once, then `\i race_vars.sql`
--                 in BOTH psql sessions so :trip_id, :pa, :pb … exist.
--
-- Do not run this file with -f: the A and B lines must go to two sessions.
-- =============================================================================

-- ---- SERIALIZABLE (Part 4): stops the double-booking with no unique index --
-- A: DROP INDEX IF EXISTS booking_bug_seat_unique; TRUNCATE booking_bug;
-- A: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- A: SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;   -- 0
-- B: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- B: SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;   -- 0
-- A: INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pa, :seat);
-- B: INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pb, :seat);
-- A: COMMIT;                                                   -- OK
-- B: COMMIT;   -- ERROR 40001: could not serialize access due to read/write dependencies

-- ---- READ COMMITTED (Part 5a): each statement sees the latest commits ----
-- A: BEGIN ISOLATION LEVEL READ COMMITTED;
-- A: SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';
-- B: SELECT book_seat(:trip_id, :pb, :seat2, 23500.00, 'CARD');
-- A: SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';  -- +1 (changed)
-- A: COMMIT;

-- ---- REPEATABLE READ (Part 5b): one snapshot for the whole transaction ----
-- A: BEGIN ISOLATION LEVEL REPEATABLE READ;
-- A: SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';
-- B: SELECT book_seat(:trip_id, :pc, :seat3, 23500.00, 'CARD');
-- A: SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';  -- same as before
-- A: COMMIT;
-- A: SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';  -- now +1

\echo 'This file is a reference list for two sessions — see 03_race_condition_guide.md Parts 4-5,'
\echo 'or run:  python3 run_race_demos.py | tee race_demos_output.log'
