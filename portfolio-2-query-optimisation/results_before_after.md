# Portfolio 2 — Query Optimisation: BEFORE vs AFTER indexes

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432

> **Honesty rule:** every `[paste real result here]` cell must be replaced by
> the student with the real EXPLAIN ANALYZE output from their own Codespace.
> `run_p2.sh` prints a BEFORE/AFTER timing summary at the end and saves the
> full plans in `results/explain_before.txt` and `results/explain_after.txt`.
>
> **What to expect (and say honestly):** the big gains are on the *lookup*
> queries — Q1 (next departing trip: Seq Scan on trip → Index Scan on
> `idx_trip_depart_at`) and Q7 (one passenger's history: Seq Scan of all
> bookings → Bitmap Index Scan on `idx_booking_passenger`). Q2–Q6 are
> *reporting* queries that read most of the table (12 of 24 months), so the
> planner correctly keeps a Seq Scan + Hash Join and their times barely move
> (± run-to-run noise). An index helps when a query reads a small fraction
> of the rows — not when it reads half of them.

Run order:

```bash
bash run_p2.sh     # runs everything below in order and prints the summary
# or one by one:
sudo runuser -u postgres -- psql -d roadlink -f 03_explain_before.sql   # capture BEFORE
sudo runuser -u postgres -- psql -d roadlink -f 02_indexes.sql          # add indexes
sudo runuser -u postgres -- psql -d roadlink -f 04_explain_after.sql    # capture AFTER
```

---

## Summary table

| # | Query | Plan type BEFORE | Plan type AFTER | Time BEFORE (ms) | Time AFTER (ms) | Speedup |
|---|---|---|---|---|---|---|
| Q1 | Free seats on next departing trip | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q2 | Bookings per route per month (12 mo) | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q3 | Revenue per origin terminal (12 mo) | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q4 | Load factor per route (12 mo) | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q5 | Busiest travel days | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q6 | Cancellation rate per route | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |
| Q7 | One passenger's booking history | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] | [paste real result here] |

> **How to fill:** copy the `execution time = X.XXX ms` line from each
> EXPLAIN ANALYZE plan and paste it into the corresponding Time cell. Copy
> the first node of each plan (Seq Scan / Index Scan / Bitmap Heap Scan)
> into the Plan-type cells.

---

## Q1 — Free seats on next departing trip

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here — explain what changed, e.g. "Seq Scan on
booking → Index Scan using idx_booking_trip_status; the partial index on
status='CONFIRMED' was not selected because the planner preferred the
composite UNIQUE index on (trip_id, seat_number). The join cost dropped
from X to Y."]

---

## Q2 — Bookings per route per month (12 mo)

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here]

---

## Q3 — Revenue per origin terminal (12 mo)

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here]

---

## Q4 — Load factor per route (12 mo)

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here]

---

## Q5 — Busiest travel days

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here]

---

## Q6 — Cancellation rate per route

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here]

---

## Brief performance analysis (write after capturing the real numbers)

[paste real result here — 1–2 paragraphs. Compare aggregate timings before
and after, mention which indexes the planner actually picked, and note any
query where adding an index did NOT help (and why). For RoadLink Express the
expected pattern is: the (trip_id, status) composite index dramatically
helps Q1 and Q4's WHERE filter, the (route_id, depart_at) index helps Q2/Q4,
the partial index on status='CANCELLED' helps Q6, and the (depart_at) index
helps Q5's range scan.]

---

## Q7 — One passenger's booking history

### BEFORE
```
[paste real result here]
```

### AFTER
```
[paste real result here]
```

**Notes:** [paste real result here — e.g. "Seq Scan on booking (all ~180k
rows read to find ~36) → Bitmap Index Scan on idx_booking_passenger."]
