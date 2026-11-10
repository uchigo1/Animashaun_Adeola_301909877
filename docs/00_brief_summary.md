# 00 — Brief summary of the CA + portfolio ↔ study-session map

**Student:** Animashaun Adeola · **Matric:** 2026/A/MIT/0432 · **Course:** MIT 8103 Advanced Database Systems · **Cohort:** September 2026 · **Case study:** RoadLink Express (inter-state bus booking).

Source PDFs read:
1. `mit-8103-advanced-database-systems-ca-september-cohort-2026.pdf` — the official Continuous Assessment brief (Miva Open University, 2026/2027 First Semester).
2. `Edited - MIT8103 Advanced Database Systems.pdf` — the Miva MIT 8103 course notes (154 pages, 6 study sessions).

---

## (a) What the CA requires

### Deliverables and weight

| Component | Activity | Marks |
|---|---|---|
| Portfolio 1 | Database Design and Modelling | 7 |
| Portfolio 2 | Query Processing and Optimisation | 7 |
| Portfolio 3 | Transactions and Concurrency | 7 |
| Portfolio 4 | NoSQL and Advanced Data Models | 7 |
| Portfolio 5 | Distributed and Cloud Database Exercise | 6 |
| Final Documentation | 2–3 page summary, GitHub link, reflection, refs/AI-use | 6 |
| **Total** | | **40** |

### Case-study rule
The student picks **one** realistic organisation and uses it consistently across
all 5 portfolios. It may be real, simulated, or a realistic scenario. The choice
must be stated at the top of the documentation, including: organisation name,
nature of the business, users, major data, and key operations. The CA lists 10
example types (university result portal, bank/fintech, e-commerce, hospital,
hotel, library, ride-hailing, social media, real-time leaderboard). Our choice
— **inter-state bus booking** — falls under the *ride-hailing/logistics* family
and is explicitly allowed ("…but not limited to").

### GitHub repository rules
* **Private** repo named `advanced-database-portfolio/` with sub-folders
  `portfolio-1-database-design/ … portfolio-5-distributed-cloud/` + top-level
  `README.md`.
* Must contain SQL scripts, schemas, ER diagrams/models, NoSQL implementations,
  execution plans and performance results, screenshots/config/test results,
  README files.
* **Progressive commits** are required — "Waiting until the deadline to upload
  all files may reduce the evidence of continuous portfolio development."

### LMS submission
A **2–3 page** documentation describing all five activities, naming the case
study, and linking to the GitHub repo. Repo must be accessible to the assessor
**before** LMS submission. Supporting screenshots required.

### Naming rules (inferred from the brief)
* Folder names must follow the suggested structure
  (`portfolio-1-database-design/` … `portfolio-5-distributed-cloud/`).
* Top-level `README.md` required.
* Final documentation is uploaded through the LMS as a single document; the
  student-chosen file name `Animashaun_Adeola_2026-A-MIT-0432_Documentation.pdf`
  embeds matric number to satisfy the "individual work" requirement.

### Submission rules
* LMS upload + accessible GitHub link.
* Individual work — discussion is allowed, but scripts, analysis, documentation
  and conclusions must be the student's own.

### AI-use declaration
Required *if* AI tools are used. Must state: (i) the AI tool, (ii) what it was
used for, (iii) how the output was reviewed/corrected/tested/verified. AI use
does **not** remove the student's responsibility for accuracy, originality and
understanding.

### Similarity / originality
The brief emphasises "academic integrity," "individual work," "evidence of
independent work," and warns that "simply submitting screenshots or copied
code without demonstrating understanding will not receive full marks." Students
with "unclear, copied, inaccessible, or suspicious submissions may be invited
for an individual verification discussion" — i.e. a viva sample may be drawn.

### Verification for the large cohort
No compulsory viva. Verification relies on: progressive GitHub commits, clear
READMEs, screenshots/outputs/logs/configs, and a short individual technical
reflection. A small random sample may be called for a brief technical
verification chat.

### Marking rubric (40 total)

| Criteria | Marks |
|---|---|
| Technical correctness | 8 |
| Database design quality | 6 |
| Practical implementation | 8 |
| Query and performance analysis | 5 |
| Application of advanced database concepts | 5 |
| Documentation and GitHub organisation | 5 |
| Technical reflection / evidence of individual understanding | 3 |

---

## (b) Portfolio ↔ Miva MIT 8103 course-note study-session map

The course notes (`Edited - MIT8103 Advanced Database Systems.pdf`, 154 pages)
contain **6 study sessions**:

| Session | Title | Topics covered |
|---|---|---|
| 1 | Review of Traditional Relational Databases and Advanced Concepts | DB design, components, characteristics of a good DB, **normalisation**, limitations of traditional DBMS |
| 2 | Distributed Database System | DDB architecture, peer-peer / client-server / federated, **data fragmentation, replication, consistency models**, **CAP theorem, BASE vs ACID** |
| 3 | Big Data and Cloud Database Systems | Big Data, **cloud DB systems**, cloud DB use cases, data warehouse, introduction to DB security |
| 4 | Query Optimisation in Database | Queries, **query optimisation**, **execution plans and cost estimation**, file organisation |
| 5 | Emerging Trends in Database Systems | AI-powered DBs, blockchain, **edge DBs, serverless DBs, graph DBs and knowledge graphs** |
| 6 | Introduction to Data Security and Data Privacy | Data privacy, advanced quantitative techniques, challenges, best practices |

