// =============================================================================
// RoadLink Express — MIT 8103 Portfolio 4
// 01_schema_validation.js — MongoDB JSON Schema validators for two collections
// =============================================================================
// Student: Animashaun Adeola  | Matric 2026/A/MIT/0432
// Run:
//   mongosh --quiet --file 01_schema_validation.js
//
// Two collections:
//   manifests  — one document per trip, with a passenger-list SNAPSHOT,
//                luggage, stops, checkpoints and incidents (these vary
//                per trip, so the document model is the right choice).
//   reviews    — one document per passenger review of a trip; rating is
//                required, plus optional comfort, punctuality, driverBehaviour
//                free-text fields.
// =============================================================================

db = db.getSiblingDB('roadlink');   // ("use roadlink" does not work inside a --file script)

// ---------------------------------------------------------------------------
// drop & re-create both collections so the script is idempotent
// ---------------------------------------------------------------------------
db.manifests.drop();
db.reviews.drop();
db.createCollection('manifests');
db.createCollection('reviews');

// ---------------------------------------------------------------------------
// manifests validator
// ---------------------------------------------------------------------------
db.runCommand({
  collMod: 'manifests',
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['tripId', 'route', 'bus', 'driver', 'departAt', 'arriveAt',
                 'passengers', 'luggageKg', 'stops', 'checkpoints', 'incidents', 'createdAt'],
      properties: {
        tripId:         { bsonType: 'long',   description: 'must be a long and is required' },
        status:         { enum: ['SCHEDULED', 'COMPLETED'] },
        route: {
          bsonType: 'object',
          required: ['fromCity', 'toCity', 'distanceKm', 'fareNgn'],
          properties: {
            fromCity:    { bsonType: 'string' },
            toCity:       { bsonType: 'string' },
            distanceKm:   { bsonType: 'double', minimum: 0 },
            fareNgn:      { bsonType: 'double', minimum: 0 }
          }
        },
        bus: {
          bsonType: 'object',
          required: ['plateNumber', 'seatCapacity'],
          properties: {
            plateNumber:  { bsonType: 'string' },
            seatCapacity: { bsonType: 'int', minimum: 1 }
          }
        },
        driver: {
          bsonType: 'object',
          required: ['name', 'licenseNo'],
          properties: {
            name:       { bsonType: 'string' },
            licenseNo:  { bsonType: 'string' }
          }
        },
        departAt:    { bsonType: 'date' },
        arriveAt:     { bsonType: 'date' },
        // passenger-list SNAPSHOT — denormalised copy of the bookings at the
        // moment the manifest was generated. Subsequent booking changes do
        // NOT mutate this snapshot; that is intentional.
        passengers: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['passengerId', 'name', 'seatNumber'],
            properties: {
              passengerId: { bsonType: 'long' },
              name:        { bsonType: 'string' },
              phone:       { bsonType: 'string' },
              seatNumber:  { bsonType: 'int', minimum: 1 },
              fareNgn:      { bsonType: 'double', minimum: 0 },
              paidChannel: { enum: ['CARD', 'BANK_TRANSFER', 'USSD', 'CASH', 'WALLET'] }
            }
          }
        },
        luggageKg:    { bsonType: 'double', minimum: 0 },
        // varying per trip — a Lagos→Ibadan hop has 1 stop; Lagos→Kano has 3+
        stops: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['terminal', 'arrivedAt'],
            properties: {
              terminal:   { bsonType: 'string' },
              arrivedAt:   { bsonType: 'date' },
              departedAt:  { bsonType: 'date' }
            }
          }
        },
        checkpoints: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['name', 'at'],
            properties: {
              name: { bsonType: 'string' },        // e.g. "Ore checkpoint"
              at:   { bsonType: 'date' },
              ok:   { bsonType: 'bool' }            // false = incident logged
            }
          }
        },
        // incidents are SPARSE — many trips have none.
        incidents: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['type', 'at', 'description'],
            properties: {
              type:        { enum: ['BREAKDOWN', 'WEATHER', 'SECURITY', 'MEDICAL', 'TRAFFIC', 'OTHER'] },
              at:          { bsonType: 'date' },
              description: { bsonType: 'string' },
              resolvedAt:  { bsonType: 'date' }
            }
          }
        },
        createdAt:    { bsonType: 'date' }
      }
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

// ---------------------------------------------------------------------------
// reviews validator
// ---------------------------------------------------------------------------
db.runCommand({
  collMod: 'reviews',
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['reviewId', 'tripId', 'route', 'passengerId', 'rating', 'submittedAt'],
      properties: {
        _id:           { bsonType: 'objectId' },   // must be listed: additionalProperties is false
        reviewId:      { bsonType: 'string' },
        tripId:        { bsonType: 'long' },
        route: {
          bsonType: 'object',
          required: ['fromCity', 'toCity'],
          properties: {
            fromCity: { bsonType: 'string' },
            toCity:   { bsonType: 'string' }
          }
        },
        passengerId:   { bsonType: 'long' },
        passengerName: { bsonType: 'string' },
        rating:        { bsonType: 'int', minimum: 1, maximum: 5 },     // 1–5 stars
        // OPTIONAL fields — vary per review (some passengers comment only
        // on comfort, others only on driver behaviour, etc.)
        comfort:         { bsonType: 'string' },
        punctuality:     { bsonType: 'string' },
        driverBehaviour: { bsonType: 'string' },
        comment:         { bsonType: 'string' },
        submittedAt:     { bsonType: 'date' }
      },
      additionalProperties: false
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

print('====================================================================');
print('  Collections created with JSON Schema validators:');
print('    roadlink.manifests  — required: tripId, route, bus, driver,');
print('                          departAt, arriveAt, passengers[], luggageKg,');
print('                          stops[], checkpoints[], incidents[], createdAt');
print('    roadlink.reviews    — required: reviewId, tripId, route, passengerId,');
print('                          rating (1–5), submittedAt');
print('                          optional: comfort, punctuality, driverBehaviour, comment');
print('====================================================================');
print('  Validators in force: validationLevel=strict, validationAction=error');
print('====================================================================');

// ---------------------------------------------------------------------------
// prove the validator works: two bad reviews must be rejected
// ---------------------------------------------------------------------------
function tryInsert(label, doc) {
  try {
    db.reviews.insertOne(doc);
    print('  FAIL  ' + label + ' — bad document was ACCEPTED');
  } catch (e) {
    print('  PASS  ' + label + ' — rejected: ' + e.message);
  }
}
print('');
print('  Validator tests (each bad document must be rejected):');
tryInsert('rating = 6 (must be 1-5)', {
  reviewId: 'TEST-1', tripId: Long.fromNumber(1), route: { fromCity: 'Lagos', toCity: 'Ibadan' },
  passengerId: Long.fromNumber(1), rating: Int32(6), submittedAt: new Date() });
tryInsert('missing rating', {
  reviewId: 'TEST-2', tripId: Long.fromNumber(1), route: { fromCity: 'Lagos', toCity: 'Ibadan' },
  passengerId: Long.fromNumber(1), submittedAt: new Date() });
tryInsert('unknown field "cvv"', {
  reviewId: 'TEST-3', tripId: Long.fromNumber(1), route: { fromCity: 'Lagos', toCity: 'Ibadan' },
  passengerId: Long.fromNumber(1), rating: Int32(4), submittedAt: new Date(), cvv: '123' });
db.reviews.deleteMany({ reviewId: /^TEST-/ });
