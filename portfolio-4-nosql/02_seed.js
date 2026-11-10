// =============================================================================
// RoadLink Express — MIT 8103 Portfolio 4
// 02_seed.js — build ~45,000 MongoDB documents from the REAL P1 data
// =============================================================================
// Student: Animashaun Adeola  | Matric 2026/A/MIT/0432
//
// Input : /tmp/roadlink_trips.jsonl, written by 00_export_from_postgres.sql
//         (one line per PostgreSQL trip, with its confirmed passengers)
// Output: roadlink.manifests — one document per trip (≈ 4,900)
//         roadlink.reviews   — reviews by passengers who really travelled
//                              (≈ 25% of them, ≈ 40,000)
//
// Why this matters: the manifest's tripId, bus, driver and passenger list are
// the SAME as in PostgreSQL, so a manifest can be joined back to the SQL
// booking. Stops and checkpoints follow the real road for each corridor, and
// only trips that have already happened get stops, incidents and reviews.
//
// Run AFTER 01_schema_validation.js (run_p4.sh does the export first):
//   mongosh --quiet --file 02_seed.js
// =============================================================================

db = db.getSiblingDB('roadlink');
const fs = require('fs');
const INPUT = '/tmp/roadlink_trips.jsonl';
const NOW = new Date();

// deterministic pseudo-random numbers, so every run gives the same data
let _s = 8103;
function rand() { _s = (_s * 1664525 + 1013904223) >>> 0; return _s / 4294967296; }
function randInt(a, b) { return a + Math.floor(rand() * (b - a + 1)); }
function pick(arr) { return arr[Math.floor(rand() * arr.length)]; }
function maybe(p) { return rand() < p; }
function addMin(d, m) { return new Date(d.getTime() + m * 60000); }

// ---------------------------------------------------------------------------
// towns a coach passes on each corridor (listed one way; reversed for the
// return trip)
// ---------------------------------------------------------------------------
const CORRIDOR = {
  'Lagos|Ibadan':          ['Sagamu Interchange'],
  'Lagos|Benin':           ['Sagamu Interchange', 'Ore'],
  'Lagos|Abuja':           ['Ibadan', 'Ilorin', 'Lokoja'],
  'Lagos|Port Harcourt':   ['Ore', 'Benin', 'Onitsha', 'Owerri'],
  'Lagos|Kano':            ['Ilorin', 'Jebba', 'Kaduna', 'Zaria'],
  'Abuja|Kano':            ['Kaduna', 'Zaria'],
  'Abuja|Enugu':           ['Lafia', 'Makurdi', 'Otukpo'],
  'Ibadan|Abuja':          ['Ilorin', 'Lokoja'],
  'Enugu|Port Harcourt':   ['Aba'],
  'Enugu|Lagos':           ['Onitsha', 'Benin', 'Ore'],
  'Port Harcourt|Abuja':   ['Owerri', 'Enugu', 'Otukpo', 'Lafia'],
  'Benin|Abuja':           ['Auchi', 'Okene', 'Lokoja']
};
function townsFor(from, to) {
  if (CORRIDOR[from + '|' + to]) return CORRIDOR[from + '|' + to];
  if (CORRIDOR[to + '|' + from]) return CORRIDOR[to + '|' + from].slice().reverse();
  return [];
}

const INCIDENTS = [
  ['TRAFFIC',   'Heavy traffic / gridlock'],
  ['TRAFFIC',   'Road works, single-lane diversion'],
  ['BREAKDOWN', 'Tyre puncture, wheel changed'],
  ['BREAKDOWN', 'Engine overheated, cooled down'],
  ['WEATHER',   'Heavy rain, reduced speed'],
  ['SECURITY',  'Extended security checkpoint'],
  ['MEDICAL',   'Passenger felt unwell, stopped at clinic']
];
const GOOD = {
  comfort: ['comfortable seats', 'AC worked well', 'clean bus', 'smooth ride'],
  punctuality: ['departed on time', 'arrived on schedule', 'arrived early'],
  driverBehaviour: ['professional driver', 'drove carefully', 'helpful with luggage'],
  comment: ['great trip overall', 'will use RoadLink again', 'excellent value', 'recommend to friends']
};
const BAD = {
  comfort: ['AC was not working', 'legroom tight', 'seat was broken', 'bus was dirty'],
  punctuality: ['left 30 min late', 'delayed for hours', 'arrived very late'],
  driverBehaviour: ['speeding on the highway', 'rude to passengers', 'too many unscheduled stops'],
  comment: ['disappointing service', 'not worth the fare', 'poor communication about the delay']
};

const raw = fs.readFileSync(INPUT, 'utf8').split('\n').filter(l => l.trim().length > 0);
print('[seed] ' + raw.length + ' trips read from ' + INPUT);

db.manifests.deleteMany({});
db.reviews.deleteMany({});

let manifests = [], reviews = [], nManifests = 0, nReviews = 0;
function flush(force) {
  if (manifests.length >= 500 || (force && manifests.length)) {
    db.manifests.insertMany(manifests, { ordered: true }); nManifests += manifests.length; manifests = [];
  }
  if (reviews.length >= 2000 || (force && reviews.length)) {
    db.reviews.insertMany(reviews, { ordered: true }); nReviews += reviews.length; reviews = [];
  }
}

