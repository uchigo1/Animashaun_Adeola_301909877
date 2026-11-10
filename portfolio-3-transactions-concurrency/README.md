# Portfolio 3 — Transactions & Concurrency

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

> **Course-note sessions covered:** Session 1 — *Traditional RDB & Advanced Concepts* (ACID); Session 2 — *Distributed Database System* (consistency models, ACID vs BASE).

---

## What this portfolio demonstrates

Four interlocking pieces that prove RoadLink Express's booking path is
correct under concurrency:

1. **`book_seat()`** — a PL/pgSQL transaction that locks the trip row
   (`SELECT … FOR UPDATE`), checks the seat is free, inserts the booking,
   records the payment, and commits. Any failure rolls everything back.
2. **COMMIT/ROLLBACK demo** — a deliberately bad payment (`amount = 0`)
   fires the `CHECK (amount_ngn > 0)` constraint AFTER the booking row is
   inserted; the implicit ROLLBACK removes the booking, so the seat is
   released and can be re-booked.
3. **Two-terminal race condition** — six parts, run either automatically
   by `run_race_demos.py` (two real database sessions at once) or by hand
   from the step tables in `03_race_condition_guide.md`. It reproduces:
   * **the BUG** — `booking_bug` table with no `UNIQUE(trip_id, seat_number)`
     and no `FOR UPDATE`; two passengers end up with the same seat.
   * **FIX 1** — adding the `UNIQUE` constraint; the second INSERT is
     rejected with `unique_violation` (an opaque error code).
   * **FIX 2** — `SELECT … FOR UPDATE` inside `book_seat()`; the second
     transaction *waits* for the first to commit, then gets a clean
     "Seat X already booked" message.
   * **FIX 3** — `SERIALIZABLE` isolation catches the same bug with no
     unique index at all (SQLSTATE 40001).
4. **Isolation levels** — `READ COMMITTED` vs `REPEATABLE READ` vs
   `SERIALIZABLE`, demonstrated with the same two-session pattern.
5. **Deadlock demo** — two sessions locking trips in opposite orders;
   PostgreSQL detects the cycle within ~1 s and aborts one transaction
   (SQLSTATE 40P01).

---

## Files

| File | Purpose | Automated? |
|---|---|---|
| `01_book_seat.sql` | PL/pgSQL `book_seat(trip, passenger, seat, amount, channel)` function | ✓ run by `run_p3.sh` |
| `02_commit_rollback_demo.sql` | Failed payment → ROLLBACK releases the seat | ✓ run by `run_p3.sh` |
| `race_setup.sql` | Builds the demo fixtures: 2 trips 45 days ahead, Kemi / Tobi / Halima, `booking_bug` | ✓ run by `run_p3.sh` |
| `race_vars.sql` | `\i race_vars.sql` in each psql session loads `:trip_id`, `:pa`, `:pb` … | used in manual mode |
| `run_race_demos.py` | Runs Parts 1–6 with two real sessions at once, prints real output | ✓ `python3 run_race_demos.py` |
| `03_race_condition_guide.md` | Step tables for Parts 1–6 (bug, UNIQUE, FOR UPDATE, SERIALIZABLE, RC vs RR, deadlock) | manual (2 terminals) |
| `04_isolation_levels.sql` | Reference list of the Part 4–5 isolation statements, marked A / B | reference |
| `05_deadlock_demo.md` | Explanation of the Part 6 deadlock and the lock-ordering fix | reference |
| `run_p3.sh` | Runner: book_seat, COMMIT/ROLLBACK demo, fixtures, then all six demos → `race_demos_output.log` | ✓ |

---

## How to run (Codespaces)

### Automated part

From the repo root:

```bash
bash setup.sh                                          # if not done
bash portfolio-1-database-design/run_p1.sh            # P1 data must exist
cd portfolio-3-transactions-concurrency
bash run_p3.sh
```

`run_p3.sh`:

1. Installs `book_seat()` (file `01_book_seat.sql`)
2. Runs the COMMIT/ROLLBACK demo (file `02_commit_rollback_demo.sql`)
3. Builds the race fixtures (`race_setup.sql`)
4. Runs all six two-session demos (`run_race_demos.py`) and saves the real
   output to `race_demos_output.log`

