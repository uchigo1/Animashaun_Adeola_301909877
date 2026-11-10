-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 2
-- 02_indexes.sql — indexes added AFTER the EXPLAIN-before run
-- =============================================================================
-- Run AFTER capturing the EXPLAIN ANALYZE output of 03_explain_before.sql.
-- Then re-run 04_explain_after.sql to capture the AFTER plan.
-- =============================================================================

\set ON_ERROR_STOP on

-- Q1: free seats lookup — join trip → bus → route → terminal, plus the
-- booking LEFT JOIN on (trip_id, status). The UNIQUE(trip_id,seat_number)
-- already gives us a partial index on trip_id; add an explicit one on
-- status so the FILTER can be pushed down.
CREATE INDEX IF NOT EXISTS idx_booking_trip_status
    ON booking (trip_id, status);

-- Q2: bookings per route per month — group by depart_at month + terminal pair.
-- A covering index on trip(route_id, depart_at) lets PG do an index-only scan.
CREATE INDEX IF NOT EXISTS idx_trip_route_depart
    ON trip (route_id, depart_at);

-- Q3: revenue per origin terminal — joins route→terminal via from_terminal_id.
CREATE INDEX IF NOT EXISTS idx_route_from_terminal
    ON route (from_terminal_id);

-- Q3: payment lookup by booking_id (already UNIQUE, so this is redundant —
-- kept here for explicitness in the write-up).
-- (UNIQUE constraint already creates an index. Nothing to do.)

-- Q4: load factor per route — same (route_id, depart_at) index helps, plus
-- the seat_capacity lookup on bus.
CREATE INDEX IF NOT EXISTS idx_bus_id_capacity
    ON bus (bus_id) INCLUDE (seat_capacity);

-- Q5: busiest travel days — needs depart_at range scan.
CREATE INDEX IF NOT EXISTS idx_trip_depart_at
    ON trip (depart_at);

-- Q6: cancellation rate — partial index on cancelled bookings for the
-- per-route aggregate.
CREATE INDEX IF NOT EXISTS idx_booking_cancelled
    ON booking (trip_id)
    WHERE status = 'CANCELLED';

-- Q7: a passenger's booking history. The two booking unique indexes start
-- with trip_id, so a lookup by passenger_id alone cannot use them → Seq Scan
-- of the whole booking table before this index exists.
CREATE INDEX IF NOT EXISTS idx_booking_passenger
    ON booking (passenger_id);

ANALYZE booking; ANALYZE trip;

\echo 'Indexes created:'
\di
