# Screenshots to capture (from YOUR own Codespace)

Save each image in this folder with these names. Only real output — no edited images.

| File | What to capture | Where it comes from |
|---|---|---|
| `p1_er_diagram.png` | The ER diagram drawn on the GitHub page of `portfolio-1-database-design/README.md` | GitHub, P1 folder |
| `p1_constraint_tests.png` | The 16-row PASS table + "Result: 16 of 16" | `p1_output.log` |
| `p1_row_counts.png` | The final table counts (≈180k bookings) | end of `p1_output.log` |
| `p2_summary.png` | The BEFORE / AFTER / speed-up table | end of `p2_output.log` |
| `p2_q7_plans.png` | Q7 plan before (Seq Scan) and after (Bitmap Index Scan) | `results/explain_before.txt`, `results/explain_after.txt` |
| `p3_rollback.png` | CASE 2 error + "0 rows" (seat released) | `p3_output.log` |
| `p3_race_parts.png` | Part 1 (2 rows, same seat) and Part 3 ("already booked") | `race_demos_output.log` |
| `p3_serializable_deadlock.png` | Part 4 (40001) and Part 6 (40P01) | `race_demos_output.log` |
| `p4_validator_and_counts.png` | 3 validator PASS lines + document counts | `p4_output.log` |
| `p4_collscan_ixscan.png` | BEFORE/AFTER totalDocsExamined summary | end of `p4_output.log` |
| `p5_partitions_pruning.png` | Rows per partition + the one-partition EXPLAIN | `partition_output.log` |
| `p5_replica.png` | TEST 1 read-only error, TEST 2 booking on replica, TEST 3 streaming | `replication_output.log` |

Tip: open the log in the editor (`code p1_output.log`) and use your computer's
screenshot tool (Windows: Win+Shift+S; Mac: Cmd+Shift+4).
