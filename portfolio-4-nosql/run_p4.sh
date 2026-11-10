#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 4 — runner
# run_p4.sh — schema validation → seed 40k+ docs → indexes → aggregations
#             → COLLSCAN vs IXSCAN
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

MONGOSH="mongosh --quiet"

echo "================================================================"
echo "  P4 — NoSQL & Advanced Data Models (RoadLink Express)"
echo "================================================================"

echo "[0/5] export the real trips + passengers from PostgreSQL (P1 data) …"
sudo runuser -u postgres -- psql -d roadlink -X -q -f 00_export_from_postgres.sql

echo
echo "[1/5] create collections + JSON Schema validators …"
$MONGOSH --file 01_schema_validation.js

echo
echo "[2/5] build trip manifests + passenger reviews from that export (≈ 45k documents) …"
$MONGOSH --file 02_seed.js

echo
echo "[3/5] create indexes …"
$MONGOSH --file 03_indexes.js

echo
echo "[4/5] run the three aggregations (avg rating, complaints, delays) …"
$MONGOSH --file 04_aggregations.js

echo
echo "[5/5] COLLSCAN → IXSCAN explain demo …"
$MONGOSH --file 05_collscan_ixscan.js

echo
echo "================================================================"
echo "  P4 DONE."
echo "  Paste real outputs into the documentation PDF."
echo "================================================================"
