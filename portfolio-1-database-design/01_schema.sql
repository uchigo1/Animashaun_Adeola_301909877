-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 1
-- 01_schema.sql — relational schema, keys, and constraints (3NF)
-- =============================================================================
-- Student : Animashaun Adeola  | Matric 2026/A/MIT/0432
-- Case    : Inter-state bus booking for RoadLink Express (simulated)
--
-- Connect through the Unix socket (no password):
--   sudo runuser -u postgres -- psql -d roadlink -f 01_schema.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- Drop in dependency-safe order so the script is idempotent.
DROP TABLE IF EXISTS cancellation CASCADE;
DROP TABLE IF EXISTS payment     CASCADE;
DROP TABLE IF EXISTS booking      CASCADE;
DROP TABLE IF EXISTS trip        CASCADE;
DROP TABLE IF EXISTS passenger   CASCADE;
DROP TABLE IF EXISTS driver      CASCADE;
DROP TABLE IF EXISTS bus         CASCADE;
DROP TABLE IF EXISTS route       CASCADE;
DROP TABLE IF EXISTS terminal    CASCADE;

-- btree_gist ships in contrib. setup.sh already installed postgresql-contrib.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;       -- for gen_random_uuid() if needed

-- The psql scripts run as the postgres superuser, but the Python generator
-- (04_bulk_generate.py) and the P3 race-demo script log in as the app role
-- `roadlink`. Give roadlink full rights on every table/sequence postgres
-- creates in this schema from now on (otherwise: "permission denied").
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES    TO roadlink;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO roadlink;

-- =============================================================================
-- 1. terminal  — a city bus station (Jibowu, Ojota, Utako, …)
-- =============================================================================
CREATE TABLE terminal (
    terminal_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city         TEXT NOT NULL,
    name         TEXT NOT NULL,                  -- e.g. "Jibowu Terminal"
    address      TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT terminal_city_name_unique UNIQUE (city, name)
);

-- =============================================================================
-- 2. route  — from_terminal → to_terminal, distance and base fare
-- =============================================================================
CREATE TABLE route (
    route_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_terminal_id BIGINT NOT NULL REFERENCES terminal(terminal_id),
    to_terminal_id   BIGINT NOT NULL REFERENCES terminal(terminal_id),
    distance_km      NUMERIC(6,2) NOT NULL,
    base_fare_ngn    NUMERIC(10,2) NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- a route's two terminals must differ
    CONSTRAINT route_diff_terminals  CHECK (from_terminal_id <> to_terminal_id),
    -- distance and fare must be positive
    CONSTRAINT route_distance_pos    CHECK (distance_km   > 0),
    CONSTRAINT route_fare_pos        CHECK (base_fare_ngn > 0),
    -- a given directed pair of terminals is unique
    CONSTRAINT route_pair_unique     UNIQUE (from_terminal_id, to_terminal_id)
);

-- =============================================================================
-- 3. bus  — physical coach, identified by plate number, has seat capacity
-- =============================================================================
CREATE TABLE bus (
    bus_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plate_number   TEXT NOT NULL,
    seat_capacity  INTEGER NOT NULL,
    model          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT bus_plate_unique       UNIQUE (plate_number),
    CONSTRAINT bus_capacity_pos        CHECK (seat_capacity > 0)
);

-- =============================================================================
-- 4. driver
-- =============================================================================
CREATE TABLE driver (
    driver_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name      TEXT NOT NULL,
    license_no     TEXT NOT NULL,
    phone          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT driver_license_unique  UNIQUE (license_no)
);

-- =============================================================================
-- 5. trip  — route + bus + driver + departure/arrival window
--    Two EXCLUDE constraints (using btree_gist + tstzrange):
--      * a bus   cannot be on two overlapping trips
--      * a driver cannot drive two overlapping trips
-- =============================================================================
CREATE TABLE trip (
    trip_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    route_id     BIGINT NOT NULL REFERENCES route(route_id),
    bus_id       BIGINT NOT NULL REFERENCES bus(bus_id),
    driver_id    BIGINT NOT NULL REFERENCES driver(driver_id),
    depart_at    TIMESTAMPTZ NOT NULL,
    arrive_at    TIMESTAMPTZ NOT NULL,
    -- tstzrange used by the EXCLUDE constraints. [depart, arrive) half-open
    -- so two back-to-back trips (one ends at 12:00, next starts at 12:00)
    -- do NOT overlap.
    trip_window  TSTZRANGE NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- arrival must be strictly after departure
    CONSTRAINT trip_arrival_after_departure CHECK (arrive_at > depart_at),
    -- trip_window must equal [depart_at, arrive_at). Triggered default below.
    CONSTRAINT trip_window_matches CHECK (
        trip_window = tstzrange(depart_at, arrive_at, '[)')
    ),
    -- bus overlap exclusion
    CONSTRAINT trip_no_bus_overlap EXCLUDE USING gist (
        bus_id      WITH =,
        trip_window WITH &&
    ),
    -- driver overlap exclusion
    CONSTRAINT trip_no_driver_overlap EXCLUDE USING gist (
        driver_id   WITH =,
        trip_window WITH &&
    )
);

