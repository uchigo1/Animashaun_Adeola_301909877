-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 2
-- 01_queries.sql — the six analysis queries
-- =============================================================================
-- Student: Animashaun Adeola  | Matric 2026/A/MIT/0432
--
-- Run:
--   sudo runuser -u postgres -- psql -d roadlink -f 01_queries.sql
--
-- All six queries are written so they can be pasted individually into psql.
-- They cover the CA's "query processing and optimisation" deliverables.
-- =============================================================================

\pset pager off
\set ON_ERROR_STOP on

\echo '====================================================================='
\echo ' Q1 — Free seats on a given trip'
\echo '====================================================================='
-- Pick the next departing trip dynamically so the demo always has a target.
-- (\set cannot run a query, so we use \gset to store the answer in :trip_id)
SELECT trip_id FROM trip WHERE depart_at > now() ORDER BY depart_at LIMIT 1 \gset

SELECT
    t.trip_id,
    tf.city || ' → ' || tt.city                       AS route,
    to_char(t.depart_at, 'YYYY-MM-DD HH24:MI')         AS depart_at,
    b.plate_number,
    b.seat_capacity,
    COUNT(bk.booking_id) FILTER (WHERE bk.status='CONFIRMED') AS seats_booked,
    b.seat_capacity
      - COUNT(bk.booking_id) FILTER (WHERE bk.status='CONFIRMED') AS seats_free
FROM trip      t
JOIN route     r  ON r.route_id   = t.route_id
JOIN terminal  tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal  tt ON tt.terminal_id = r.to_terminal_id
JOIN bus       b  ON b.bus_id     = t.bus_id
LEFT JOIN booking bk ON bk.trip_id = t.trip_id
WHERE t.trip_id = :trip_id
GROUP BY t.trip_id, tf.city, tt.city, t.depart_at, b.plate_number, b.seat_capacity;

-- The actual list of free seat numbers (1..capacity minus booked):
WITH cap AS (
  SELECT t.trip_id, b.seat_capacity
  FROM trip t JOIN bus b ON b.bus_id = t.bus_id
  WHERE t.trip_id = :trip_id
),
taken AS (
  SELECT seat_number FROM booking WHERE trip_id = :trip_id AND status='CONFIRMED'
),
all_seats AS (
  SELECT generate_series(1, (SELECT seat_capacity FROM cap)) AS seat_no
)
SELECT a.seat_no AS free_seat
FROM all_seats a
LEFT JOIN taken tk ON tk.seat_number = a.seat_no
WHERE tk.seat_number IS NULL
ORDER BY a.seat_no;


\echo ''
\echo '====================================================================='
\echo ' Q2 — Bookings per route per month (last 12 months)'
\echo '====================================================================='
SELECT
    to_char(t.depart_at, 'YYYY-MM')                   AS yyyymm,
    tf.city || ' → ' || tt.city                       AS route,
    COUNT(bk.booking_id)                              AS bookings
FROM trip      t
JOIN route     r  ON r.route_id   = t.route_id
JOIN terminal  tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal  tt ON tt.terminal_id = r.to_terminal_id
LEFT JOIN booking bk ON bk.trip_id = t.trip_id
WHERE t.depart_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY 1, 2
ORDER BY 1 DESC, 3 DESC;


\echo ''
\echo '====================================================================='
\echo ' Q3 — Revenue per terminal (origin) over the last 12 months'
\echo '====================================================================='
SELECT
    tf.city                                            AS origin_terminal,
    SUM(p.amount_ngn)                                  AS revenue_ngn,
    COUNT(p.payment_id)                                AS payments_count
FROM payment    p
JOIN booking    bk ON bk.booking_id = p.booking_id
JOIN trip       t  ON t.trip_id    = bk.trip_id
JOIN route      r  ON r.route_id   = t.route_id
JOIN terminal   tf ON tf.terminal_id = r.from_terminal_id
WHERE p.status = 'SUCCESS'
  AND t.depart_at >= date_trunc('month', now()) - interval '12 months'
GROUP BY tf.city
ORDER BY revenue_ngn DESC;


