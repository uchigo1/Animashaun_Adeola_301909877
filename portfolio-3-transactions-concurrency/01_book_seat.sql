-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 3
-- 01_book_seat.sql — PL/pgSQL booking transaction
-- =============================================================================
-- Implements book_seat(p_trip_id, p_passenger_id, p_seat_number, p_amount,
--                       p_channel)  → booking_id (BIGINT)
--
-- The function is one atomic transaction:
--   1. SELECT … FOR UPDATE on the trip row (locks the trip, prevents races)
--   2. Validate the seat is free (no existing booking for trip+seat)
--   3. Validate the seat number is within the bus capacity (the trigger also
--      enforces this, but checking here gives a cleaner error message)
--   4. INSERT into booking (status='CONFIRMED')
--   5. INSERT into payment (status='SUCCESS')
--   6. COMMIT on success
--   7. ROLLBACK on any error (releases the trip lock + the half-written
--      booking row)
--
-- Returns the new booking_id on success. Raises a clean EXCEPTION on failure.
-- =============================================================================

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS book_seat(bigint, bigint, integer, numeric, text);

CREATE OR REPLACE FUNCTION book_seat(
    p_trip_id      BIGINT,
    p_passenger_id BIGINT,
    p_seat_number  INTEGER,
    p_amount       NUMERIC,
    p_channel      TEXT
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id BIGINT;
    v_capacity    INTEGER;
    v_exists      BOOLEAN;
BEGIN
    -- 1. Lock the trip row so concurrent book_seat() calls on the same trip
    --    serialize. This is the "Fix 2" described in 03_race_condition_guide.md.
    --    Without it, two concurrent calls could both see the seat as free.
    PERFORM 1 FROM trip WHERE trip_id = p_trip_id FOR UPDATE;

    -- 2. Validate the seat is free.
    SELECT EXISTS (
        SELECT 1 FROM booking
         WHERE trip_id = p_trip_id
           AND seat_number = p_seat_number
           AND status = 'CONFIRMED'
    ) INTO v_exists;
    IF v_exists THEN
        RAISE EXCEPTION
            'Seat % on trip % is already booked',
            p_seat_number, p_trip_id
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 3. Validate seat number within bus capacity.
    SELECT b.seat_capacity
      INTO v_capacity
      FROM trip t JOIN bus b ON b.bus_id = t.bus_id
     WHERE t.trip_id = p_trip_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip % does not exist', p_trip_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF p_seat_number < 1 OR p_seat_number > v_capacity THEN
        RAISE EXCEPTION
            'Seat % out of range for trip % (capacity %)',
            p_seat_number, p_trip_id, v_capacity
            USING ERRCODE = 'check_violation';
    END IF;

    -- 4. Insert the booking.
    INSERT INTO booking (trip_id, passenger_id, seat_number, status)
    VALUES (p_trip_id, p_passenger_id, p_seat_number, 'CONFIRMED')
    RETURNING booking_id INTO v_booking_id;

    -- 5. Insert the payment. If this FAILS (e.g. amount <= 0, or the channel
    --    is invalid), the exception propagates, plpgsql issues an implicit
    --    ROLLBACK, the booking row is removed, the trip lock is released.
    --    → 02_commit_rollback_demo.sql demonstrates this explicitly.
    INSERT INTO payment (booking_id, amount_ngn, channel, paid_at, status)
    VALUES (v_booking_id, p_amount, p_channel, now(), 'SUCCESS');

    -- 6. Implicit COMMIT happens when the function returns.
    RETURN v_booking_id;
END;
$$;

\echo 'Function book_seat() created.'
\df book_seat
