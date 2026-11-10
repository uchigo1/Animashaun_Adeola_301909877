-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 5
-- 01_partition.sql — partition bookings by month of departure
-- =============================================================================
-- The booking table from P1 is unpartitioned. P5 demonstrates monthly
-- RANGE partitioning on depart_at (which lives on `trip`, one JOIN away
-- from `booking`). Because PostgreSQL can only partition by a column on
-- the partitioned table itself, we copy depart_at onto the booking row
-- via a trigger so the partition key is local.
--
-- Run:
--   sudo runuser -u postgres -- psql -d roadlink -f 01_partition.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1. Create a NEW partitioned table: booking_p (the "_p" suffix avoids
--    clashing with P1's `booking` table).
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS booking_p CASCADE;   -- also drops every partition

CREATE TABLE booking_p (
    booking_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    trip_id       BIGINT NOT NULL,
    passenger_id  BIGINT NOT NULL,
    seat_number   INTEGER NOT NULL,
    depart_at     TIMESTAMPTZ NOT NULL,    -- denormalised from trip, used as partition key
    booked_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        TEXT NOT NULL DEFAULT 'CONFIRMED'
                  CHECK (status IN ('CONFIRMED','CANCELLED','REFUNDED')),
    CONSTRAINT booking_p_seat_unique UNIQUE (trip_id, seat_number, depart_at),
    CONSTRAINT booking_p_seat_pos    CHECK (seat_number > 0)
) PARTITION BY RANGE (depart_at);

-- ---------------------------------------------------------------------------
-- 2. Create partitions: one per month, covering the past 24 months + the
--    next 3 months. Range-relative to today so the demo never expires.
-- ---------------------------------------------------------------------------
-- Generate a partition per month using PL/pgSQL
DO $$
DECLARE
    d date := date_trunc('month', CURRENT_DATE - interval '24 months');
    end_date date := date_trunc('month', CURRENT_DATE + interval '3 months');
    part_name text;
    next_m date;
BEGIN
    WHILE d <= end_date LOOP
        next_m := (d + interval '1 month')::date;
        part_name := 'booking_p_' || to_char(d, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF booking_p
             FOR VALUES FROM (%L) TO (%L)',
            part_name, d, next_m
        );
        d := next_m;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Mirror P1's seat-capacity trigger on the partitioned table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION roadlink_check_seat_capacity_p()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_capacity INTEGER;
BEGIN
    SELECT b.seat_capacity
      INTO v_capacity
      FROM trip t JOIN bus b ON b.bus_id = t.bus_id
     WHERE t.trip_id = NEW.trip_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip % does not exist', NEW.trip_id;
    END IF;
    IF NEW.seat_number < 1 OR NEW.seat_number > v_capacity THEN
        RAISE EXCEPTION 'Seat % out of range for trip % (capacity %)',
            NEW.seat_number, NEW.trip_id, v_capacity
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END$$;

CREATE TRIGGER trg_booking_p_seat_capacity
BEFORE INSERT OR UPDATE OF seat_number, trip_id ON booking_p
FOR EACH ROW EXECUTE FUNCTION roadlink_check_seat_capacity_p();

-- ---------------------------------------------------------------------------
-- 4. Copy P1's bulk bookings into the partitioned table.
--    We pull depart_at from the trip so the partition key is populated.
-- ---------------------------------------------------------------------------
INSERT INTO booking_p (trip_id, passenger_id, seat_number, depart_at, booked_at, status)
SELECT  b.trip_id, b.passenger_id, b.seat_number, t.depart_at, b.booked_at, b.status
FROM    booking b
JOIN    trip    t ON t.trip_id = b.trip_id
ON CONFLICT (trip_id, seat_number, depart_at) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5. Show the partitions and how many rows landed in each (exact counts)
-- ---------------------------------------------------------------------------
ANALYZE booking_p;

\echo ''
\echo '--- partitions of booking_p: rows and size per month ---'
SELECT tableoid::regclass                                   AS partition,
       count(*)                                             AS rows,
       pg_size_pretty(pg_total_relation_size(tableoid))     AS size
FROM booking_p
GROUP BY tableoid
ORDER BY 1;

SELECT count(*) AS partitions FROM pg_inherits WHERE inhparent = 'booking_p'::regclass;
SELECT (SELECT count(*) FROM booking)   AS rows_in_booking,
       (SELECT count(*) FROM booking_p) AS rows_in_booking_p;

-- ---------------------------------------------------------------------------
-- 6. Partition pruning: a query for ONE month only reads ONE partition
-- ---------------------------------------------------------------------------
\echo ''
\echo '--- PRUNING: bookings departing last December (partitioned table) ---'
\echo '    Look for "Subplans Removed" or a single booking_p_YYYY_12 scan.'
SELECT CASE WHEN extract(month FROM now()) = 12
            THEN date_trunc('month', now())::date
            ELSE make_date(extract(year FROM now())::int - 1, 12, 1) END AS dec0 \gset
SELECT (:'dec0'::date + interval '1 month')::date AS dec1 \gset
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FROM booking_p
WHERE depart_at >= :'dec0' AND depart_at < :'dec1';

\echo ''
\echo '--- same question on the UNPARTITIONED booking table (needs the trip join) ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FROM booking b JOIN trip t ON t.trip_id = b.trip_id
WHERE t.depart_at >= :'dec0' AND t.depart_at < :'dec1';

\echo ''
\echo '===================================================================='
\echo '  booking_p partitioned by month of depart_at. Done.'
\echo '===================================================================='
