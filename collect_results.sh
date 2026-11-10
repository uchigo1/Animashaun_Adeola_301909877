#!/usr/bin/env bash
# =============================================================================
# collect_results.sh — gather the key REAL numbers from your own run into
# my_results.txt (used to write the 2-3 page documentation).
# Run from the repo root AFTER all five portfolios have been run:
#   bash collect_results.sh && code my_results.txt
# =============================================================================
cd "$(dirname "$0")"
OUT=my_results.txt
PSQL="sudo runuser -u postgres -- psql -d roadlink -X -q"
P1=portfolio-1-database-design; P2=portfolio-2-query-optimisation
P3=portfolio-3-transactions-concurrency; P4=portfolio-4-nosql; P5=portfolio-5-distributed-cloud

{
echo "MY RESULTS — RoadLink Express — $(date '+%Y-%m-%d %H:%M %Z')"
echo
echo "===== P1: row counts (live) ====="
$PSQL -c "SELECT 'terminals' t, count(*) FROM terminal UNION ALL SELECT 'routes', count(*) FROM route
          UNION ALL SELECT 'buses', count(*) FROM bus UNION ALL SELECT 'drivers', count(*) FROM driver
          UNION ALL SELECT 'passengers', count(*) FROM passenger UNION ALL SELECT 'trips', count(*) FROM trip
          UNION ALL SELECT 'bookings', count(*) FROM booking UNION ALL SELECT 'payments', count(*) FROM payment
          UNION ALL SELECT 'cancellations', count(*) FROM cancellation;"
echo "===== P1: constraint tests ====="
grep -E "PASS|FAIL|Result:" $P1/p1_output.log 2>/dev/null || echo "(no p1_output.log — run: bash run_p1.sh | tee p1_output.log)"
echo
echo "===== P2: BEFORE / AFTER timings ====="
sed -n '/SUMMARY/,/P2 DONE/p' $P2/p2_output.log 2>/dev/null | grep -E "^Q[0-9]|Query" || echo "(no p2_output.log)"
echo "--- plan changes (first scan line per query) ---"
for f in before after; do
  echo "[$f]"
  awk '/^--- Q/{q=$2; seen=0} /Scan/ && !seen && q!=""{sub(/^ *(->)? */,""); print "  " q " " substr($0,1,70); seen=1}' \
      $P2/results/explain_$f.txt 2>/dev/null
done
echo
echo "===== P3: race demos ====="
grep -E "PART|ERROR \[|>>>" $P3/race_demos_output.log 2>/dev/null || echo "(no race_demos_output.log)"
grep -E "CASE|confirmed_bookings|violates check" -A2 $P3/p3_output.log 2>/dev/null | grep -E "CASE|^ +[0-9]+ *$|violates" | head -12
echo
echo "===== P4: MongoDB ====="
grep -E "PASS|FAIL|manifests  :|reviews    :|total docs|BEFORE  |AFTER  " $P4/p4_output.log 2>/dev/null || echo "(no p4_output.log)"
echo
echo "===== P5: partitions + pruning ====="
sed -n '/partitions of booking_p/,$p' $P5/partition_output.log 2>/dev/null | grep -v -e '^ *$' -e '^-*+' -e '^===' | head -60
echo "===== P5: replica ====="
grep -E "PRIMARY|REPLICA|read-only|bookings_on|streaming|^ +[0-9]+ \| |walreceiver" $P5/replication_output.log 2>/dev/null | head -24
echo
echo "===== GitHub ====="
git remote get-url origin 2>/dev/null
git log --oneline | head -12
} > "$OUT" 2>&1

echo "Saved $OUT — open it with:  code $OUT"
