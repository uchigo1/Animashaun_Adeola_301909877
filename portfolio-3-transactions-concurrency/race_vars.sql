-- race_vars.sql — run this FIRST in each psql terminal:   \i race_vars.sql
-- It loads the demo ids made by race_setup.sql into psql variables
-- (:trip_id, :trip2, :pa, :pb, :pc, :seat, :seat2, :seat3) so every step in
-- 03_race_condition_guide.md can be pasted exactly as written.
SELECT max(val) FILTER (WHERE key = 'trip_id') AS trip_id,
       max(val) FILTER (WHERE key = 'trip2')   AS trip2,
       max(val) FILTER (WHERE key = 'pa')      AS pa,
       max(val) FILTER (WHERE key = 'pb')      AS pb,
       max(val) FILTER (WHERE key = 'pc')      AS pc,
       max(val) FILTER (WHERE key = 'seat')    AS seat,
       max(val) FILTER (WHERE key = 'seat2')   AS seat2,
       max(val) FILTER (WHERE key = 'seat3')   AS seat3
FROM race_demo
\gset
\echo 'Loaded: trip_id=' :trip_id ' trip2=' :trip2 ' Kemi(pa)=' :pa ' Tobi(pb)=' :pb ' Halima(pc)=' :pc ' seats=' :seat :seat2 :seat3
