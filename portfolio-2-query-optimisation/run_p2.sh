#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 2 — runner
# run_p2.sh — runs the 6 queries, EXPLAIN BEFORE, adds indexes, EXPLAIN AFTER
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

PSQL="sudo runuser -u postgres -- psql -d roadlink -X -q"

echo "================================================================"
echo "  P2 — Query Optimisation (RoadLink Express)"
echo "================================================================"

mkdir -p results

echo "[1/4] running the 7 analysis queries (raw outputs) …"
$PSQL -f 01_queries.sql

echo
echo "[2/4] EXPLAIN ANALYZE — BEFORE indexes …"
$PSQL -f 03_explain_before.sql | tee results/explain_before.txt

echo
echo "[3/4] adding indexes …"
$PSQL -f 02_indexes.sql

echo
echo "[4/4] EXPLAIN ANALYZE — AFTER indexes …"
$PSQL -f 04_explain_after.sql | tee results/explain_after.txt

echo
echo "================================================================"
echo "  SUMMARY — Execution Time per query (real numbers from this run)"
echo "================================================================"
summ() { grep -E "^--- Q|Execution Time" "$1" | awk '/^--- Q/{q=$2; sub(":","",q); next} /Execution Time/{print q, $3}'; }
printf "%-5s %14s %14s %9s\n" "Query" "BEFORE (ms)" "AFTER (ms)" "speed-up"
join <(summ results/explain_before.txt) <(summ results/explain_after.txt) | \
  awk '{ printf "%-5s %14.3f %14.3f %8.1fx\n", $1, $2, $3, ($3>0 ? $2/$3 : 0) }'
echo
echo "================================================================"
echo "  P2 DONE."
echo "  Full plans saved in portfolio-2-query-optimisation/results/"
echo "  Copy the real timings into results_before_after.md"
echo "================================================================"
