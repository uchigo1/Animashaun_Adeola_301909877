-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 1
-- 02_triggers.sql — business rules that a CHECK constraint cannot express
-- =============================================================================
-- Student : Animashaun Adeola  | Matric 2026/A/MIT/0432
--
-- A CHECK constraint can only look at the row being written. These rules
-- need data from ANOTHER table, so they are BEFORE triggers:
--
--   1. booking: seat_number must be between 1 and the bus's seat_capacity
--               (capacity lives on bus, the seat lives on booking)
--   2. booking: a seat cannot be booked after the trip has departed
--               (booked_at must be before trip.depart_at)
--   3. cancellation: must happen before departure, the refund cannot be
--               more than what was paid, and recording a cancellation
--               marks the booking CANCELLED (and its payment REFUNDED)
--
-- "Arrival after departure" is a plain CHECK on trip (trip_arrival_after_
-- departure in 01_schema.sql) because both columns are on the same row.
--
-- Run after 01_schema.sql:
--   sudo runuser -u postgres -- psql -d roadlink -f 02_triggers.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 1 + 2. booking: seat within capacity, booked before departure
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION roadlink_check_booking()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_capacity  INTEGER;
    v_bus_id    BIGINT;
    v_depart_at TIMESTAMPTZ;
BEGIN
    SELECT b.seat_capacity, t.bus_id, t.depart_at
      INTO v_capacity, v_bus_id, v_depart_at
      FROM trip t
      JOIN bus  b ON b.bus_id = t.bus_id
     WHERE t.trip_id = NEW.trip_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip % does not exist', NEW.trip_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.seat_number < 1 OR NEW.seat_number > v_capacity THEN
        RAISE EXCEPTION
            'Seat % is out of range for trip % (bus % has capacity %)',
            NEW.seat_number, NEW.trip_id, v_bus_id, v_capacity
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.booked_at >= v_depart_at THEN
        RAISE EXCEPTION
            'Trip % departed at %; a seat cannot be booked at %',
            NEW.trip_id, v_depart_at, NEW.booked_at
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS trg_booking_seat_capacity ON booking;
CREATE TRIGGER trg_booking_seat_capacity
BEFORE INSERT OR UPDATE OF seat_number, trip_id, booked_at ON booking
FOR EACH ROW EXECUTE FUNCTION roadlink_check_booking();

-- -----------------------------------------------------------------------------
-- 3. cancellation: before departure, refund <= amount paid, sync statuses
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION roadlink_on_cancellation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_depart_at TIMESTAMPTZ;
    v_paid      NUMERIC;
BEGIN
    SELECT t.depart_at, p.amount_ngn
      INTO v_depart_at, v_paid
      FROM booking bk
      JOIN trip    t ON t.trip_id = bk.trip_id
      LEFT JOIN payment p ON p.booking_id = bk.booking_id
     WHERE bk.booking_id = NEW.booking_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking % does not exist', NEW.booking_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.cancelled_at >= v_depart_at THEN
        RAISE EXCEPTION
            'Booking % cannot be cancelled at %: the trip departed at %',
            NEW.booking_id, NEW.cancelled_at, v_depart_at
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.refund_ngn > COALESCE(v_paid, 0) THEN
        RAISE EXCEPTION
            'Refund ₦% is more than the ₦% paid for booking %',
            NEW.refund_ngn, COALESCE(v_paid, 0), NEW.booking_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- keep booking/payment status consistent with the cancellation record
    UPDATE booking SET status = 'CANCELLED'
     WHERE booking_id = NEW.booking_id AND status <> 'CANCELLED';
    UPDATE payment SET status = 'REFUNDED'
     WHERE booking_id = NEW.booking_id AND status = 'SUCCESS' AND NEW.refund_ngn > 0;

    RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS trg_cancellation_rules ON cancellation;
CREATE TRIGGER trg_cancellation_rules
BEFORE INSERT ON cancellation
FOR EACH ROW EXECUTE FUNCTION roadlink_on_cancellation();

\echo 'Triggers created:'
SELECT event_object_table AS table_name, trigger_name, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY 1, 2, 4;