-- Make sure trip_window is always populated consistently even if the INSERT
-- omits it (defensive — the CHECK above will reject anything inconsistent).
CREATE OR REPLACE FUNCTION roadlink_set_trip_window()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.trip_window IS NULL OR NEW.trip_window = 'empty'::tstzrange THEN
        IF NEW.arrive_at > NEW.depart_at THEN
            NEW.trip_window := tstzrange(NEW.depart_at, NEW.arrive_at, '[)');
        ELSE
            -- leave it empty: CHECK trip_arrival_after_departure then rejects
            -- the row with a clear message (tstzrange() would raise a
            -- confusing "range lower bound" error instead)
            NEW.trip_window := 'empty'::tstzrange;
        END IF;
    END IF;
    RETURN NEW;
END$$;

CREATE TRIGGER trg_trip_window
BEFORE INSERT OR UPDATE ON trip
FOR EACH ROW EXECUTE FUNCTION roadlink_set_trip_window();

-- =============================================================================
-- 6. passenger
-- =============================================================================
CREATE TABLE passenger (
    passenger_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT NOT NULL,
    phone         TEXT,
    email         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT passenger_email_unique UNIQUE (email)
);

-- =============================================================================
-- 7. booking  — one passenger, one seat, one trip
--    UNIQUE (trip_id, seat_number)  →  one passenger per seat per trip
--    seat_number ∈ [1, bus.seat_capacity]  →  enforced by trigger below
-- =============================================================================
CREATE TABLE booking (
    booking_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id       BIGINT NOT NULL REFERENCES trip(trip_id),
    passenger_id  BIGINT NOT NULL REFERENCES passenger(passenger_id),
    seat_number   INTEGER NOT NULL,
    booked_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        TEXT NOT NULL DEFAULT 'CONFIRMED'
                  CHECK (status IN ('CONFIRMED','CANCELLED','REFUNDED')),
    -- seat number must be a positive integer
    CONSTRAINT booking_seat_pos   CHECK (seat_number > 0)
);

-- One passenger per seat per trip. This is a PARTIAL unique index: it only
-- counts CONFIRMED bookings, so when a booking is cancelled the seat can be
-- sold again (a plain UNIQUE (trip_id, seat_number) would keep a cancelled
-- seat blocked for ever, and would disagree with book_seat() in P3, which
-- treats only CONFIRMED rows as "taken").
CREATE UNIQUE INDEX booking_seat_unique
    ON booking (trip_id, seat_number) WHERE status = 'CONFIRMED';

-- A passenger cannot hold two confirmed seats on the same trip (otherwise
-- one person could block several seats).
CREATE UNIQUE INDEX booking_one_passenger_per_trip
    ON booking (trip_id, passenger_id) WHERE status = 'CONFIRMED';

-- The seat-capacity rule is a trigger, not a CHECK, because the capacity
-- lives on another table (bus). It is in 02_triggers.sql.

-- =============================================================================
-- 8. payment  — one booking has exactly one payment (1:1)
-- =============================================================================
CREATE TABLE payment (
    payment_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id   BIGINT NOT NULL UNIQUE REFERENCES booking(booking_id),
    amount_ngn   NUMERIC(10,2) NOT NULL,
    channel      TEXT NOT NULL CHECK (channel IN ('CARD','BANK_TRANSFER','USSD','CASH','WALLET')),
    paid_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    status       TEXT NOT NULL DEFAULT 'SUCCESS'
                 CHECK (status IN ('SUCCESS','FAILED','REFUNDED')),
    -- fare and payment > 0
    CONSTRAINT payment_amount_pos CHECK (amount_ngn > 0)
);

-- =============================================================================
-- 9. cancellation  — optional, 0..1 per booking
-- =============================================================================
CREATE TABLE cancellation (
    cancellation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id      BIGINT NOT NULL UNIQUE REFERENCES booking(booking_id),
    cancelled_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    reason          TEXT,
    refund_ngn      NUMERIC(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT cancellation_refund_nonneg CHECK (refund_ngn >= 0)
);

-- =============================================================================
-- Helpful views
-- =============================================================================
CREATE VIEW v_seat_capacity AS
SELECT t.trip_id,
       t.bus_id,
       b.plate_number,
       b.seat_capacity,
       COUNT(bk.booking_id)            AS seats_booked,
       b.seat_capacity - COUNT(bk.booking_id) AS seats_free
  FROM trip      t
  JOIN bus       b  ON b.bus_id  = t.bus_id
  LEFT JOIN booking bk ON bk.trip_id = t.trip_id
                       AND bk.status = 'CONFIRMED'   -- in the ON clause, so trips
                                                     -- with 0 bookings still show
 GROUP BY t.trip_id, t.bus_id, b.plate_number, b.seat_capacity;

-- =============================================================================
-- Done. Sanity print:
-- =============================================================================
-- Make the app role `roadlink` the OWNER of the nine tables (and, with them,
-- their identity sequences). The generator does TRUNCATE … RESTART IDENTITY,
-- which only the owner of the sequences may do.
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE %I OWNER TO roadlink', r.tablename);
    END LOOP;
END$$;
ALTER VIEW v_seat_capacity OWNER TO roadlink;

\echo 'Schema created. Tables:'
\dt
