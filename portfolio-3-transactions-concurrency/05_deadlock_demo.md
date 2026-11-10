# Portfolio 3 — Deadlock demo

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

The step-by-step table is **Part 6 of `03_race_condition_guide.md`** (it uses
the two demo trips from `race_setup.sql`, loaded into each psql session with
`\i race_vars.sql`). `python3 run_race_demos.py` runs it automatically.

## What happens

* **Terminal A** locks trip 1 (`SELECT … FOR UPDATE`), then asks for trip 2.
* **Terminal B** locks trip 2, then asks for trip 1.
* Each now waits for a lock the other holds — a cycle. After
  `deadlock_timeout` (1 second by default) PostgreSQL's deadlock detector
  aborts one of them with `ERROR: deadlock detected` (SQLSTATE **40P01**);
  the other transaction gets its row and carries on.

## When this could happen at RoadLink Express

`book_seat()` locks only **one** trip, so ordinary bookings never deadlock.
The risk is a "move my seat" feature: passenger 1 moves from trip T1 to T2
while passenger 2 moves from T2 to T1, each locking "my old trip" first.

## The fix

Always take the locks in the same order — by `trip_id`:

```sql
SELECT trip_id FROM trip
WHERE trip_id IN (:trip_id, :trip2)
ORDER BY trip_id
FOR UPDATE;
```

With one global order there can be no cycle: the second transaction simply
waits its turn (Part 6, second table). The application should still catch
40P01 and 40001 and retry the transaction, because PostgreSQL may abort a
transaction for these reasons under load.

> **Honesty reminder:** use your own output (`race_demos_output.log` or
> screenshots of your two terminals) as evidence.
