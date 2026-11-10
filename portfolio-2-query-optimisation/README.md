# Portfolio 2 — Query Processing & Optimisation

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case study:** RoadLink Express

> **Course-note session covered:** Study Session 4 — *Query Optimisation in Database* (queries, query optimisation, execution plans & cost estimation, file organisation).

---

## What this portfolio demonstrates

Seven analysis queries that an operations manager at RoadLink Express would
actually run, plus a measured EXPLAIN ANALYZE comparison **before vs after**
indexes. The CA demands "SQL queries, query results, execution plans,
indexing/optimisation evidence, and brief performance analysis" — this
portfolio delivers all five for the same RoadLink case study used in P1.

The seven queries:

| # | Query | Why it matters | Index added |
|---|---|---|---|
| Q1 | Free seats on the next departing trip | Used in real-time seat-selection UI | `idx_trip_depart_at` (finds the next trip) + `idx_booking_trip_status` |
| Q2 | Bookings per route per month (12 mo) | Demand trend per corridor | `idx_trip_route_depart (route_id, depart_at)` |
| Q3 | Revenue per origin terminal (12 mo) | Which terminal earns most | `idx_route_from_terminal (from_terminal_id)` |
| Q4 | Load factor (seats sold ÷ capacity) per route | Profitability per corridor | `idx_bus_id_capacity` (covering) |
| Q5 | Busiest travel days | Operations staffing | `idx_trip_depart_at (depart_at)` |
| Q6 | Cancellation rate (overall + per route) | Quality / fraud signals | `idx_booking_cancelled` partial index |
| Q7 | One passenger's booking history ("My trips" screen) | Customer app / support desk | `idx_booking_passenger (passenger_id)` |

---

## Files

| File | Purpose |
|---|---|
| `01_queries.sql` | The seven analysis queries, runnable in psql |
| `02_indexes.sql` | `CREATE INDEX` statements for the optimisation step |
| `03_explain_before.sql` | Drops all P2 indexes, then runs EXPLAIN ANALYZE for each query (the BEFORE baseline) |
| `04_explain_after.sql` | Re-runs the same EXPLAIN ANALYZE for each query (the AFTER measurement) |
| `results/` | Created by `run_p2.sh`: the full BEFORE and AFTER plans (`explain_before.txt`, `explain_after.txt`) |
| `results_before_after.md` | Template with `[paste real result here]` placeholders for every plan + every timing |
| `run_p2.sh` | End-to-end runner |

---

## How to run (Codespaces)

From the repo root:

```bash
bash setup.sh        # if not already done
bash portfolio-1-database-design/run_p1.sh    # P1 must have populated the data first
cd portfolio-2-query-optimisation
bash run_p2.sh
```

`run_p2.sh` does:

1. `01_queries.sql` — print the seven queries' raw result sets
2. `03_explain_before.sql` — drop any pre-existing P2 indexes; EXPLAIN ANALYZE each query (BEFORE baseline)
3. `02_indexes.sql` — create the seven indexes
4. `04_explain_after.sql` — EXPLAIN ANALYZE each query again (AFTER measurement)
5. prints a BEFORE / AFTER / speed-up summary table from the two plan files

All psql calls go through:

```bash
sudo runuser -u postgres -- psql -d roadlink -f <file>.sql
```

i.e. via the Unix socket at `/var/run/postgresql` — no password.

---

## What to screenshot for the LMS submission

1. The terminal output of `bash run_p2.sh` showing the query result sets and the final timing summary.
2. The full EXPLAIN ANALYZE plan of EACH query BEFORE the indexes.
3. The full EXPLAIN ANALYZE plan of EACH query AFTER the indexes.
4. The summary table in `results_before_after.md` (after you have filled in
   the real `[paste real result here]` placeholders with the captured
   timings).
5. `\di` output of the `roadlink` database showing the new indexes exist.
6. `SELECT * FROM pg_stat_user_indexes WHERE relname='booking';` showing
   the index scan counts after a re-run of the queries.

---

## Git commit

```bash
git add portfolio-2-query-optimisation/
git commit -m "P2: 7 analysis queries + EXPLAIN ANALYZE before/after indexes"
git push
```

---

## Plain-English explanation

The seven queries answer the questions RoadLink Express's operations manager
asks every Monday morning: *which trip has free seats right now, which
corridor is growing, which terminal earns most, which route fills the bus,
which days we are slammed, which routes customers are cancelling, and what one customer has booked.*

Each query is written in plain SQL — no fancy syntax — so the EXPLAIN
ANALYZE plan is readable. The BEFORE baseline is captured with **no
secondary indexes** (only the PKs and UNIQUE constraints from P1). Each
query typically does a sequential scan over `trip` (≈ thousands of rows)
and a sequential scan over `booking` (≈ 180k rows from P1's bulk
generator), then joins them.

The AFTER step adds seven targeted indexes:

* `idx_booking_trip_status (trip_id, status)` — composite, lets Q1 find
  booked seats for one trip in O(log n) instead of scanning all bookings.
* `idx_trip_route_depart (route_id, depart_at)` — covering index for Q2
  and Q4's GROUP BY.
* `idx_route_from_terminal (from_terminal_id)` — speeds Q3's terminal join.
* `idx_bus_id_capacity` INCLUDE `(seat_capacity)` — covering index for Q4's
  capacity lookup so PG can do an Index-Only Scan.
* `idx_trip_depart_at (depart_at)` — range scan for Q5's last-12-month
  window.
* `idx_booking_cancelled` PARTIAL `WHERE status='CANCELLED'` — a small,
  targeted index for Q6's cancellation-rate aggregation; only cancelled
  rows are stored.
* `idx_booking_passenger (passenger_id)` — Q7's lookup. The two booking
  unique indexes start with `trip_id`, so before this index PostgreSQL had
  to read every booking to find one passenger's ~30.

**What actually happens (honest analysis).** Indexes help *lookup*
queries that need a few rows: Q1 (the next departing trip moves from a
Seq Scan on `trip` to an Index Scan on `idx_trip_depart_at`) and Q7 (a
Seq Scan of all bookings becomes a Bitmap Index Scan on
`idx_booking_passenger`) get many times faster. Q2–Q6 are *reporting*
queries that read 12 of the 24 months — about half the table — so the
planner correctly keeps Seq Scan + Hash Join, and their times stay about
the same (small differences are run-to-run noise). That is the lesson of
the cost model: an index is worth it when a query reads a small fraction
of the rows. For the reports, the real fix is P5's monthly partitioning
(scan only the months asked for) or a summary table refreshed nightly.
The exact numbers are captured by the student into
`results_before_after.md` — every `[paste real result here]` placeholder is
replaced with the real EXPLAIN plan and the real `execution time = X.XXX
ms` line.

This portfolio covers **Session 4** of the Miva course notes (query
optimisation, execution plans, cost estimation, file organisation). The
file-organisation discussion in Session 4 maps directly to the index
choices: a B-tree on `(trip_id, status)` is the storage structure that
makes the seat-availability lookup O(log n + k) instead of O(n).