### Doing the two-terminal demos by hand (optional, good for screenshots)

Open **two terminal tabs**, in each one:

```bash
cd portfolio-3-transactions-concurrency
sudo runuser -u postgres -- psql -d roadlink
```

then `\i race_vars.sql` inside psql, and follow the step tables in
`03_race_condition_guide.md` (Parts 1–6) one line at a time. Re-run
`race_setup.sql` to start again from clean.

---

## What to screenshot for the LMS submission

1. The output of `bash run_p3.sh` (the COMMIT/ROLLBACK demo: the row that
   appears after CASE 1, the empty result after CASE 2, and the row that
   appears again after CASE 3).
2. The two-terminal BUG screen showing **two rows** in `booking_bug` for
   the same `(trip_id, seat_number)`.
3. The two-terminal FIX 1 screen showing the `unique_violation` ERROR in
   Terminal B.
4. The two-terminal FIX 2 screen showing the clean
   `ERROR: Seat X on trip Y is already booked` message in Terminal B.
5. The SERIALIZABLE part (B's `could not serialize access` error) and the
   READ COMMITTED vs REPEATABLE READ counts (Part 5).
6. The deadlock demo — the `ERROR: deadlock detected` message (Part 6).

All six are in `race_demos_output.log` if you used the automatic runner.

---

## Git commit

```bash
git add portfolio-3-transactions-concurrency/
git commit -m "P3: book_seat() txn, COMMIT/ROLLBACK, race demos (bug, UNIQUE, FOR UPDATE, SERIALIZABLE, RC vs RR, deadlock)"
git push
```

---

## Plain-English explanation

A booking is not just an `INSERT INTO booking`. It is a *transaction* that
must:

* **A**tomically create the booking row AND the payment row. If payment
  fails, the seat must NOT be left half-booked.
* **C**onsistently refuse to give the same seat to two passengers.
* **I**solate concurrent attempts so that two passengers clicking "Book
  seat 7" at the same instant do not both succeed.
* **D**urably persist the booking so that a power failure between "payment
  received" and "seat confirmed" never loses the sale.

The `book_seat()` function delivers all four:

* **Atomicity** — it does both `INSERT`s in one transaction; if either
  fails, both roll back.
* **Consistency** — the partial unique index on `(trip_id, seat_number)`
  for CONFIRMED bookings and the
  seat-capacity trigger guarantee no rule can be violated, regardless of
  which client wrote the row.
* **Isolation** — `SELECT … FOR UPDATE` on the trip row makes concurrent
  `book_seat()` calls for the same trip *serialise*: the second call
  blocks until the first commits, then sees the seat as taken and gets a
  clean error.
* **Durability** — once `COMMIT` returns, the booking is in the WAL and
  survives a crash.

The race-condition guide shows what happens when each protection is
removed in turn: the BUG (no constraint, no lock) silently sells the same
seat twice; FIX 1 (constraint only) prevents it but reports an opaque
error code; FIX 2 (constraint + FOR UPDATE) gives the application a
clean message.

The isolation-level demo shows the trade-off: READ COMMITTED is fastest
but allows non-repeatable reads; REPEATABLE READ is snapshot-based and
prevents them; SERIALIZABLE catches the *write-skew* anomaly but at the
cost of more aborts. RoadLink Express uses READ COMMITTED (the default)
for online bookings because the FOR UPDATE lock gives us the correctness
we need without the abort overhead of SERIALIZABLE.

The deadlock demo shows that even with locking, cyclic waits can occur if
the application acquires locks in different orders. PostgreSQL detects
the cycle and aborts one transaction; the application must retry. The
fix is to acquire locks in a deterministic order (e.g. by `trip_id`
ascending) — `book_seat()` does this naturally because it only ever
locks one trip row.

This portfolio covers **Session 1** (ACID) and **Session 2** (consistency
models, ACID vs BASE) of the Miva course notes. The race-condition demo is
the canonical lost-update anomaly; the isolation demo is the
I in ACID; the deadlock demo shows the engine's autonomous recovery from
a cyclic-wait pathology.
