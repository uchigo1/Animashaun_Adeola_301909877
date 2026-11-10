-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 2
-- 03_explain_before.sql — EXPLAIN ANALYZE before the indexes are added
-- =============================================================================
-- Run BEFORE 02_indexes.sql:
--   sudo runuser -u postgres -- psql -d roadlink -f 03_explain_before.sql
--
-- Paste each block's output into results_before_after.md under the
-- "BEFORE" column. Do NOT simulate; copy the real plan.
-- =============================================================================

\pset pager off
-- fresh planner statistics after the bulk load, so BEFORE and AFTER are fair
ANALYZE;
\set ON_ERROR_STOP off

-- Drop any indexes that 02_indexes.sql may have left behind, so we are
-- truly measuring the "no indexes" baseline. (Constraints stay.)
DROP INDEX IF EXISTS idx_booking_trip_status;
DROP INDEX IF EXISTS idx_trip_route_depart;
DROP INDEX IF EXISTS idx_route_from_terminal;
DROP INDEX IF EXISTS idx_bus_id_capacity;
DROP INDEX IF EXISTS idx_trip_depart_at;
DROP INDEX IF EXISTS idx_booking_cancelled;
DROP INDEX IF EXISTS idx_booking_passenger;

\echo '====================================================================='
\echo ' EXPLAIN ANALYZE — BEFORE INDEXES'
\echo ' Paste each plan into results_before_after.md (BEFORE column)'
\echo '====================================================================='
\echo ''
\echo '--- Q1: free seats on next departing trip ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT bk.seat_number
FROM booking bk
WHERE bk.trip_id = (SELECT trip_id FROM trip WHERE depart_at > now() ORDER BY depart_at LIMIT 1)
  AND bk.status = 'CONFIRMED';

\echo ''
\echo '--- Q2: bookings per route per month (12 mo) ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT to_char(t.depart_at,'YYYY-MM') AS ym,
       tf.city || ' → ' || tt.city AS route,
       COUNT(bk.booking_id) AS n
FROM trip t
JOIN route r ON r.route_id = t.route_id
JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal tt ON tt.terminal_id = r.to_terminal_id
LEFT JOIN booking bk ON bk.trip_id = t.trip_id
WHERE t.depart_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY 1, 2
ORDER BY 1 DESC, 3 DESC;

\echo ''
\echo '--- Q3: revenue per origin terminal (12 mo) ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT tf.city AS origin,
       SUM(p.amount_ngn) AS revenue_ngn
FROM payment p
JOIN booking bk ON bk.booking_id = p.booking_id
JOIN trip t ON t.trip_id = bk.trip_id
JOIN route r ON r.route_id = t.route_id
JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
WHERE p.status='SUCCESS'
  AND t.depart_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY tf.city
ORDER BY revenue_ngn DESC;

\echo ''
\echo '--- Q4: load factor per route (12 mo) ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT tf.city || ' → ' || tt.city AS route,
       COUNT(bk.booking_id) FILTER (WHERE bk.status='CONFIRMED') AS seats_sold,
       SUM(b.seat_capacity) AS capacity
FROM trip t
JOIN route r ON r.route_id = t.route_id
JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal tt ON tt.terminal_id = r.to_terminal_id
JOIN bus b ON b.bus_id = t.bus_id
LEFT JOIN booking bk ON bk.trip_id = t.trip_id AND bk.status='CONFIRMED'
WHERE t.depart_at >= now() - interval '12 months'
GROUP BY 1;

\echo ''
\echo '--- Q5: busiest travel days ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT to_char(t.depart_at,'YYYY-MM-DD') AS d, COUNT(bk.booking_id) AS n
FROM trip t
LEFT JOIN booking bk ON bk.trip_id = t.trip_id
WHERE t.depart_at >= now() - interval '12 months'
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

\echo ''
\echo '--- Q6: cancellation rate per route ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT tf.city || ' → ' || tt.city AS route,
       COUNT(*) FILTER (WHERE b.status='CANCELLED') AS cancelled,
       COUNT(*) AS total
FROM booking b
JOIN trip t ON t.trip_id = b.trip_id
JOIN route r ON r.route_id = t.route_id
JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal tt ON tt.terminal_id = r.to_terminal_id
GROUP BY 1
ORDER BY 2 DESC;

\echo ''
\echo '--- Q7: one passenger''s booking history ---'
SELECT passenger_id FROM booking GROUP BY passenger_id ORDER BY COUNT(*) DESC, passenger_id LIMIT 1 \gset
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT bk.booking_id, t.depart_at, bk.seat_number, bk.status
FROM booking bk
JOIN trip t ON t.trip_id = bk.trip_id
WHERE bk.passenger_id = :passenger_id
ORDER BY t.depart_at DESC;
