// =============================================================================
// RoadLink Express — MIT 8103 Portfolio 4
// 05_collscan_ixscan.js — COLLSCAN before index, IXSCAN after index
// =============================================================================
// Demonstrates the COLLSCAN → IXSCAN transition by running the same query
// with .explain() FIRST without the index, then with the index.
//
// Run:
//   mongosh --quiet --file 05_collscan_ixscan.js
//
// Paste the two explain() outputs into the documentation PDF.
// =============================================================================

db = db.getSiblingDB('roadlink');   // ("use roadlink" does not work inside a --file script)

// ---------------------------------------------------------------------------
// 1. Choose a query that is selective enough to benefit from an index:
//    "find all reviews for tripId = 1"
// ---------------------------------------------------------------------------
const TEST_TRIP_ID = Long.fromNumber(1);

print('====================================================================');
print(' STEP 1 — drop any index on reviews.tripId to force a COLLSCAN');
print('====================================================================');
try { db.reviews.dropIndex('idx_review_tripId'); } catch (e) { print('  (no idx_review_tripId yet)'); }

print('');
print('====================================================================');
print(' STEP 2 — explain() BEFORE index (expect COLLSCAN)');
print('====================================================================');
const before = db.reviews.find({ tripId: TEST_TRIP_ID }).explain('executionStats');
printjson(before.executionStats);
print('---- winning plan ----');
printjson(before.queryPlanner.winningPlan);

print('');
print('====================================================================');
print(' STEP 3 — create the index idx_review_tripId');
print('====================================================================');
db.reviews.createIndex({ tripId: 1 }, { name: 'idx_review_tripId' });

print('');
print('====================================================================');
print(' STEP 4 — explain() AFTER index (expect IXSCAN)');
print('====================================================================');
const after = db.reviews.find({ tripId: TEST_TRIP_ID }).explain('executionStats');
printjson(after.executionStats);
print('---- winning plan ----');
printjson(after.queryPlanner.winningPlan);

print('');
print('====================================================================');
print('  Summary (paste into the documentation):');
print('    BEFORE  totalDocsExamined : ' + before.executionStats.totalDocsExamined);
print('    BEFORE  executionTimeMs   : ' + before.executionStats.executionTimeMillis);
print('    AFTER   totalDocsExamined : ' + after.executionStats.totalDocsExamined);
print('    AFTER   executionTimeMs   : ' + after.executionStats.executionTimeMillis);
print('====================================================================');
