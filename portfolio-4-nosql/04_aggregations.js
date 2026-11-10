// =============================================================================
// RoadLink Express — MIT 8103 Portfolio 4
// 04_aggregations.js — three pipeline aggregations
// =============================================================================
// Run AFTER 03_indexes.js:
//   mongosh --quiet --file 04_aggregations.js
//
// Three aggregations, mirroring the CA's NoSQL deliverables:
//   A) Average rating per route
//   B) Common complaints (low-rating reviews, grouped by optional free-text)
//   C) Delays per route (manifests with incidents, grouped by corridor)
// =============================================================================

db = db.getSiblingDB('roadlink');   // ("use roadlink" does not work inside a --file script)

// print an aggregation result as one readable line per document
function show(rows) {
  rows.forEach(r => print('  ' + EJSON.stringify(r, { relaxed: true })
    .replace(/"_id":\{/, '').replace(/[{}"]/g, '').replace(/,/g, ', ')));
  print('  (' + rows.length + ' rows)');
}

print('====================================================================');
print(' A — Average rating per route');
print('====================================================================');
const avgRatingPerRoute = db.reviews.aggregate([
  { $group: {
      _id: { fromCity: '$route.fromCity', toCity: '$route.toCity' },
      avgRating: { $avg: '$rating' },
      reviewCount: { $sum: 1 },
      oneStar: { $sum: { $cond: [{ $eq: ['$rating', 1] }, 1, 0] } },
      fiveStar: { $sum: { $cond: [{ $eq: ['$rating', 5] }, 1, 0] } }
  }},
  { $sort: { avgRating: 1 } },               // worst-rated routes first
  { $set: { avgRating: { $round: ['$avgRating', 2] } } }
]);
show(avgRatingPerRoute.toArray());

print('');
print('====================================================================');
print(' B — Common complaints (low-rating reviews, grouped by free-text)');
print('====================================================================');
const commonComplaints = db.reviews.aggregate([
  { $match: { rating: { $lte: 2 } } },
  { $facet: {
      comfort: [
        { $match: { comfort: { $exists: true } } },
        { $group: { _id: '$comfort', count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 5 }
      ],
      punctuality: [
        { $match: { punctuality: { $exists: true } } },
        { $group: { _id: '$punctuality', count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 5 }
      ],
      driverBehaviour: [
        { $match: { driverBehaviour: { $exists: true } } },
        { $group: { _id: '$driverBehaviour', count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 5 }
      ],
      comment: [
        { $match: { comment: { $exists: true } } },
        { $group: { _id: '$comment', count: { $sum: 1 } } },
        { $sort: { count: -1 } },
        { $limit: 5 }
      ]
  }}
]);
const cc = commonComplaints.toArray()[0];
for (const k of Object.keys(cc)) { print('  ' + k + ':'); cc[k].forEach(x => print('     ' + x.count + '  ' + x._id)); }

print('');
print('====================================================================');
print(' C — Delays (incidents) per route');
print('====================================================================');
const delaysPerRoute = db.manifests.aggregate([
  // only manifests that have ≥1 incident
  { $match: { 'incidents.0': { $exists: true } } },
  { $unwind: '$incidents' },
  { $group: {
      _id: {
        fromCity: '$route.fromCity',
        toCity:   '$route.toCity',
        type:     '$incidents.type'
      },
      incidentCount: { $sum: 1 },
      avgResolutionMins: {
        $avg: {
          $divide: [
            { $subtract: ['$incidents.resolvedAt', '$incidents.at'] },
            60 * 1000
          ]
        }
      }
  }},
  { $sort: { incidentCount: -1 } },
  { $limit: 15 },
  { $set: { avgResolutionMins: { $round: ['$avgResolutionMins', 0] } } }
]);
show(delaysPerRoute.toArray());

print('');
print('====================================================================');
print('  Aggregations complete. Paste real outputs into the documentation.');
print('====================================================================');
