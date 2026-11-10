# Portfolio 4 — NoSQL & Advanced Data Models

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Case:** RoadLink Express

> **Course-note sessions covered:** Session 3 — *Big Data and Cloud Database Systems* (NoSQL is the storage engine for Big-Data-class workloads); Session 5 — *Emerging Trends* (document/graph/edge databases are the "advanced data models" of the session title); connecting back to Session 1 — *Limitations of traditional RDBMS*.

---

## What this portfolio demonstrates

Two MongoDB collections, built from the *same* RoadLink Express case study
as P1, that show where a document store is a better fit than a relational
schema:

| Collection | Shape | Why document-store |
|---|---|---|
| `manifests` | One document per trip, with **passenger-list snapshot**, luggage, stops, checkpoints, incidents — all varying per trip | Denormalised → one fetch returns the whole manifest; incidents and stops arrays are sparse (most trips have 0–2 incidents, but Lagos→Kano has 4+); no JOINs needed for the printed manifest |
| `reviews` | One document per passenger review; rating required, optional free-text fields for `comfort`, `punctuality`, `driverBehaviour`, `comment` | Schema is intentionally variable — passengers comment on different aspects; in SQL this would need either many nullable columns or an EAV table |

Plus:

* **JSON Schema validation** with `validationLevel: 'strict'`,
  `validationAction: 'error'` — MongoDB enforces required fields and
  types server-side, like a strict relational schema.
* **≈ 46,000 documents built from the real P1 data**: one manifest per
  PostgreSQL trip (≈ 4,900, same tripId, bus, driver and confirmed
  passengers) and ≈ 42,000 reviews written only by passengers who really
  travelled on a completed trip. Stops follow the real road for each
  corridor (e.g. Lagos → Abuja: Ibadan, Ilorin, Lokoja); upcoming trips are
  `SCHEDULED` with no stops or incidents yet.
* **Validator tests** — three bad reviews (rating 6, missing rating, an
  unknown `cvv` field) are inserted and must be rejected.
* **Three aggregation pipelines**:
  - Average rating per route (group + avg + sort)
  - Common complaints (low-rating reviews, faceted by optional free-text)
  - Delays per route (manifests with incidents, unwound, grouped)
* **COLLSCAN → IXSCAN demonstration** — same query run with `.explain()`
  before and after creating an index, showing the planner's switch from a
  collection scan to an index scan and the corresponding drop in
  `totalDocsExamined` and `executionTimeMillis`.
* **SQL vs NoSQL comparison** (`sql_vs_nosql.md`) — side-by-side trade-offs
  for the same case study, with the polyglot-persistence recommendation.

---

## Files

| File | Purpose |
|---|---|
| `00_export_from_postgres.sql` | Exports every P1 trip with its confirmed passengers to `/tmp/roadlink_trips.jsonl` |
| `01_schema_validation.js` | Creates `manifests` + `reviews` collections with `$jsonSchema` validators, then proves they reject bad documents |
| `02_seed.js` | Turns that export into ≈ 4,900 manifests + ≈ 42,000 reviews (≈ 46k documents) |
| `03_indexes.js` | Creates six indexes (incl. a sparse index on `incidents.type`) |
| `04_aggregations.js` | Three aggregation pipelines (avg rating, complaints, delays) |
| `05_collscan_ixscan.js` | Drops the `idx_review_tripId` index, runs `.explain()`, recreates the index, runs `.explain()` again — shows the COLLSCAN→IXSCAN transition |
| `sql_vs_nosql.md` | Side-by-side comparison with the P1 PostgreSQL schema; polyglot-persistence recommendation |
| `run_p4.sh` | End-to-end runner |

---

## How to run (Codespaces)

From the repo root:

```bash
bash setup.sh        # if not done — starts mongod on 127.0.0.1:27017
cd portfolio-4-nosql
bash run_p4.sh
```

`run_p4.sh` runs:

