# Handling the December festive rush

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

December is the busiest month for Nigerian inter-state bus operators:
Christmas travel, end-of-year family reunions, and "Ileya" (Eid al-Fitr
or al-Adha, when it falls in December). RoadLink Express sees **~3× the
normal booking volume** in December (visible in P1's bulk generator: it
sets `trips_for_day(December) = 18` vs the year-round baseline of 4).

This note lists the architectural and operational controls that keep the
booking path available and correct during the December peak.

---

## 1. What breaks in December (and why)

| Failure mode | Why it happens in December | Mitigation |
|---|---|---|
| **Seat-availability read latency spikes** | 3× more users hitting `Q1 — free seats` (P2 query 1) | Read from the streaming replica; scale read replicas horizontally; the partition pruning (P5) limits scans to the current month |
| **Booking write contention on a single trip** | Many passengers click "Book seat 7" simultaneously | `SELECT … FOR UPDATE` on the trip row (P3) serialises; the second call gets a clean "seat already booked" message and does NOT block the row |
| **Replication lag grows** | Write volume triples → WAL generation triples → replica can fall seconds behind | Scale up the replica's WAL receiver count; consider a synchronous replica inside Lagos so writes can be safely retried |
| **Audit log volume grows** | `pgaudit` writes a row per DML | Batch-insert audit rows; archive to S3 every hour |
| **Cold-storage fetch latency** | Old partitions (Oct, Nov) get re-queried for "this time last year" reports | Keep Nov + Dec partitions hot on fast NVMe; archive Sep and earlier to S3 + Parquet |
| **MongoDB review spikes** | More trips → more reviews → aggregation pipelines slow down | Use the `idx_review_route` and `idx_review_rating` indexes (P4); shard the reviews collection by `route.fromCity` if growth continues |
| **Payment gateway timeouts** | 3× volume → PSP rate-limits RoadLink | Queue payments (Redis Streams) and retry; degrade gracefully to "your booking is provisional, we will confirm within 5 minutes" |
| **Driver scheduling conflict** | More trips than drivers → would-be overlapping trips | The `EXCLUDE USING gist` constraint (P1) on the `trip` table makes it impossible to schedule an overlapping trip for the same driver; the scheduler must hire seasonal drivers |

---

## 2. Capacity plan (December)

| Resource | Year-round | December peak | Scaling tactic |
|---|---|---|---|
| Trips/day | 4 | 18 | Hire 4 extra drivers + 4 extra buses for the month |
| Bookings/day | ~1,500 | ~5,000 | Add a 2nd streaming replica (read fan-out) |
| Concurrent psql connections | ~50 | ~200 | Bump `max_connections` to 300; use PgBouncer for pooling |
| Read replica lag | <100 ms | 200–800 ms | Acceptable; UI shows "as of X seconds ago" |
| WAL archive volume | ~2 GB/day | ~6 GB/day | Auto-scale the S3 archive bucket |
| MongoDB review inserts | ~50/day | ~200/day | Within replica-set capacity; no action needed |

---

## 3. Operational runbook (December 1 → January 5)

1. **Pre-scale** (Dec 1): provision a 2nd streaming replica; bump
   `max_wal_senders`; verify `synchronous_standby_names` includes both
   Lagos replicas so a failover is automatic.
2. **Daily check (08:00 WAT)**: query `pg_stat_replication` for lag; if
   `replay_lsn` lags `sent_lsn` by > 1 GB, alert and scale up the
   replica's `max_replication_slots` and CPU.
3. **Daily peak (16:00–22:00 WAT)**: monitor connection count; if > 200,
   PgBouncer sheds new connections into a queue.
4. **Hourly audit archive**: cron job detaches partitions older than 90
   days and uploads them to S3 with object-lock.
5. **December 24–26 and December 31**: read-only DR drill — fail a
   read-only workload to the Abuja DR standby to verify it can serve
   seat-availability queries if Lagos goes down.
6. **January 5**: scale back down; detach the December partition; archive
   it; reduce `max_wal_senders` to baseline.

---

## 4. The constraint that saves us

The portfolio's strongest protection against the December rush is the
**`EXCLUDE USING gist` constraint** (P1) on the `trip` table. It means
that *no matter how many bookings pour in*, a single bus cannot be
double-booked onto two overlapping trips, and a single driver cannot be
assigned to two overlapping trips. The database enforces this at the
storage engine — the application cannot accidentally violate it, even
under 10× normal load.

Combined with the `SELECT … FOR UPDATE` lock in `book_seat()` (P3), the
booking write path is correct under concurrency without any
application-level locking. The December peak is therefore primarily a
**capacity** problem (more trips, more replicas, more drivers), not a
**correctness** problem.

---

## 5. CAP placement under December load

* The **write path stays CP** (synchronous Lagos replica + FOR UPDATE
  locks). We do NOT switch to async replication in December — losing a
  booking during the festive peak is more damaging to the brand than
  the ~5 ms added latency.
* The **read path stays AP** (eventual consistency on the replica). We
  accept that "free seats" can be a few seconds stale; the user is told
  "seat may have been taken — confirm at checkout."
* The **DR path stays AP** (async Abuja). If Lagos goes down in
  December, we promote Abuja and accept an RPO of 5–30 s. The backlog
  of bookings that arrive during the failover window are queued in
  Redis Streams and replayed once the new primary is up.

---

## 6. Conclusion

The architecture from `04_cloud_architecture.md` scales for December
without changing its design — only its capacity. Partition pruning
(P5) keeps read queries on the current month; the `EXCLUDE` constraint
(P1) keeps write correctness; `SELECT … FOR UPDATE` (P3) keeps the
race condition under control; the streaming replica (P5) absorbs read
load; and the DR standby (P5) absorbs the Lagos-failure scenario. The
December festive rush is therefore a *capacity-management* exercise,
not a *correctness* exercise — which is exactly what the portfolio
was designed to achieve.

---

## Course-note link

The CAP theorem discussion in **Session 2** is what guides the CP-vs-AP
choice for each workload. The **Session 3** cloud-DB use-case discussion
covers the elastic capacity argument. **Session 1**'s "characteristics of
a good database" includes the resilience under load that the EXCLUDE
constraint and FOR UPDATE lock provide.
