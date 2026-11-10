// =============================================================================
// RoadLink Express — MIT 8103 Portfolio 4
// 03_indexes.js — create the indexes that turn COLLSCANs into IXSCANs
// =============================================================================
// Run AFTER 02_seed.js:
//   mongosh --quiet --file 03_indexes.js
// =============================================================================

db = db.getSiblingDB('roadlink');   // ("use roadlink" does not work inside a --file script)

// Index the manifest lookup-by-tripId path
db.manifests.createIndex({ tripId: 1 }, { name: 'idx_manifest_tripId' });

// Index reviews by tripId so we can join manifests ↔ reviews
db.reviews.createIndex({ tripId: 1 }, { name: 'idx_review_tripId' });

// Index reviews by (route.fromCity, route.toCity) — the per-route aggregation
db.reviews.createIndex(
  { 'route.fromCity': 1, 'route.toCity': 1 },
  { name: 'idx_review_route' }
);

// Index reviews by rating — speeds the "common complaints" filter
db.reviews.createIndex({ rating: 1 }, { name: 'idx_review_rating' });

// Index manifests by route + departAt — speeds the "delays per route"
// aggregation that groups incidents by corridor.
db.manifests.createIndex(
  { 'route.fromCity': 1, 'route.toCity': 1, departAt: 1 },
  { name: 'idx_manifest_route_depart' }
);

// Index manifests by incidents (sparse — only docs that HAVE incidents)
db.manifests.createIndex(
  { 'incidents.type': 1 },
  { name: 'idx_manifest_incident_type', sparse: true }
);

print('====================================================================');
print('  Indexes created on roadlink.manifests and roadlink.reviews.');
print('  Index list:');
print('====================================================================');
printjson(db.manifests.getIndexes());
printjson(db.reviews.getIndexes());
