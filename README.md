# RoadLink Express — MIT 8103 Advanced Database Systems Portfolio

| Field | Value |
|---|---|
| Student | Animashaun Adeola |
| Matric number | 2026/A/MIT/0432 |
| Programme | Master of Information Technology |
| University | Miva Open University |
| Course | MIT 8103 — Advanced Database Systems |
| Cohort | September 2026 |
| Case study | Inter-state Bus Booking for **RoadLink Express** (simulated transport company) |
| GitHub repository | **[GitHub link]** *(paste your private repo URL here)* |

> **Repository URL (placeholder for the assessor):** `[GitHub link]`
> Please request access from the student if the repo is private.

---

## 1. Case study (one paragraph)

**RoadLink Express** is a simulated inter-state bus operator. It runs coaches
between terminals in **Lagos (Jibowu, Ojota), Abuja (Utako), Ibadan, Enugu,
Port Harcourt, Benin and Kano**. A passenger picks a *route* and a
*departure*, chooses a *seat*, pays, and travels. Each trip is operated by
exactly one bus and one driver, and carries a *manifest* of booked
passengers. The portfolio builds the relational schema, the booking
transaction, the NoSQL trip-manifest/review store, and a partitioned +
replicated cloud deployment that keeps all personal data inside Nigeria
(NDPA 2023).

---

## 2. Folder layout

```
advanced-database-portfolio/
├── README.md                              ← you are here
├── setup.sh                               ← installs PostgreSQL 16 + MongoDB 8 (Codespaces)
├── docs/
│   └── 00_brief_summary.md                ← Step 0: CA summary + portfolio↔study-session map
├── portfolio-1-database-design/
│   ├── README.md
│   ├── run_p1.sh
│   ├── er_diagram.mmd                     ← Mermaid ER diagram
│   ├── 01_schema.sql                      ← tables, keys, constraints
│   ├── 02_triggers.sql                    ← seat-capacity + arrival-after-departure triggers
│   ├── 03_seed.sql                        ← terminals, routes, buses, drivers, passengers
│   ├── 04_bulk_generate.py                ← ≈180k bookings: 2 years + next 14 days (no overlap, no double-sold seat)
│   ├── 05_constraint_tests.sql            ← tests that MUST FAIL
│   └── notes_3nf.md                       ← 3NF walk-through
├── portfolio-2-query-optimisation/
│   ├── README.md
│   ├── run_p2.sh
│   ├── 01_queries.sql                     ← 6 analysis queries
│   ├── 02_indexes.sql                     ← CREATE INDEX statements
│   ├── 03_explain_before.sql              ← EXPLAIN ANALYZE (no indexes)
│   ├── 04_explain_after.sql               ← EXPLAIN ANALYZE (with indexes)
│   └── results_before_after.md           ← table with [paste real result] cells
├── portfolio-3-transactions-concurrency/
│   ├── README.md
│   ├── run_p3.sh
│   ├── 01_book_seat.sql                   ← PL/pgSQL txn (lock trip, check seat, book, pay)
│   ├── 02_commit_rollback_demo.sql        ← failed payment releases the seat
│   ├── race_setup.sql / race_vars.sql     ← fixtures + psql variables for the demos
│   ├── run_race_demos.py                  ← runs Parts 1-6 with two real sessions
│   ├── 03_race_condition_guide.md         ← step tables: bug, UNIQUE, FOR UPDATE, SERIALIZABLE, RC vs RR, deadlock
│   ├── 04_isolation_levels.sql            ← reference list of the isolation steps
│   └── 05_deadlock_demo.md                ← deadlock + lock-ordering fix
├── portfolio-4-nosql/
│   ├── README.md
│   ├── run_p4.sh
│   ├── 00_export_from_postgres.sql        ← export the real P1 trips + passengers
│   ├── 01_schema_validation.js            ← JSON Schema validators (+ 3 rejection tests)
│   ├── 02_seed.js                          ← ≈ 46k manifests + reviews built from that export
│   ├── 03_indexes.js                       ← create indexes
│   ├── 04_aggregations.js                ← avg rating, complaints, delays per route
│   ├── 05_collscan_ixscan.js             ← EXPLAIN before vs after index
│   └── sql_vs_nosql.md                    ← SQL vs NoSQL comparison
└── portfolio-5-distributed-cloud/
    ├── README.md
    ├── run_p5.sh
    ├── 01_partition.sql                   ← bookings partitioned by month of departure
    ├── 02_setup_replica.sh                ← pg_basebackup + streaming replica
    ├── 03_replica_tests.sql               ← replica rejects writes, new rows arrive
    ├── 04_cloud_architecture.md           ← NDPA 2023, Nigeria region, CAP, sync vs async
    └── 05_december_rush.md                ← scaling the festive peak
```

---

## 3. First-time setup (Codespaces)

From the repo root, **once**:

```bash
# 1. Provision PostgreSQL 16 + MongoDB 8 (idempotent, ~3 min on first run)
bash setup.sh
```

The script:

