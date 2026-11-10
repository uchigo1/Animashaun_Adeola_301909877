#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 3 — runner
# run_p3.sh — installs book_seat(), runs the COMMIT/ROLLBACK demo, prints the
# race-condition and isolation/deadlock instructions.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

PSQL="sudo runuser -u postgres -- psql -d roadlink -X -q"

echo "================================================================"
echo "  P3 — Transactions & Concurrency (RoadLink Express)"
echo "================================================================"

echo "[1/4] installing book_seat() transaction function …"
$PSQL -f 01_book_seat.sql

echo
echo "[2/4] COMMIT/ROLLBACK demo — failed payment releases the seat …"
$PSQL -f 02_commit_rollback_demo.sql

echo
echo "[3/4] race-demo fixtures (2 demo trips, Kemi / Tobi / Halima, booking_bug) …"
$PSQL -v ON_ERROR_STOP=1 -f race_setup.sql

echo
echo "[4/4] the six two-session demos (two real database sessions at once) …"
python3 run_race_demos.py | tee race_demos_output.log
echo

echo "================================================================"
echo "  P3 DONE. Evidence: race_demos_output.log (Parts 1-6)."
echo "  To do the demos by hand in two terminals: 03_race_condition_guide.md"
echo "================================================================"
