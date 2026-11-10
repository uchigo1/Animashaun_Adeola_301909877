# Cloud Architecture for RoadLink Express — NDPA 2023 + CAP + sync vs async

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432

> **Course-note sessions covered:** Session 2 — *Distributed Database
> System* (DDB architecture, fragmentation = partitioning, replication,
> consistency models, CAP theorem, ACID vs BASE); Session 3 — *Cloud
> Database Systems*; Session 6 — *Data Security & Data Privacy* (NDPA 2023
> is the Nigerian data-privacy law; keeping data in-country is a privacy
> control).

---

## 1. The data-residency requirement (NDPA 2023)

The **Nigeria Data Protection Act, 2023** (NDPA 2023) is the principal
Nigerian data-privacy law, enforced by the Nigeria Data Protection
Commission (NDPC). It does not ban storing data abroad, but its rules on
cross-border transfers (Part VIII) only allow personal data to leave Nigeria
where the destination gives an adequate level of protection or another legal
basis applies (for example consent or appropriate safeguards), and the
controller must be able to show this. The simplest way to stay compliant is
not to transfer at all.

RoadLink Express collects passenger names, phone numbers, email addresses,
payment channel identifiers and travel patterns. These are *personal data*
under NDPA. As a design choice, the architecture keeps all of it inside
Nigeria, so no cross-border transfer assessment is needed.

---

## 2. Reference architecture

```
                            ┌──────────────────────────────────────┐
                            │  Lagos Tier-3 data centre             │
                            │  (Nigerian colocation / local cloud   │
                            │   provider; all PII stays in Nigeria) │
                            │                                       │
                            │  ┌────────────────────────────────┐  │
                            │  │  RoadLink API (Next.js)        │  │
                            │  │  + booking-service (Go/Node)   │  │
                            │  └──────────┬─────────────────────┘  │
                            │             │                          │
                            │   ┌─────────┴──────────┐              │
                            │   │  PostgreSQL 16    │              │
                            │   │   PRIMARY          │              │
                            │   │   (write leader)   │              │
                            │   │   port 5432        │              │
                            │   └─────────┬──────────┘              │
                            │             │ streaming WAL           │
                            │             ▼                          │
                            │   ┌────────────────────┐               │
                            │   │ PostgreSQL 16       │               │
                            │   │  STREAMING REPLICA  │               │
                            │   │  (read-only)        │               │
                            │   │  port 5433          │               │
                            │   └────────────────────┘               │
                            │                                       │
                            │   ┌────────────────────┐               │
                            │   │ MongoDB 8          │               │
                            │   │  REPLICA SET       │               │
                            │   │  (manifests/reviews)│              │
                            │   └────────────────────┘               │
                            │                                       │
                            │   ┌────────────────────┐               │
                            │   │ Object storage     │               │
                            │   │ (S3 — encrypted)   │               │
                            │   │  manifest PDFs,    │               │
                            │   │  audit logs         │               │
                            │   └────────────────────┘               │
                            └──────────────────────────────────────┘

                            ┌──────────────────────────────────────┐
                            │  Abuja DR site                       │
                            │  (warm standby — async replica)      │
                            │                                       │
                            │   ┌────────────────────┐               │
                            │   │ PostgreSQL 16       │               │
                            │   │  ASYNC STANDBY      │               │
                            │   │  (DR only, no reads)│               │
                            │   └────────────────────┘               │
                            └──────────────────────────────────────┘
```

### Components

| Layer | Choice | Why |
|---|---|---|
| Compute | RoadLink API (Next.js + Go/Node micro-services) | Stateless; horizontally scalable behind a load balancer |
| Relational DB | PostgreSQL 16 primary + 1 streaming replica | Same case study as P1–P3; seat-availability reads hit the replica, booking writes hit the primary |
| Document DB | MongoDB 8 replica set | Same case study as P4; manifests and reviews |
| Object storage | S3-compatible, encrypted at rest | Manifest PDFs, audit logs, backups |
| Region | Lagos data centre (Nigerian colocation or local cloud provider) | NDPA 2023 — keeps passenger PII in Nigeria |
| DR site | Abuja (warm async standby) | Geographic redundancy; Lagos→Abuja is ~700 km so a single regional outage (power, fibre cut) does not lose data |