### Mapping table

| Portfolio | What it produces | Primary study session(s) | Secondary session(s) | Why |
|---|---|---|---|---|
| **P1 — Database Design & Modelling** | ER diagram, 3NF relational schema, constraints (UNIQUE trip+seat, two `btree_gist` exclusion constraints on `tstzrange` for bus/driver overlaps, seat-capacity trigger, fare/payment > 0), ≈180k bookings, bulk generator, constraint tests | **Session 1** — *Review of Traditional RDB & Advanced Concepts* (DB design, normalisation, characteristics of a good DB) | Session 6 (data security: constraint-enforced integrity is the first line of defence) | P1 is exactly the "design + normalise + constrain" content of Session 1, applied to RoadLink Express. |
| **P2 — Query Processing & Optimisation** | 7 queries (free seats, bookings/route/month, revenue/terminal, load factor, busiest days, cancellation rate, one passenger's history), `EXPLAIN ANALYZE` before vs after indexes, before/after table | **Session 4** — *Query Optimisation in Database* (queries, query optimisation, execution plans & cost estimation, file organisation) | Session 1 (a normalised schema is the precondition for sane query plans) | P2 is the practical application of execution plans + cost estimation from Session 4. |
| **P3 — Transactions & Concurrency** | `book_seat()` ACID transaction (check seat free → create booking → record payment → COMMIT), COMMIT/ROLLBACK demo (failed payment releases seat), step-by-step 2-psql race-condition guide (bug → UNIQUE fix → `SELECT … FOR UPDATE` fix), isolation-level demo (READ COMMITTED / REPEATABLE READ / SERIALIZABLE), deadlock demo | **Session 1** — *Traditional RDB & Advanced Concepts* (ACID, characteristics of a good DB) **and** **Session 2** — *Distributed Database System* (consistency models, ACID vs BASE) | Session 4 (the race-condition write path is exactly what query optimisation on hot rows must protect) | ACID is the central concept of Session 1; the consistency-models discussion of Session 2 is the theoretical backbone of the isolation-level demo. |
| **P4 — NoSQL & Advanced Data Models** | MongoDB trip manifests (passenger snapshot, luggage, stops, checkpoints, incidents — varying per trip) and passenger reviews (ratings + optional comfort/punctuality/driver-behaviour fields), JSON schema validation, aggregations (avg rating per route, common complaints, delays per route), ≈46k docs built from the P1 trips, `COLLSCAN → IXSCAN` index demo, SQL vs NoSQL comparison | **Session 3** — *Big Data and Cloud Database Systems* (Big Data ⇒ NoSQL stores are the storage engine) **and** **Session 5** — *Emerging Trends* (document/graph/edge DBs are the "advanced data models" of the title) | Session 1 (the same case study, modelled relationally in P1, gives the direct SQL-vs-NoSQL comparison) | Document stores are the natural "advanced data model" for trip manifests with variable shape; the SQL-vs-NoSQL comparison maps back to Session 1's limitations-of-traditional-DBMS discussion. |
| **P5 — Distributed & Cloud Database Exercise** | Bookings partitioned by month of departure, primary + streaming read replica for seat-availability searches (replica rejects writes, new rows arrive), cloud architecture keeping data in Nigeria under **NDPA 2023**, CAP theorem + sync vs async replication trade-offs, handling the December festive rush | **Session 2** — *Distributed Database System* (DDB architecture, fragmentation = partitioning, replication, consistency models, CAP theorem, ACID vs BASE) **and** **Session 3** — *Cloud Database Systems* (cloud DB + use cases) | **Session 6** — *Data Security & Data Privacy* (NDPA 2023 is the Nigerian data-privacy law; keeping data in-country is a privacy control) | Partitioning = fragmentation; streaming replica = physical replication; CAP discussion = direct from Session 2; cloud-deployment discussion = Session 3; the NDPA framing ties it to Session 6. |

### Cross-cutting threads

* **Same case study, five angles.** Every portfolio re-uses RoadLink Express
  data, so the same passengers, routes, buses, drivers and trips flow through
  the SQL schema (P1), the queries (P2), the booking transaction (P3), the
  MongoDB manifests/reviews (P4), and the partitioned/replicated deployment
  (P5).
* **Honesty discipline.** Per the brief's §10 (assessment expectations) and
  §11 (academic integrity + AI-use), every EXPLAIN plan, timing and screenshot
  in the *final documentation PDF* must come from real Codespaces runs. The
  scripts in this repo contain `[paste real output here]` placeholders exactly
  where the student must paste captured output before submission.