* removes `/etc/apt/sources.list.d/yarn.list` (a known Codespaces breakage),
* installs `postgresql-16` + contrib (`btree_gist` and `pgcrypto` ship with it),
* installs MongoDB 8.0 from the official repo and starts `mongod` on `127.0.0.1:27017`,
* creates a `roadlink` role + `roadlink` database (time zone Africa/Lagos),
* adds a trust line at the **top** of `pg_hba.conf` so we can connect through
  the Unix socket without a password,
* reloads PostgreSQL.

Codespaces gotchas (already handled in `setup.sh` but worth knowing):

| Rule | What we do |
|---|---|
| `sudo -u postgres` does not work (PAM) | we use `sudo runuser -u postgres -- …` everywhere |
| TCP login needs a password | every `psql` connects through `host=/var/run/postgresql` |
| `pg_hba.conf` is order-sensitive | trust line is *prepended*, not appended |
| `pg_ctl` for v16 lives in `/usr/lib/postgresql/16/bin/` | absolute path used in `02_setup_replica.sh` |
| `pg_ctlcluster 16 main start/reload` is the cluster manager | used for start/reload |
| Don't use `postgres_fdw` | we never do |
| No fixed dates that expire | seed data uses `CURRENT_DATE - INTERVAL '...'` |

---

## 4. Running each portfolio

Every portfolio folder has a `run_pN.sh` that runs end-to-end:

```bash
cd portfolio-1-database-design  && bash run_p1.sh
cd portfolio-2-query-optimisation && bash run_p2.sh
cd portfolio-3-transactions-concurrency && bash run_p3.sh
cd portfolio-4-nosql && bash run_p4.sh
cd portfolio-5-distributed-cloud && bash run_p5.sh
```

Run them **in order, 1 → 5**: P2–P5 use the data P1 creates, and P4/P5 copy
it. Each script is safe to re-run, but re-running `run_p1.sh` rebuilds all
the data, so run P2–P5 again after it.

If the Codespace was stopped and restarted, start the databases again with:

```bash
sudo pg_ctlcluster 16 main start
pgrep -x mongod || sudo mongod --dbpath /data/db --logpath /var/log/mongodb/mongod.log --logappend --bind_ip 127.0.0.1 --fork
```

---

## 5. What each portfolio demonstrates (and which course-note study session)

| Portfolio | Demonstrates | Course-note study session |
|---|---|---|
| 1 — Database Design | ER + 3NF schema, constraints, bulk data, triggers | Session 1 (Traditional RDB + Normalisation) |
| 2 — Query Optimisation | 7 queries, EXPLAIN ANALYZE before/after indexes | Session 4 (Query Optimisation: execution plans, cost) |
| 3 — Transactions & Concurrency | ACID txn, race condition, isolation levels, deadlock | Session 1 (ACID) + Session 2 (consistency models) |
| 4 — NoSQL | MongoDB trip manifests + reviews, schema validation, aggregations, COLLSCAN→IXSCAN | Session 3 (Big Data) + Session 5 (Emerging trends: document/graph/edge) |
| 5 — Distributed & Cloud | Partitioning, streaming replica, NDPA 2023 cloud architecture, CAP trade-offs | Session 2 (Distributed DB, CAP, replication) + Session 3 (Cloud DB) + Session 6 (Data Privacy) |

---

## 6. Progressive git commits (evidence of continuous work)

The CA rubric rewards progressive commits. Suggested commit sequence:

```bash
# (the Codespace is already connected to your GitHub repo — no git init needed)
git add setup.sh README.md docs/00_brief_summary.md
git commit -m "P0: brief, setup.sh, repo README"
git add portfolio-1-database-design/
git commit -m "P1: ER, 3NF schema, constraints, triggers, 180k bookings, tests"
git add portfolio-2-query-optimisation/
git commit -m "P2: 7 queries, indexes, EXPLAIN ANALYZE before/after"
git add portfolio-3-transactions-concurrency/
git commit -m "P3: book_seat() txn, race-condition guide, isolation, deadlock"
git add portfolio-4-nosql/
git commit -m "P4: MongoDB manifests + reviews, validators, aggregations, index"
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly partition, streaming replica, NDPA cloud arch"
git push
```

After running everything and capturing real outputs, the final 2-3 page
documentation PDF (`Animashaun_Adeola_Documentation.pdf`) is uploaded to the
submission form; it can also be added to `docs/` in a final commit.

---

## 7. AI-use declaration

> **Tools:** an AI assistant ([name the tool you used, e.g. Z.ai]) drafted
> the first version of the scripts and READMEs from the CA brief. Claude
> (Anthropic) then ran every script in a Codespaces-like environment and
> fixed what failed — each fix is listed in `CHANGES.md`.
>
> **My part:** I chose the case study, ran every portfolio in my own GitHub
> Codespace, checked the outputs, and wrote the reflection myself. Every
> query result, EXPLAIN plan, timing and screenshot in my documentation is
> real output from my own run — nothing was invented or simulated.
>
> **How I checked it:** [in your own words — e.g. "I re-ran run_p1.sh and
> confirmed all 16 constraint tests PASS; I compared the BEFORE/AFTER
> timings in P2 with the plans; I watched the replica reject a write in P5".]

---

## 8. Academic integrity

The case study, the runs and the reflection are mine. Code was drafted and
corrected with the AI tools named above (see `CHANGES.md` for every
correction), and I can explain how each script works.