---

## 3. Partitioning = "data fragmentation" (Session 2)

The portfolio partitions `booking_p` by **month of `depart_at`** (see
`01_partition.sql`). In Session 2's terminology this is **horizontal
fragmentation by range** — each monthly partition is a fragment holding the
rows whose `depart_at` falls in that month. Benefits:

* **Pruning** — queries with `WHERE depart_at BETWEEN ...` touch only the
  relevant partitions, not the full 50k+ row history.
* **Archive** — old months can be detached (`ALTER TABLE … DETACH
  PARTITION`) and moved to cheaper storage (S3 + Parquet) once they are
  past the regulatory retention window.
* **Parallelism** — PostgreSQL can run partition-wise joins in parallel
  workers, scanning different months on different CPU cores.

---

## 4. Replication = "physical replication" (Session 2)

The portfolio uses PostgreSQL's **streaming replication** (see
`02_setup_replica.sh`): the primary continuously ships WAL segments over
a TCP connection to the replica. The replica replays them as they arrive,
so it is at most a few milliseconds behind the primary (the "replication
lag"). This is **physical replication** (byte-level) — distinct from
**logical replication** (row-level, via `pg_logical` slots), which we do
not use here because physical replication is simpler and works for the
whole cluster, not per-table.

In Session 2's terminology, the streaming replica is a **read replica
with eventual consistency**: writes committed on the primary are *not*
visible on the replica until the WAL reaches it. The replication lag is
typically < 100 ms on the same LAN, but a partition (network break)
between primary and replica means the replica falls behind, and reads
from it can return stale data.

---

## 5. CAP theorem placement

The CAP theorem (Session 2) says a distributed system can guarantee **at
most two** of {Consistency, Availability, Partition-tolerance}. Because
network partitions *can* happen, the practical choice is between **CP**
and **AP**.

| Workload | CAP choice | Why |
|---|---|---|
| Booking write path (P3) | **CP** (strong consistency) | A seat cannot be sold to two passengers; if the primary is unreachable, we FAIL the booking rather than risk inconsistency. The primary is the single source of truth. |
| Seat-availability read path (P2) | **AP-ish** (eventual consistency, reads from replica) | For "show me free seats" the user is OK seeing a few-seconds-stale view; if the replica is unreachable we fall back to the primary. Availability > strong consistency here. |
| Manifest / review (P4) | **AP** (MongoDB replica set, reads from secondary) | Manifests are denormalised snapshots; a few seconds of staleness is invisible. |
| Disaster recovery (DR) | **AP** (Abuja async standby) | If Lagos goes down we promote Abuja. We accept that the last few seconds of writes might be lost (RPO ~ 5–30 s) in exchange for availability. |

The portfolio therefore demonstrates a **hybrid CP / AP** strategy — the
write path is CP (synchronous on the primary, with FOR UPDATE locks from
P3 enforcing isolation); the read path is AP (replica reads with eventual
consistency); the DR path is AP with a small RPO.

---

## 6. Sync vs async replication trade-offs

| Aspect | Synchronous (synchronous_commit=on, synchronous_standby_names set) | Asynchronous (default) |
|---|---|---|
| **Durability** | A write is committed only after the replica ACKs the WAL → no data loss on primary failure (RPO = 0) | WAL is shipped async; if the primary crashes after COMMIT and before WAL is shipped, that write is lost (RPO > 0, typically < 5 s) |
| **Write latency** | Higher — COMMIT waits for the replica ACK (~2–10 ms on LAN, much more over WAN) | Lower — COMMIT returns as soon as WAL is flushed locally |
| **Availability** | Lower — if the replica is unreachable, the primary blocks writes (or falls back to async, depending on `synchronous_standby_names` config) | Higher — primary keeps writing even if the replica is offline |
| **Use for** | Lagos primary + Lagos replica (same DC, LAN latency) — strong consistency for the booking path | Lagos primary + Abuja DR (700 km WAN) — DR only, accept small RPO |
| **CAP placement** | CP (strong consistency, lower availability under partition) | AP-ish (higher availability, accept small RPO) |

### What we pick for RoadLink Express

* **Lagos primary → Lagos replica (LAN)**: **synchronous**, with
  `synchronous_standby_names = 'FIRST 1 (lagos_replica)'`. This means
  every booking COMMIT waits for the Lagos replica to ack the WAL. Write
  latency is ~5 ms higher, but no booking is ever lost if the primary
  crashes.
* **Lagos primary → Abuja DR (WAN)**: **asynchronous**. The 700 km WAN
  round-trip would add 10–30 ms to every booking if synchronous, which
  is unacceptable for the user experience. We accept RPO ≈ 5–30 s on
  the Abuja standby.

### Configuration knobs (already set in 02_setup_replica.sh)

```ini
# primary postgresql.conf
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
synchronous_commit = on                       # the COMMIT-wait flag
synchronous_standby_names = 'FIRST 1 (lagos_replica)'
```

```ini
# replica postgresql.conf
hot_standby = on                              # allow read queries during recovery
hot_standby_feedback = on                     # replica sends vacuum hints to primary
```

---

## 7. NDPA 2023 — what we actually do

| NDPA 2023 requirement | Architectural control |
|---|---|
| Cross-border transfer rules (Part VIII) | All clusters run in the Lagos region; the Abuja standby is also in Nigeria. No data crosses the Nigerian border. |
| Encryption at rest | PostgreSQL data directory on LUKS-encrypted disks; MongoDB encrypted at rest; backups encrypted with keys held in a Lagos key-management service. |
| Encryption in transit | TLS 1.3 on every connection (API → DB, primary → replica, replica → DR). Self-signed certs are NOT used; the Lagos KMS issues them. |
| Access control | Role-based: `roadlink` (read-write booking), `roadlink_read` (read-only seat-availability), `roadlink_repl` (replication), `roadlink_admin` (DDL). `pg_hba.conf` enforces. |
| Audit log | `pgaudit` extension; every DDL and DML written to a separate audit table; logs shipped to write-once object storage in the Lagos data centre. |
| Data subject rights (access, rectification, erasure) | `passenger.email` is indexed; a "right to be forgotten" job sets `passenger.full_name='ANONYMISED'` and `email=NULL` for the requested passenger, cascading to booking rows. The MongoDB manifest snapshot is intentionally NOT mutated (a printed manifest is a legal record of who was on the bus). |
| Data retention | Booking + payment rows kept only for the tax-record retention period, then anonymised. Old monthly partitions are detached and archived; manifests archived after 90 days. |
| Cross-border transfer | None — all data stays in Nigeria. If a foreign regulator demands data, the request goes through the NDPC. |

---

## 8. CAP & ACID/BASE reconciliation

| Property | ACID (P3) | BASE (P4/P5 read path) |
|---|---|---|
| Atomicity | Booking + payment in one txn | Manifest write is single-document atomic |
| Consistency | Strong (CP) | Eventual (replica lag) |
| Isolation | READ COMMITTED + FOR UPDATE | Read-from-secondary is stale |
| Durability | Synchronous WAL flush on primary | Replica ack required for the Lagos pair |

RoadLink Express is therefore **CP for writes** (strict ACID on the
primary) and **AP for reads** (eventual consistency on the replica). The
CAP theorem forces the choice; we cannot have all three.

---

## 9. Conclusion

The portfolio demonstrates a real Nigerian-cloud deployment that:

* partitions the booking history by month (P5 file `01_partition.sql`),
* runs a streaming read replica on the same Codespace (P5 file
  `02_setup_replica.sh`),
* proves the replica rejects writes and that primary commits arrive on the
  replica (P5 file `03_replica_tests.sql`),
* keeps all PII inside Nigeria for NDPA 2023,
* uses synchronous replication within Lagos (CP for the write path) and
  asynchronous replication to Abuja (AP for DR),
* and explicitly chooses CP for the booking write path and AP for the
  seat-availability read path.

This portfolio covers **Session 2** (distributed DB, fragmentation,
replication, consistency models, CAP theorem, ACID vs BASE), **Session 3**
(cloud DB systems), and **Session 6** (NDPA 2023 data-privacy compliance).
