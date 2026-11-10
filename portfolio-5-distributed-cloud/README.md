# Portfolio 5 — Distributed & Cloud Database Exercise

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

> **Course-note sessions covered:** Session 2 — *Distributed Database System* (fragmentation = partitioning, replication, consistency models, CAP, ACID vs BASE); Session 3 — *Cloud Database Systems*; Session 6 — *Data Security & Data Privacy* (NDPA 2023 is the Nigerian data-privacy law).

---

## What this portfolio demonstrates

Three concrete deliverables + two architectural write-ups that turn the
single-node RoadLink Express database from P1–P4 into a distributed,
Nigerian-cloud-resident system:

| # | Deliverable | File |
|---|---|---|
| 1 | **Partition `bookings` by month of departure** (range partitioning = horizontal fragmentation in Session 2's terms); each monthly partition can be detached + archived | `01_partition.sql` |
| 2 | **Primary + streaming read replica** (physical replication via WAL shipping) on port 5432 + 5433 of the same Codespace; replica is read-only, accepts new rows via streaming | `02_setup_replica.sh` + `03_replica_tests.sql` |
| 3 | **Cloud architecture keeping data in Nigeria** (NDPA 2023); Lagos primary + Lagos replica (synchronous, CP) + Abuja DR standby (asynchronous, AP); CAP and sync-vs-async trade-offs | `04_cloud_architecture.md` |
| 4 | **Handling the December festive rush** — capacity plan, runbook, CAP placement under peak load | `05_december_rush.md` |

---

## Files

| File | Purpose | Automated? |
|---|---|---|
| `01_partition.sql` | Creates `booking_p` partitioned by RANGE(`depart_at`); generates monthly partitions covering the past 24 months + next 3 months (date-relative, never expires); copies P1's bulk data into the partitioned table; shows per-partition row counts and an EXPLAIN proving partition pruning (one month → one partition) | ✓ run by `run_p5.sh` |
| `02_setup_replica.sh` | Creates a replication role, prepends a replication trust line at the TOP of `pg_hba.conf`, sets `wal_level=replica` on the primary, runs `pg_basebackup` to clone the primary into a new data dir, writes the replica's own `postgresql.conf` (port 5433, `hot_standby=on`) and copies `pg_hba.conf` / `pg_ident.conf` (Ubuntu keeps them in /etc, so pg_basebackup does not), starts the replica with `pg_ctl` | ✓ run by `run_p5.sh` |
| `03_replica_tests.sql` | ONE script that switches between the servers itself (`\connect … 5432` / `5433`): who is who, the replica rejects a write, a booking made on the primary appears on the replica, `pg_stat_replication` / `pg_stat_wal_receiver` and lag | ✓ run by `run_p5.sh` |
| `04_cloud_architecture.md` | Reference architecture: NDPA 2023 residency requirement, Lagos primary + Lagos replica (sync, CP) + Abuja DR standby (async, AP); partitioning = fragmentation; streaming replication = physical replication; CAP placement per workload; sync vs async trade-off table; NDPA controls matrix | write-up |
| `05_december_rush.md` | December festive-rush capacity plan, runbook, CAP placement under peak load | write-up |
| `run_p5.sh` | End-to-end runner for the automated parts | ✓ |

---

## How to run (Codespaces)

From the repo root:

```bash
bash setup.sh                                       # if not done
bash portfolio-1-database-design/run_p1.sh          # P1 data must exist
cd portfolio-5-distributed-cloud
bash run_p5.sh
```

`run_p5.sh`:

1. `01_partition.sql` — creates `booking_p` partitioned by month,
   copies P1's bulk data, prints per-partition row counts.
2. `02_setup_replica.sh` — provisions a streaming replica on port 5433.
3. `03_replica_tests.sql` — proves the replica works (all in one run).

Outputs are saved to `partition_output.log` and `replication_output.log`.
To re-run only the replica proof later:

```bash
sudo runuser -u postgres -- psql -d roadlink -f 03_replica_tests.sql
```

(If the Codespace was stopped, the replica stops too. Start it again with
`sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/replica -l /tmp/replica.log start`.)

---

## What to screenshot for the LMS submission

1. The partition sizes output from `01_partition.sql` (per-partition row
   counts showing monthly distribution).
2. The streaming replica setup output from `02_setup_replica.sh`
   (`pg_stat_replication` row showing `state=streaming`).
3. The output of `03_replica_tests.sql` (in `replication_output.log`):
   - TEST 0: primary `in_recovery = f`, replica `in_recovery = t`.
   - TEST 1: the replica rejects the INSERT (`read-only transaction`).
   - TEST 2: the booking made on the primary is found on the replica and
     the replica's count is one higher.
   - TEST 3: `pg_stat_replication` shows `streaming`, `bytes_behind = 0`.
4. The partition-pruning EXPLAIN from `01_partition.sql` (only one
   `booking_p_YYYY_12` partition is scanned).
5. The architecture diagram from `04_cloud_architecture.md` (rendered
   ASCII art is fine; or redraw in draw.io).
6. The `SHOW wal_level;` and `SHOW synchronous_commit;` outputs from the
   primary, and `SHOW hot_standby;` from the replica.

---

## Git commit

```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partition, streaming replica on 5433, NDPA cloud arch, CAP, December rush"
git push
```

---

## Plain-English explanation

A single-node database is correct but fragile: if the host dies, the
business stops. P5 turns RoadLink Express into a distributed system by
doing three things.

**Partitioning** splits the `booking` table into monthly chunks. Each
chunk is its own physical file, so queries with a date range touch only
the relevant month — a query for "this week's bookings" scans the
current month's partition (a few thousand rows) instead of the whole
two-year history (50k+ rows). Old months can be detached and moved to
cheap S3 storage once they're past the regulatory retention window. In
Session 2's terms, this is **horizontal range fragmentation**.

**Streaming replication** keeps a second PostgreSQL cluster — running
on port 5433 — in lock-step with the primary. The primary writes every
change to its Write-Ahead Log (WAL); the replica receives the WAL over a
TCP connection and replays it, so it is at most a few milliseconds
behind. The replica is **read-only**: the test in `03_replica_tests.sql`
proves that any INSERT attempt on the replica raises
`cannot execute INSERT in a read-only transaction`. Seat-availability
reads (P2's Q1) are routed to the replica, freeing the primary to handle
the booking write path (P3) without read contention.

**Cloud architecture** places both clusters in a Nigerian cloud region
(Lagos, or on-prem) to satisfy NDPA 2023's data-residency requirement.
A second, asynchronous standby in Abuja provides disaster recovery —
if Lagos goes down, we promote Abuja and accept a small RPO (5–30 s of
lost writes) in exchange for availability. Within Lagos, the replica is
**synchronous** (`synchronous_standby_names = 'FIRST 1 (lagos_replica)'`)
so the booking write path is **CP** under CAP — no committed booking is
ever lost, even if the primary crashes immediately after COMMIT. The
read path is **AP** — eventual consistency on the replica, with a small
staleness window the user is told about in the UI.

The **December festive rush** is the stress test. December brings 3× the
normal booking volume (Christmas travel + end-of-year reunions). The
correctness guarantees from P1 (the `EXCLUDE USING gist` constraint
prevents bus/driver double-booking) and P3 (`SELECT … FOR UPDATE`
prevents seat double-booking) hold unchanged — December is a *capacity*
problem, not a *correctness* problem. We add a second Lagos replica,
bump `max_connections`, route more reads to the replica, and queue
payments in Redis Streams to absorb PSP rate limits.

This portfolio covers **Session 2** (distributed DB, fragmentation =
partitioning, replication, consistency models, CAP theorem, ACID vs
BASE), **Session 3** (cloud DB systems), and **Session 6** (NDPA 2023
data-privacy compliance — keeping data in-country is a privacy control).