\echo ''
\echo '====================================================================='
\echo ' Q4 — Load factor (seats sold ÷ capacity) per route'
\echo '====================================================================='
SELECT
    tf.city || ' → ' || tt.city                          AS route,
    COUNT(DISTINCT t.trip_id)                            AS trips_run,
    SUM(b.seat_capacity)                                 AS total_capacity,
    COUNT(bk.booking_id) FILTER (WHERE bk.status='CONFIRMED') AS seats_sold,
    ROUND(
      COUNT(bk.booking_id) FILTER (WHERE bk.status='CONFIRMED')::numeric
      / NULLIF(SUM(b.seat_capacity), 0)
      * 100, 2
    )                                                    AS load_factor_pct
FROM trip      t
JOIN route     r  ON r.route_id   = t.route_id
JOIN terminal  tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal  tt ON tt.terminal_id = r.to_terminal_id
JOIN bus       b  ON b.bus_id     = t.bus_id
LEFT JOIN booking bk ON bk.trip_id = t.trip_id AND bk.status='CONFIRMED'
GROUP BY tf.city, tt.city
ORDER BY load_factor_pct DESC;


\echo ''
\echo '====================================================================='
\echo ' Q5 — Busiest travel days (most bookings, last 12 months)'
\echo '====================================================================='
SELECT
    to_char(t.depart_at, 'YYYY-MM-DD')                  AS travel_date,
    to_char(t.depart_at, 'Day')                          AS weekday,
    COUNT(bk.booking_id)                                 AS bookings
FROM trip      t
LEFT JOIN booking bk ON bk.trip_id = t.trip_id
WHERE t.depart_at >= now() - interval '12 months'
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;


\echo ''
\echo '====================================================================='
\echo ' Q6 — Cancellation rate (overall + per route)'
\echo '====================================================================='
-- Overall rate
SELECT
    COUNT(*) FILTER (WHERE b.status='CANCELLED')                 AS cancelled,
    COUNT(*)                                                      AS total,
    ROUND(
      COUNT(*) FILTER (WHERE b.status='CANCELLED')::numeric
      / NULLIF(COUNT(*), 0) * 100, 2
    )                                                            AS cancel_rate_pct
FROM booking b;

-- Per-route rate (top 10 most cancelled)
SELECT
    tf.city || ' → ' || tt.city                              AS route,
    COUNT(*) FILTER (WHERE b.status='CANCELLED')             AS cancelled,
    COUNT(*)                                                 AS total,
    ROUND(
      COUNT(*) FILTER (WHERE b.status='CANCELLED')::numeric
      / NULLIF(COUNT(*), 0) * 100, 2
    )                                                        AS cancel_rate_pct
FROM booking    b
JOIN trip       t  ON t.trip_id    = b.trip_id
JOIN route      r  ON r.route_id   = t.route_id
JOIN terminal   tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal   tt ON tt.terminal_id = r.to_terminal_id
GROUP BY 1
ORDER BY cancelled DESC
LIMIT 10;


\echo ''
\echo '====================================================================='
\echo ' Q7 — A passenger''s booking history ("My trips" screen in the app)'
\echo '====================================================================='
-- The busiest passenger is used so the result is never empty.
SELECT passenger_id FROM booking GROUP BY passenger_id ORDER BY COUNT(*) DESC, passenger_id LIMIT 1 \gset
SELECT
    p.full_name,
    bk.booking_id,
    tf.city || ' → ' || tt.city                  AS route,
    to_char(t.depart_at, 'YYYY-MM-DD HH24:MI')    AS depart_at,
    bk.seat_number,
    bk.status
FROM booking   bk
JOIN passenger p  ON p.passenger_id = bk.passenger_id
JOIN trip      t  ON t.trip_id      = bk.trip_id
JOIN route     r  ON r.route_id     = t.route_id
JOIN terminal  tf ON tf.terminal_id = r.from_terminal_id
JOIN terminal  tt ON tt.terminal_id = r.to_terminal_id
WHERE bk.passenger_id = :passenger_id
ORDER BY t.depart_at DESC
LIMIT 10;
