# Normalisation walk-through — RoadLink Express schema → 3NF

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Session 1** (Traditional RDB & Advanced Concepts).

The schema in `01_schema.sql` is in **third normal form (3NF)**. This note
walks through each table and explains why no further decomposition is needed.

---

## Normal-form definitions used

* **1NF** — every column holds a single atomic value; no repeating groups;
  every row has a primary key.
* **2NF** — 1NF + every non-key attribute depends on the *whole* primary key
  (no partial dependency). Only matters for composite keys.
* **3NF** — 2NF + no non-key attribute depends on another non-key attribute
  (no transitive dependency). "Every non-key column must depend on the key,
  the whole key, and nothing but the key, so help me Codd."

---

## Table-by-table analysis

### `terminal` — 3NF ✓
* PK: `terminal_id`.
* Atomic columns (`city`, `name`, `address`).
* `city` and `name` are functionally independent of each other (Lagos has two
  terminals: Jibowu and Ojota). No transitive dependency.
* `UNIQUE (city, name)` prevents accidental duplicates without compromising
  normalisation.

### `route` — 3NF ✓
* PK: `route_id`. Surrogate key (so 2NF is automatic).
* `distance_km` and `base_fare_ngn` both depend on `route_id` only — they
  are properties of the *directed pair of terminals*, not of either terminal
  alone.
* Natural-key alternative would be `(from_terminal_id, to_terminal_id)` —
  that composite is also enforced as `UNIQUE`. Neither `distance_km` nor
  `base_fare_ngn` depends on a single terminal, so 2NF holds.
* No transitive dependencies: `base_fare_ngn` *could* be derived from
  `distance_km` by a pricing formula, but in RoadLink Express fares are set
  commercially (Lagos→Abuja is ₦23,500, but Lagos→Kano which is further is
  ₦28,500 because of demand, not distance alone). Keeping `base_fare_ngn`
  explicit preserves the 3NF information-theoretic content.

### `bus` — 3NF ✓
* PK: `bus_id`.
* `plate_number`, `seat_capacity`, `model` are all direct facts about a
  single bus. None depends on another non-key column.

### `driver` — 3NF ✓
* PK: `driver_id`.
* `full_name`, `license_no`, `phone` are atomic, single-valued facts about a
  driver. `license_no` is also `UNIQUE`.

### `trip` — 3NF ✓
* PK: `trip_id`. Surrogate.
* `route_id`, `bus_id`, `driver_id`, `depart_at`, `arrive_at`, `trip_window`
  are all facts about *this specific scheduled run*.
* `trip_window` is a *derived* value (`tstzrange(depart_at, arrive_at, '[)')`)
  kept in the table only so the `EXCLUDE USING gist` constraint can use it
  for overlap detection — there is no other way to express "no two trips for
  the same bus may overlap" in standard SQL. The `CHECK trip_window_matches`
  constraint keeps the derived column consistent with its source columns.
* `arrive_at` is *not* a transitive dependency on `depart_at` — it depends on
  both `depart_at` *and* `route_id` (the route's distance determines trip
  duration). Storing `arrive_at` directly is a denormalisation in the strict
  sense, but in transport operations the published arrival time is a
  commercial commitment, not a computed value, so we treat it as
  authoritative and let `trip_window_matches` only verify the half-open
  interval identity.

### `passenger` — 3NF ✓
* PK: `passenger_id`.
* `full_name`, `phone`, `email` are independent atomic facts about a person.
* `email` is `UNIQUE`.

### `booking` — 3NF ✓
* PK: `booking_id`. Surrogate.
* Natural key: `(trip_id, seat_number)` — enforced by `UNIQUE`.
* `passenger_id`, `seat_number`, `booked_at`, `status` depend only on the
  booking (i.e. on `booking_id`). They do **not** depend on `passenger_id`
  alone, nor on `trip_id` alone.
* `status` is an enum-like `CHECK IN ('CONFIRMED','CANCELLED','REFUNDED')`.
* A second `UNIQUE INDEX (trip_id, passenger_id)` enforces "one passenger,
  one seat, one trip" — this is a *business rule* layered on top of 3NF; it
  does not affect the normal form.

### `payment` — 3NF ✓
* PK: `payment_id`.
* `booking_id` is `UNIQUE` so the relationship is 1:1 — one payment per
  booking. The natural key could have been `booking_id` alone; we keep a
  separate `payment_id` for reporting joins.
* `amount_ngn`, `channel`, `paid_at`, `status` depend only on the payment.
* No transitive dependency: `channel` does not determine `amount_ngn` (a
  ₦23,500 Lagos→Abuja fare can be paid by CARD, BANK_TRANSFER, USSD or
  WALLET).

### `cancellation` — 3NF ✓
* PK: `cancellation_id`.
* `booking_id` is `UNIQUE` (one cancellation per booking; 0..1
  cardinality).
* `cancelled_at`, `reason`, `refund_ngn` depend only on the cancellation.

---

## Why not BCNF / 4NF?

The schema is in BCNF for every determinant we have identified. We do not
have any multi-valued dependencies: a passenger can have many bookings, but
each booking is a single (trip, seat) pair, not a set of independent
attributes. There is therefore no need to split any table further.

---

## Summary

| Table | PK | Surrogate? | 1NF | 2NF | 3NF | Notes |
|---|---|---|---|---|---|---|
| terminal | terminal_id | yes | ✓ | ✓ | ✓ | `UNIQUE (city, name)` |
| route | route_id | yes | ✓ | ✓ | ✓ | `UNIQUE (from, to)`; CHECK from ≠ to |
| bus | bus_id | yes | ✓ | ✓ | ✓ | `UNIQUE plate_number` |
| driver | driver_id | yes | ✓ | ✓ | ✓ | `UNIQUE license_no` |
| trip | trip_id | yes | ✓ | ✓ | ✓ | two `EXCLUDE USING gist` constraints on `tstzrange` |
| passenger | passenger_id | yes | ✓ | ✓ | ✓ | `UNIQUE email` |
| booking | booking_id | yes | ✓ | ✓ | ✓ | unique index `(trip_id, seat_number)` WHERE status = 'CONFIRMED'; trigger enforces seat ≤ capacity and booked before departure |
| payment | payment_id | yes | ✓ | ✓ | ✓ | `UNIQUE booking_id` (1:1 with booking) |
| cancellation | cancellation_id | yes | ✓ | ✓ | ✓ | `UNIQUE booking_id` (0..1 with booking) |

All nine tables satisfy **3NF** (and BCNF). No further decomposition is
required or beneficial.
