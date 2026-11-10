-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 3
-- race_setup.sql — builds the fixtures for the two-terminal demos (Parts 1-6)
-- =============================================================================
-- Safe to re-run: it removes the previous demo rows first, then creates
--   * two demo trips 45 days ahead (no generated trip is that far out):
--       Trip 1  Lagos (Jibowu) → Abuja (Utako)  — the seat everyone wants
--       Trip 2  Lagos (Ojota)  → Ibadan         — used for the deadlock
--   * three demo passengers: Kemi Adebanjo (books at Jibowu),
--     Tobi Nwachukwu (books at Ojota), Halima Garba (Part 5)
--   * booking_bug — a copy of booking with NO unique rule (Parts 1, 2, 4)
--   * race_demo — a tiny table of the ids; race_vars.sql reads it with \gset
--     so nobody has to copy an id by hand
--
-- Run once (either terminal), from this folder:
--   sudo runuser -u postgres -- psql -d roadlink -f race_setup.sql
-- =============================================================================
\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS race_demo (key text PRIMARY KEY, val bigint NOT NULL);

-- ---- remove the previous demo run -------------------------------------------
DELETE FROM payment WHERE booking_id IN (
    SELECT booking_id FROM booking WHERE trip_id IN (SELECT val FROM race_demo WHERE key LIKE 'trip%'));
DELETE FROM cancellation WHERE booking_id IN (
    SELECT booking_id FROM booking WHERE trip_id IN (SELECT val FROM race_demo WHERE key LIKE 'trip%'));
DELETE FROM booking WHERE trip_id IN (SELECT val FROM race_demo WHERE key LIKE 'trip%');
DELETE FROM trip    WHERE trip_id IN (SELECT val FROM race_demo WHERE key LIKE 'trip%');
TRUNCATE race_demo;

-- ---- demo passengers (kept between runs) ------------------------------------
INSERT INTO passenger (full_name, phone, email) VALUES
    ('Kemi Adebanjo',  '+234-803-555-0101', 'race.demo.kemi@example.com'),
    ('Tobi Nwachukwu', '+234-806-555-0202', 'race.demo.tobi@example.com'),
    ('Halima Garba',   '+234-809-555-0303', 'race.demo.halima@example.com')
ON CONFLICT (email) DO NOTHING;

-- ---- two demo trips, 45 days ahead, 07:00 and 08:00 Lagos time ---------------
WITH d AS (SELECT (date_trunc('day', now() AT TIME ZONE 'Africa/Lagos') + interval '45 days 7 hours')
                  AT TIME ZONE 'Africa/Lagos' AS t0)
INSERT INTO trip (route_id, bus_id, driver_id, depart_at, arrive_at)
SELECT r.route_id, b.bus_id, dr.driver_id,
       d.t0 + x.offs,
       d.t0 + x.offs + (r.distance_km / 60.0) * interval '1 hour'
FROM d,
     (VALUES (1, 'Jibowu Terminal', 'Utako Terminal',    'LAG-234-XA', 'NIG-DL-100001', interval '0 hours'),
             (2, 'Ojota Terminal',  'Iwo Road Terminal', 'LAG-456-XB', 'NIG-DL-100002', interval '1 hour')
     ) AS x(n, from_name, to_name, plate, licence, offs)
JOIN terminal tf ON tf.name = x.from_name
JOIN terminal tt ON tt.name = x.to_name
JOIN route r     ON r.from_terminal_id = tf.terminal_id AND r.to_terminal_id = tt.terminal_id
JOIN bus b       ON b.plate_number = x.plate
JOIN driver dr   ON dr.license_no  = x.licence
ORDER BY x.n;

-- ---- remember every id the demos need ---------------------------------------
INSERT INTO race_demo (key, val)
SELECT 'trip_id', t.trip_id FROM trip t JOIN bus b USING (bus_id)
 WHERE b.plate_number = 'LAG-234-XA' AND t.depart_at > now() + interval '40 days'
UNION ALL
SELECT 'trip2',   t.trip_id FROM trip t JOIN bus b USING (bus_id)
 WHERE b.plate_number = 'LAG-456-XB' AND t.depart_at > now() + interval '40 days'
UNION ALL SELECT 'pa', passenger_id FROM passenger WHERE email = 'race.demo.kemi@example.com'
UNION ALL SELECT 'pb', passenger_id FROM passenger WHERE email = 'race.demo.tobi@example.com'
UNION ALL SELECT 'pc', passenger_id FROM passenger WHERE email = 'race.demo.halima@example.com'
UNION ALL SELECT 'seat',  12
UNION ALL SELECT 'seat2', 13
UNION ALL SELECT 'seat3', 14;

-- ---- the deliberately broken table for Parts 1, 2 and 4 ---------------------
DROP TABLE IF EXISTS booking_bug;
CREATE TABLE booking_bug (
    bug_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id       BIGINT  NOT NULL,
    passenger_id  BIGINT  NOT NULL,
    seat_number   INTEGER NOT NULL,
    status        TEXT    NOT NULL DEFAULT 'CONFIRMED',
    booked_at     TIMESTAMPTZ NOT NULL DEFAULT now()
    -- NO unique (trip_id, seat_number), NO trigger: anything goes
);
ALTER TABLE booking_bug OWNER TO roadlink;
ALTER TABLE race_demo   OWNER TO roadlink;

\echo ''
\echo 'Demo fixtures ready:'
SELECT d.key, d.val,
       COALESCE(p.full_name,
                tf.city || ' (' || tf.name || ') → ' || tt.city || ', departs ' ||
                to_char(t.depart_at, 'YYYY-MM-DD HH24:MI'),
                'seat number') AS meaning
FROM race_demo d
LEFT JOIN passenger p ON d.key IN ('pa','pb','pc') AND p.passenger_id = d.val
LEFT JOIN trip t      ON d.key IN ('trip_id','trip2') AND t.trip_id = d.val
LEFT JOIN route r     ON r.route_id = t.route_id
LEFT JOIN terminal tf ON tf.terminal_id = r.from_terminal_id
LEFT JOIN terminal tt ON tt.terminal_id = r.to_terminal_id
ORDER BY d.key;