for (const line of raw) {
  const t = JSON.parse(line);
  const departAt = new Date(t.departAt);
  const plannedArrive = new Date(t.arriveAt);
  const completed = plannedArrive < NOW;
  const towns = townsFor(t.fromCity, t.toCity);
  const durMin = (plannedArrive - departAt) / 60000;

  // incidents and delay only for trips that have happened
  const incidents = [];
  let delay = 0;
  if (completed) {
    delay = randInt(0, 25);
    if (maybe(0.16)) {
      const n = maybe(0.2) ? 2 : 1;
      for (let k = 0; k < n; k++) {
        const [type, description] = pick(INCIDENTS);
        const at = addMin(departAt, randInt(30, Math.max(31, Math.floor(durMin) - 30)));
        const lost = type === 'BREAKDOWN' ? randInt(30, 150) : randInt(15, 90);
        delay += lost;
        incidents.push({ type, at, description, resolvedAt: addMin(at, lost) });
      }
    }
  }
  const arriveAt = completed ? addMin(plannedArrive, delay) : plannedArrive;

  // stops: each corridor town, evenly spaced, 15-25 min rest
  const stops = [];
  if (completed) {
    towns.forEach((town, idx) => {
      const arr = addMin(departAt, Math.round(durMin * (idx + 1) / (towns.length + 1)) + Math.round(delay * (idx + 1) / (towns.length + 1)));
      stops.push({ terminal: town, arrivedAt: arr, departedAt: addMin(arr, randInt(15, 25)) });
    });
  }
  // checkpoints: FRSC / police checks near some of those towns
  const checkpoints = [];
  if (completed) {
    const places = towns.length ? towns : [t.toCity];
    places.forEach((town, idx) => {
      if (idx === 0 || maybe(0.5)) {
        checkpoints.push({
          name: pick(['FRSC check', 'Police check']) + ' near ' + town,
          at: addMin(departAt, Math.round(durMin * (idx + 0.5) / (places.length + 1))),
          ok: !incidents.some(i => i.type === 'SECURITY')
        });
      }
    });
  }

  const passengers = t.passengers.map(p => ({
    passengerId: Long.fromNumber(p.id),
    name: p.name,
    phone: p.phone,
    seatNumber: Int32(p.seat),
    fareNgn: Double(p.fare),
    paidChannel: p.channel
  }));

  manifests.push({
    tripId: Long.fromNumber(t.tripId),
    status: completed ? 'COMPLETED' : 'SCHEDULED',
    route: { fromCity: t.fromCity, fromTerminal: t.fromTerminal, toCity: t.toCity, toTerminal: t.toTerminal,
             distanceKm: Double(t.km), fareNgn: Double(t.fare) },
    bus: { plateNumber: t.plate, seatCapacity: Int32(t.cap), model: t.model },
    driver: { name: t.driver, licenseNo: t.licence },
    departAt, arriveAt,
    delayMinutes: Int32(delay),
    passengers,
    cancelledBookings: Int32(t.cancelled),
    luggageKg: Double(completed ? passengers.length * randInt(8, 16) : 0),
    stops, checkpoints, incidents,
    createdAt: completed ? addMin(departAt, -45) : NOW
  });

  // reviews: ~25% of passengers on completed trips; worse trips, worse stars
  if (completed) {
    for (const p of t.passengers) {
      if (!maybe(0.25)) continue;
      const hadTrouble = incidents.length > 0 || delay > 60;
      let rating = hadTrouble ? randInt(1, 4) : (maybe(0.85) ? randInt(4, 5) : randInt(2, 3));
      const notes = rating >= 4 ? GOOD : BAD;
      const doc = {
        reviewId: 'REV-' + t.tripId + '-' + p.seat,
        tripId: Long.fromNumber(t.tripId),
        route: { fromCity: t.fromCity, toCity: t.toCity },
        passengerId: Long.fromNumber(p.id),
        passengerName: p.name,
        rating: Int32(rating)
      };
      // OPTIONAL fields — each review mentions only what that passenger cared about
      if (maybe(0.5)) doc.comfort = pick(notes.comfort);
      if (maybe(0.5) || (hadTrouble && rating <= 2)) doc.punctuality = pick(notes.punctuality);
      if (maybe(0.35)) doc.driverBehaviour = pick(notes.driverBehaviour);
      if (maybe(0.6)) doc.comment = pick(notes.comment);
      let sub = addMin(arriveAt, randInt(30, 72 * 60));
      if (sub > NOW) sub = addMin(NOW, -randInt(1, 30));
      doc.submittedAt = sub;
      reviews.push(doc);
    }
  }
  flush(false);
}
flush(true);

print('');
print('====================================================================');
print('  manifests  : ' + db.manifests.countDocuments({}) + '  (' +
      db.manifests.countDocuments({ status: 'SCHEDULED' }) + ' upcoming, ' +
      db.manifests.countDocuments({ 'incidents.0': { $exists: true } }) + ' with incidents)');
print('  reviews    : ' + db.reviews.countDocuments({}));
print('  total docs : ' + (db.manifests.countDocuments({}) + db.reviews.countDocuments({})));
print('  target was : 40,000+ documents');
print('====================================================================');
