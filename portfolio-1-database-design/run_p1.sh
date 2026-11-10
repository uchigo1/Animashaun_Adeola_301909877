#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 1 — runner
# run_p1.sh — end-to-end: schema → seed → bulk generate → constraint tests
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

PSQL="sudo runuser -u postgres -- psql -d roadlink -v ON_ERROR_STOP=1 -X -q"

echo "================================================================"
echo "  P1 — Database Design (RoadLink Express)"
echo "================================================================"

echo "[1/6] (re)create schema + constraints …"
$PSQL -f 01_schema.sql

echo "[2/6] triggers (seat capacity, booked before departure, cancellation rules) …"
$PSQL -f 02_triggers.sql

echo "[3/6] seed terminals / routes / buses / drivers / passengers …"
$PSQL -f 03_seed.sql

echo "[4/6] bulk-generate 50k+ bookings over the last 2 years …"
python3 04_bulk_generate.py

echo "[5/6] run constraint tests (every bad insert must be rejected) …"
$PSQL -f 05_constraint_tests.sql

echo "[6/6] final table counts + ER diagram location …"
$PSQL -c "SELECT 'terminals' AS t, COUNT(*) FROM terminal
          UNION ALL SELECT 'routes',      COUNT(*) FROM route
          UNION ALL SELECT 'buses',       COUNT(*) FROM bus
          UNION ALL SELECT 'drivers',     COUNT(*) FROM driver
          UNION ALL SELECT 'passengers',  COUNT(*) FROM passenger
          UNION ALL SELECT 'trips',       COUNT(*) FROM trip
          UNION ALL SELECT 'bookings',    COUNT(*) FROM booking
          UNION ALL SELECT 'payments',    COUNT(*) FROM payment
          UNION ALL SELECT 'cancellations', COUNT(*) FROM cancellation
          ORDER BY t;"

echo
echo "================================================================"
echo "  P1 DONE."
echo "  ER diagram : shown in portfolio-1-database-design/README.md on GitHub"
echo "             (source: er_diagram.mmd)"
echo "  3NF notes : portfolio-1-database-design/notes_3nf.md"
echo "================================================================"
