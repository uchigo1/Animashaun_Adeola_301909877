# SQL vs NoSQL — comparison for the RoadLink Express case study

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432

This note compares the PostgreSQL relational model (Portfolio 1) with the
MongoDB document model (this portfolio) for the *same* RoadLink Express
case study, so the trade-offs are concrete rather than abstract.

---

## 1. What each model stores for the same trip

### PostgreSQL (P1)

The fact "trip 1234 has Chinedu Okafor driving, 47 passengers booked,
2 incidents" is split across **5 tables**:

```
trip (1234, route_id=1, bus_id=2, driver_id=3, depart, arrive, …)
   ↓ joins
route(1, …)             bus(2, …)              driver(3, …)
booking(1234, p1, 7)    booking(1234, p2, 8)   …   (47 rows)
```

A "give me the manifest for trip 1234" query is a 5-way JOIN. Updates to
the booking list (cancellations, re-seatings) write to the `booking` table
in real time, so the manifest is a *live* view.

### MongoDB (P4)

The same fact is one document in the `manifests` collection:

```json
{
  "tripId": 1234,
  "route": { "fromCity": "Lagos", "toCity": "Abuja", "distanceKm": 715, "fareNgn": 23500 },
  "bus":   { "plateNumber": "LAG-234-XA", "seatCapacity": 47 },
  "driver":{ "name": "Chinedu Okafor", "licenseNo": "NIG-DL-100001" },
  "departAt":  ISODate(...),
  "arriveAt":  ISODate(...),
  "passengers": [
    { "passengerId": 1, "name": "Adebayo Johnson", "seatNumber": 7, "fareNgn": 23500, "paidChannel": "CARD" },
    … 47 entries …
  ],
  "luggageKg": 564,
  "stops":       [ { "terminal": "Ore", "arrivedAt": …, "departedAt": … }, … ],
  "checkpoints": [ { "name": "Ore", "at": …, "ok": true }, … ],
  "incidents":   [ { "type": "BREAKDOWN", "at": …, "description": "Engine overheated", "resolvedAt": … } ],
  "createdAt":   ISODate(...)
}
```

The whole manifest is **fetched in one round trip** with no JOIN. The
passenger list is a *snapshot* — a frozen copy of the bookings at the
moment the manifest was generated. Subsequent booking changes do not
mutate the manifest, which is what the operations team actually wants
(a printed manifest must not silently change after the bus has departed).

---

## 2. Side-by-side trade-offs

| Dimension | PostgreSQL (P1) | MongoDB (P4) | Winner for RoadLink |
|---|---|---|---|
| **Schema rigidity** | Strict — columns, types, constraints are enforced server-side (UNIQUE trip+seat, EXCLUDE on tstzrange, CHECKs) | Loose — `validator: { $jsonSchema }` enforces required fields & types, but the optional fields (comfort, punctuality, driverBehaviour) vary per review with no migration | SQL for the booking path; Mongo for the manifest/review path |
| **Joins** | Mandatory — manifest = 5-way JOIN | None — denormalised into one document | Mongo (manifest) |
| **Transactions** | Full ACID, multi-statement, with `SELECT … FOR UPDATE` | Multi-document ACID since v4.0, but the manifest is a single document so it is naturally atomic | Tie |
| **Consistency model** | Strict consistency (single primary) | Strong consistency on the primary; read-from-secondary can be stale | SQL for booking; Mongo OK for manifests |
| **Read latency (manifest)** | 5-way JOIN across 50k+ bookings → ~10 ms after indexing | Single document fetch by `_id` or `tripId` → <1 ms | Mongo |
| **Write latency (booking)** | INSERT 1 row in `booking` + INSERT 1 row in `payment` = 2 writes | Would require either an in-place update of the manifest's passengers array (locks the whole document) OR a separate `bookings` collection (back to SQL's shape) | SQL |
| **Schema evolution** | ALTER TABLE migrates all rows; expensive on a 50M-row table | Add a new field — old documents simply lack it; no migration | Mongo |
| **Vertical vs horizontal scaling** | Vertical primarily; horizontal needs sharding + a coordinator (Citus, pg_fdw — which we are forbidden to use) | Native horizontal sharding by shard key | Mongo for very large scale |
| **Ad-hoc reporting** | SQL GROUP BY, window functions, CTEs — concise | Aggregation pipeline — verbose but powerful | SQL |
| **Storage cost** | Normalised → less duplication | Denormalised → passenger names repeated in every manifest | SQL |
| **Best fit for…** | High-write, strict-consistency OLTP (bookings, payments) | Read-heavy, denormalised, schema-variable reads (manifests, reviews, logs) | Both — polyglot persistence |

---

## 3. Why RoadLink Express uses BOTH

| Workload | Best store | Why |
|---|---|---|
| Online booking (write-heavy, strict ACID, race-condition-sensitive) | PostgreSQL | unique index on `(trip_id, seat_number)` for confirmed bookings + `EXCLUDE USING gist` + `SELECT … FOR UPDATE` |
| Seat-availability lookup (read-heavy, time-windowed) | PostgreSQL with indexes (P2) | Already indexed; 50k+ rows scan in <5 ms |
| Trip manifest printing (read-heavy, frozen snapshot, denormalised) | MongoDB | One document = one round-trip; passenger list is naturally a snapshot |
| Passenger reviews (variable fields, sparse, schema evolves) | MongoDB | Optional `comfort`, `punctuality`, `driverBehaviour` fields don't need migrations |
| Aggregations across manifests (delays per route, common complaints) | MongoDB | Pipeline handles nested arrays (`incidents`, `passengers`) without JOINs |

This is **polyglot persistence**: the same business fact (a trip) lives in
two stores, optimised for two different access patterns. The booking
transaction writes to PostgreSQL; an ETL job (or a Debezium CDC stream)
copies the just-booked trip's data into MongoDB as a manifest document
when the trip is "sealed" (i.e. the bus has departed and the manifest is
frozen).

---

## 4. CAP theorem framing

Both stores run as a single primary in P1–P4; P5 adds a streaming replica.
In CAP terms:

* **C**onsistency: PostgreSQL gives strong (linearisable) consistency on
  the primary; the replica is eventually consistent for reads.
* **A**vailability: a single-primary setup is *not* highly available — if
  the primary fails, you must promote a replica manually (or use automatic
  failover). MongoDB replica sets have built-in automatic failover, which
  improves availability at the cost of a short write outage during
  election.
* **P**artition tolerance: both tolerate network partitions between
  primary and replica, but neither accepts writes on the replica during
  the partition (PostgreSQL streaming replicas are read-only; MongoDB
  secondaries can serve reads if `readPreference=secondaryPreferred`,
  which trades consistency for availability).

For RoadLink Express — a transport operator where *the booking must never
silently lose data* — we pick **CP**: strong consistency over availability.
P5 explores this trade-off in more depth.

---

## 5. Suitability conclusion

For the RoadLink Express case study, MongoDB is the **right choice for
the manifest and review workloads** (read-heavy, denormalised,
schema-variable) and PostgreSQL is the **right choice for the booking and
payment workloads** (write-heavy, strict-consistency, race-sensitive).
Using both is not a contradiction — it is polyglot persistence, where each
store is optimised for the workload it serves best.

This portfolio covers **Session 3** (Big Data — NoSQL is the storage
engine for Big-Data-class workloads), **Session 5** (Emerging trends —
document, graph, edge databases are the "advanced data models" of the
session title), and connects back to **Session 1** (the limitations of
traditional RDBMS that motivate the NoSQL move).
