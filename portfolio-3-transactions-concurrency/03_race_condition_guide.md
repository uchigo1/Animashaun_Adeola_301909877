# Portfolio 3 — Two-terminal concurrency demos (Parts 1–6)

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

Two passengers at two booking desks — **Kemi Adebanjo at Jibowu (Terminal A)**
and **Tobi Nwachukwu at Ojota (Terminal B)** — try to buy **the same seat**
on the same Lagos → Abuja coach at the same moment.

| Part | What it shows | Result you should see |
|---|---|---|
| 1 | **The bug** — check-then-insert, no unique rule | both inserts succeed → 2 people on 1 seat |
| 2 | **Fix 1** — `UNIQUE (trip_id, seat_number)` | B waits for A, then `duplicate key` (23505) |
| 3 | **Fix 2** — `book_seat()` locks the trip row with `SELECT … FOR UPDATE` | B waits, then `Seat 12 on trip … is already booked` |
| 4 | **Fix 3** — `SERIALIZABLE` isolation, still no unique rule | B's COMMIT fails: `could not serialize access` (40001) |
| 5 | READ COMMITTED vs REPEATABLE READ | the seat count changes mid-transaction under RC, not under RR |
| 6 | **Deadlock** — two desks lock two trips in opposite order | one gets `deadlock detected` (40P01); fix = lock in id order |

You can do this two ways. **Both produce real output from your own database.**

---

## Option 1 (fast) — run all six parts automatically

```bash
cd portfolio-3-transactions-concurrency
python3 run_race_demos.py | tee race_demos_output.log
```

`run_race_demos.py` opens **two real database sessions at once** (Terminal A
and Terminal B), sends every step below to the right session in the right
order, and prints what PostgreSQL answered. Steps that must wait for a lock
run in the background so you can see "still WAITING" and then the result.
Save `race_demos_output.log` — it is your evidence for Parts 1–6.

---

## Option 2 (by hand) — two terminal tabs

### Once, in either terminal

```bash
cd portfolio-3-transactions-concurrency
sudo runuser -u postgres -- psql -d roadlink -f 01_book_seat.sql
sudo runuser -u postgres -- psql -d roadlink -f race_setup.sql
```

`race_setup.sql` creates two demo trips 45 days ahead, the three demo
passengers and the `booking_bug` table (a copy of `booking` with **no**
unique rule). Re-run it any time to start again from clean.

### In EACH of the two terminals

Open two terminal tabs (the **+** next to the terminal's name). In each one:

```bash
cd portfolio-3-transactions-concurrency
sudo runuser -u postgres -- psql -d roadlink
```

then, inside psql:

```sql
\i race_vars.sql
```

This loads `:trip_id`, `:trip2`, `:pa` (Kemi), `:pb` (Tobi), `:pc` (Halima),
`:seat`, `:seat2`, `:seat3` into **that** psql session, so every line below
can be pasted exactly as written — no ids to copy.

> Do the steps **in number order**, one line at a time, in the terminal shown.
> "(waits…)" means the cursor hangs: that is the lock working. Go to the next
> step in the *other* terminal and it will finish.

---

### Part 1 — THE BUG

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `BEGIN;` | BEGIN |
| 2 | A | `SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;` | 0 — seat looks free |
| 3 | B | `BEGIN;` | BEGIN |
| 4 | B | `SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;` | 0 — seat looks free to B too |
| 5 | A | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pa, :seat);` | INSERT 0 1 |
| 6 | A | `COMMIT;` | COMMIT |
| 7 | B | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pb, :seat);` | INSERT 0 1 — nothing stops it |
| 8 | B | `COMMIT;` | COMMIT |
| 9 | A | `SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = :trip_id;` | **2 rows, same seat** ← the bug (screenshot) |

### Part 2 — FIX 1: a UNIQUE index

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `TRUNCATE booking_bug;` | |
| 2 | A | `CREATE UNIQUE INDEX booking_bug_seat_unique ON booking_bug (trip_id, seat_number);` | CREATE INDEX |
| 3 | A | `BEGIN;` | |
| 4 | B | `BEGIN;` | |
| 5 | A | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pa, :seat);` | INSERT 0 1 |
| 6 | B | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pb, :seat);` | **(waits…)** for A |
| 7 | A | `COMMIT;` | COMMIT — and B now shows `ERROR: duplicate key value violates unique constraint "booking_bug_seat_unique"` |
| 8 | B | `ROLLBACK;` | |
| 9 | A | `SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = :trip_id;` | 1 row — Kemi only |

### Part 3 — FIX 2: `book_seat()` with `SELECT … FOR UPDATE`