0. `00_export_from_postgres.sql` — export the real trips (P1 must have run)
1. `01_schema_validation.js` — create collections + validators + validator tests
2. `02_seed.js` — build ≈ 46k documents from the export (well under a minute)
3. `03_indexes.js` — create six indexes
4. `04_aggregations.js` — print the three aggregation results
5. `05_collscan_ixscan.js` — print the COLLSCAN vs IXSCAN explain plans

MongoDB is started by `setup.sh` on `127.0.0.1:27017` with no auth —
`mongosh` connects without credentials.

---

## What to screenshot for the LMS submission

1. The output of `bash run_p4.sh` — collection counts showing 40k+
   documents.
2. The `$jsonSchema` validator printout from
   `db.runCommand({listCollections: 1})` so the assessor can see the
   schema is enforced.
3. The three aggregation outputs (avg rating per route, common
   complaints, delays per route).
4. The two `.explain()` plans side by side: BEFORE (COLLSCAN) and AFTER
   (IXSCAN), with the `totalDocsExamined` and `executionTimeMillis`
   numbers circled.
5. A document from each collection (`db.manifests.findOne()` and
   `db.reviews.findOne()`) so the assessor can see the variable-shape
   reviews (one with all four optional fields, one with only `comment`).
6. The `db.manifests.getIndexes()` and `db.reviews.getIndexes()` output.

---

## Git commit

```bash
git add portfolio-4-nosql/
git commit -m "P4: MongoDB manifests + reviews from real trips, JSON Schema validators, 46k docs, 3 aggregations, COLLSCAN→IXSCAN, SQL vs NoSQL"
git push
```

---

## Plain-English explanation

A trip manifest is the printed sheet the driver carries that lists every
passenger, every stop, every checkpoint, and every incident. In SQL, the
equivalent is a five-way JOIN of `trip + route + bus + driver + booking`,
plus an outer join to `cancellation` to know who actually showed up, plus
a separate query for stops and incidents. In MongoDB, the manifest is
*one document* — fetched in a single round trip, ready to print.

Crucially, the manifest's passenger list is a **snapshot**: it is the list
as it was when the bus departed. New bookings after departure must not
silently change the printed manifest. In SQL, this requires either a
materialised view that is refreshed at departure, or a separate
`manifest_passengers` history table. In MongoDB, the snapshot is just a
nested array that is copied at manifest-generation time and never updated
again — a much cleaner fit for the workload.

Reviews are the other natural document-store use case. A passenger might
say "the AC was broken" without rating punctuality; another might say
"the driver was rude" without commenting on comfort. In SQL this needs
either many nullable columns (wasteful and rigid) or an EAV table
(`review_attributes(review_id, key, value)` — flexible but verbose to
query). In MongoDB, the optional fields simply appear in some documents
and not in others, with no migration needed when a new field is added.

The **JSON Schema validator** is the bridge between "schemaless" and
"schemaful": required fields are enforced server-side (you cannot insert a
manifest without `tripId`, `route`, `bus`, `driver`, `passengers`, …), but
optional fields remain free-form. This is the sweet spot between SQL's
rigidity and the original NoSQL "store anything" model.

The **COLLSCAN → IXSCAN demo** is the same lesson as P2's EXPLAIN ANALYZE
comparison, but in MongoDB: without an index, the planner scans every
document in the collection (COLLSCAN); with an index on `tripId`, it jumps
straight to the matching documents (IXSCAN), and `totalDocsExamined`
drops from N to k. The `executionTimeMillis` drops proportionally.

The **SQL vs NoSQL comparison** documents the polyglot-persistence
recommendation: keep the booking and payment path in PostgreSQL (where
strict ACID + UNIQUE constraints + EXCLUDE constraints matter most), and
move the manifest and review workloads to MongoDB (where denormalisation,
sparse fields and document-atomic updates are the better fit). This is
not a contradiction — it is two stores optimised for two different access
patterns, with an ETL job (or a Debezium CDC stream) copying a just-sealed
trip from PostgreSQL to MongoDB as a manifest document.

This portfolio covers **Session 3** (Big Data), **Session 5** (Emerging
trends: document, graph, edge databases), and connects back to **Session
1** (limitations of traditional RDBMS that motivated the NoSQL move).
