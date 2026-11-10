#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 5 — runner
# run_p5.sh — partition bookings → set up streaming replica → run replica tests
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

PSQL="sudo runuser -u postgres -- psql -d roadlink -X -q"

echo "================================================================"
echo "  P5 — Distributed & Cloud Database Exercise (RoadLink Express)"
echo "================================================================"

echo "[1/3] partition booking_p by month of depart_at …"
$PSQL -v ON_ERROR_STOP=1 -f 01_partition.sql | tee partition_output.log

echo
echo "[2/3] set up a streaming replica on port 5433 …"
bash 02_setup_replica.sh 2>&1 | tee replication_output.log

echo
echo "[3/3] replica tests — write rejection, new row arrives, lag (one script) …"
$PSQL -f 03_replica_tests.sql 2>&1 | tee -a replication_output.log
echo

echo "================================================================"
echo "  P5 DONE. Evidence: replication_output.log"
echo "  Architecture write-up   : 04_cloud_architecture.md"
echo "  December-rush write-up   : 05_december_rush.md"
echo "================================================================"