`book_seat()` (01_book_seat.sql) starts with
`PERFORM 1 FROM trip WHERE trip_id = p_trip_id FOR UPDATE;` — it locks the
trip row, so two bookings for the same trip queue up one behind the other.

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `BEGIN;` | |
| 2 | A | `SELECT book_seat(:trip_id, :pa, :seat, 23500.00, 'CARD');` | a booking_id |
| 3 | B | `BEGIN;` | |
| 4 | B | `SELECT book_seat(:trip_id, :pb, :seat, 23500.00, 'CARD');` | **(waits…)** on the trip lock |
| 5 | A | `COMMIT;` | COMMIT — B now shows `ERROR: Seat 12 on trip … is already booked` |
| 6 | B | `ROLLBACK;` | |
| 7 | A | `SELECT booking_id, passenger_id, seat_number, status FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | 1 row — Kemi's |

### Part 4 — FIX 3: SERIALIZABLE (no unique index at all)

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `DROP INDEX booking_bug_seat_unique; TRUNCATE booking_bug;` | |
| 2 | A | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| 3 | A | `SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;` | 0 |
| 4 | B | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| 5 | B | `SELECT count(*) FROM booking_bug WHERE trip_id = :trip_id AND seat_number = :seat;` | 0 |
| 6 | A | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pa, :seat);` | INSERT 0 1 |
| 7 | B | `INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES (:trip_id, :pb, :seat);` | INSERT 0 1 (no wait — there is no index) |
| 8 | A | `COMMIT;` | COMMIT |
| 9 | B | `COMMIT;` | **`ERROR: could not serialize access due to read/write dependencies among transactions`** (40001) |
| 10 | A | `SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = :trip_id;` | 1 row — Kemi only |

Same steps as Part 1, but PostgreSQL noticed that both transactions read
"seat free" and both wrote it, which no one-after-the-other order could
produce, so it cancelled B. The app would simply retry B.

### Part 5 — READ COMMITTED vs REPEATABLE READ

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `BEGIN ISOLATION LEVEL READ COMMITTED;` | |
| 2 | A | `SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | 1 (Kemi) |
| 3 | B | `SELECT book_seat(:trip_id, :pb, :seat2, 23500.00, 'CARD');` | a booking_id (auto-commits) |
| 4 | A | `SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | **2** — changed inside one transaction |
| 5 | A | `COMMIT;` | |
| 6 | A | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| 7 | A | `SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | 2 |
| 8 | B | `SELECT book_seat(:trip_id, :pc, :seat3, 23500.00, 'CARD');` | a booking_id (Halima) |
| 9 | A | `SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | **still 2** — same snapshot |
| 10 | A | `COMMIT;` | |
| 11 | A | `SELECT count(*) FROM booking WHERE trip_id = :trip_id AND status = 'CONFIRMED';` | 3 — new transaction, new snapshot |

### Part 6 — DEADLOCK (and the fix)

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `BEGIN;` | |
| 2 | A | `SELECT trip_id FROM trip WHERE trip_id = :trip_id FOR UPDATE;` | locks trip 1 |
| 3 | B | `BEGIN;` | |
| 4 | B | `SELECT trip_id FROM trip WHERE trip_id = :trip2 FOR UPDATE;` | locks trip 2 |
| 5 | A | `SELECT trip_id FROM trip WHERE trip_id = :trip2 FOR UPDATE;` | **(waits…)** for B |
| 6 | B | `SELECT trip_id FROM trip WHERE trip_id = :trip_id FOR UPDATE;` | after ~1 s: **`ERROR: deadlock detected`** (40P01) in one terminal; the other gets its row |
| 7 | A | `ROLLBACK;` | |
| 8 | B | `ROLLBACK;` | |

**The fix:** every transaction locks the trips it needs **in trip_id order**:

| Step | Terminal | Paste this | What you see |
|---|---|---|---|
| 1 | A | `BEGIN;` | |
| 2 | A | `SELECT trip_id FROM trip WHERE trip_id IN (:trip_id, :trip2) ORDER BY trip_id FOR UPDATE;` | 2 rows locked |
| 3 | B | `BEGIN;` | |
| 4 | B | `SELECT trip_id FROM trip WHERE trip_id IN (:trip_id, :trip2) ORDER BY trip_id FOR UPDATE;` | (waits…) — just queues |
| 5 | A | `COMMIT;` | B now gets its 2 rows — no deadlock |
| 6 | B | `COMMIT;` | |

When finished: `\q` in both terminals.

---

## Why RoadLink Express uses FIX 2 (plus the unique index)

| Approach | Stops double-booking? | What the passenger sees |
|---|---|---|
| Bug (no rule, no lock) | **No** | Two tickets for one seat — found at boarding |
| Fix 1: UNIQUE index | Yes | A raw database error the app must translate |
| Fix 2: `SELECT … FOR UPDATE` in `book_seat()` | Yes | "Seat 12 is already booked" — the app shows it directly |
| Fix 3: SERIALIZABLE | Yes | A retry error (40001); the app must retry the whole booking |

`book_seat()` uses Fix 2 for a clean message, and the partial unique index
`booking_seat_unique` (P1) stays as the safety net for any code path that
bypasses the function. Moving a passenger between two trips locks both trips
in `trip_id` order (Part 6), so it can never deadlock.

This maps to Session 1 (ACID) and the transaction-management/concurrency
topics of the Miva MIT 8103 course notes.

> **Honesty reminder:** submit the output you get yourself
> (`race_demos_output.log` or screenshots of your two terminals) — not the
> "What you see" column above. Your booking ids and process numbers will differ.
