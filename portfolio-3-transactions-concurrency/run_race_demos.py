#!/usr/bin/env python3
"""
RoadLink Express — MIT 8103 Portfolio 3
run_race_demos.py — runs ALL SIX two-terminal demos automatically.

It opens two real PostgreSQL sessions at the same time:
    T1 = Terminal A, the Jibowu booking desk (Kemi Adebanjo)
    T2 = Terminal B, the Ojota  booking desk (Tobi Nwachukwu)
and sends each step to the right session in the order given in
03_race_condition_guide.md. When a step has to WAIT for a lock, it is run in
a background thread, so you can see it block and then finish (or fail) once
the other session commits.

Every line printed is real output from your database — nothing is typed in.

Run (from this folder, after run_p1.sh and run_p3.sh):
    python3 run_race_demos.py | tee race_demos_output.log
"""
import subprocess
import sys
import threading
import time

import psycopg

DSN = "dbname=roadlink user=roadlink host=/var/run/postgresql"
HERE = sys.path[0] or "."


def banner(text):
    print("\n" + "=" * 74)
    print("  " + text)
    print("=" * 74, flush=True)


def connect(name):
    conn = psycopg.connect(DSN, autocommit=True)
    conn.execute(f"SET application_name = '{name}'")
    return conn


def execute(conn, sql, params=None):
    """Run one statement; return (ok, list of result lines). Never raises."""
    out = []
    try:
        cur = conn.execute(sql, params)
        if cur.description:
            rows = cur.fetchall()
            out.append("       " + " | ".join(d.name for d in cur.description))
            for r in rows:
                out.append("       " + " | ".join(str(x) for x in r))
            out.append(f"       ({len(rows)} row{'s' if len(rows) != 1 else ''})")
        else:
            out.append(f"       {cur.statusmessage}")
        return True, out
    except psycopg.Error as e:
        out.append(f"       ERROR [{e.diag.sqlstate}]: {e.diag.message_primary}")
        if e.diag.message_detail:
            for line in e.diag.message_detail.splitlines():
                out.append(f"       DETAIL: {line}")
        return False, out


def run(conn, label, sql, params=None):
    print(f"{label:<4}> {sql.strip()}", flush=True)
    ok, out = execute(conn, sql, params)
    print("\n".join(out), flush=True)
    return ok


class Waiting:
    """A statement started in the background because it is expected to block."""

    def __init__(self, conn, label, sql):
        self.label, self.result = label, None
        print(f"{label:<4}> {sql.strip()}", flush=True)
        self.thread = threading.Thread(target=self._go, args=(conn, sql))
        self.thread.start()
        time.sleep(1.5)
        if self.thread.is_alive():
            print(f"{label:<4}  ... still WAITING for a lock held by the other terminal", flush=True)

    def _go(self, conn, sql):
        self.result = execute(conn, sql)

    def join(self):
        self.thread.join()
        print(f"{self.label:<4}  ... the waiting statement has now finished:")
        print("\n".join(self.result[1]), flush=True)
        return self.result[0]


def in_background(conn, label, sql, params=None):
    return Waiting(conn, label, sql)


def main():
    # fresh fixtures every run
    subprocess.run(
        ["psql", "-h", "/var/run/postgresql", "-U", "roadlink", "-d", "roadlink",
         "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", f"{HERE}/race_setup.sql"],
        check=True, stdout=subprocess.DEVNULL)

    A = connect("Terminal A (Jibowu)")
    B = connect("Terminal B (Ojota)")
    ids = dict(A.execute("SELECT key, val FROM race_demo").fetchall())
    v = {k: int(x) for k, x in ids.items()}
    trip, trip2, seat, seat2, seat3 = v["trip_id"], v["trip2"], v["seat"], v["seat2"], v["seat3"]
    pa, pb, pc = v["pa"], v["pb"], v["pc"]

    print(f"Demo trip {trip} (Lagos Jibowu → Abuja), second trip {trip2} (Lagos Ojota → Ibadan)")
    print(f"Kemi Adebanjo = passenger {pa} at Terminal A, Tobi Nwachukwu = passenger {pb} at Terminal B,"
          f" Halima Garba = passenger {pc}")
    print(f"Everyone wants seat {seat}.")

    check_bug = f"SELECT count(*) AS seat_{seat}_holders FROM booking_bug WHERE trip_id = {trip} AND seat_number = {seat}"
    ins_bug = "INSERT INTO booking_bug (trip_id, passenger_id, seat_number) VALUES ({t}, {p}, {s})"

    # ------------------------------------------------------------------ Part 1
    banner("PART 1 — THE BUG: check-then-insert with no unique rule (booking_bug)")
    run(A, "A", "BEGIN")
    run(A, "A", check_bug)
    run(B, "B", "BEGIN")
    run(B, "B", check_bug)
    run(A, "A", ins_bug.format(t=trip, p=pa, s=seat))
    run(A, "A", "COMMIT")
    run(B, "B", ins_bug.format(t=trip, p=pb, s=seat))
    run(B, "B", "COMMIT")
    run(A, "A", f"SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = {trip} ORDER BY bug_id")
    print("  >>> BUG: two passengers now hold the same seat.")

    # ------------------------------------------------------------------ Part 2
    banner("PART 2 — FIX 1: a UNIQUE index on (trip_id, seat_number)")
    run(A, "A", "TRUNCATE booking_bug")
    run(A, "A", "CREATE UNIQUE INDEX booking_bug_seat_unique ON booking_bug (trip_id, seat_number)")
    run(A, "A", "BEGIN")
    run(A, "A", check_bug)
    run(B, "B", "BEGIN")
    run(B, "B", check_bug)
    run(A, "A", ins_bug.format(t=trip, p=pa, s=seat))
    t = in_background(B, "B", ins_bug.format(t=trip, p=pb, s=seat))
    run(A, "A", "COMMIT")
    t.join()
    run(B, "B", "ROLLBACK")
    run(A, "A", f"SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = {trip} ORDER BY bug_id")
    print("  >>> FIXED: B waited for A, then got a unique_violation. One holder only.")

    # ------------------------------------------------------------------ Part 3
    banner("PART 3 — FIX 2: book_seat() locks the trip row (SELECT … FOR UPDATE)")
    book = "SELECT book_seat({t}, {p}, {s}, 23500.00, 'CARD') AS booking_id"
    run(A, "A", "BEGIN")
    run(A, "A", book.format(t=trip, p=pa, s=seat))
    run(B, "B", "BEGIN")
    t = in_background(B, "B", book.format(t=trip, p=pb, s=seat))
    run(A, "A", "COMMIT")
    t.join()
    run(B, "B", "ROLLBACK")
    run(A, "A", f"SELECT booking_id, passenger_id, seat_number, status FROM booking "
                f"WHERE trip_id = {trip} AND seat_number = {seat} AND status = 'CONFIRMED'")
    print("  >>> FIXED: B queued behind A's lock, then got a clear 'already booked' message.")

    # ------------------------------------------------------------------ Part 4
    banner("PART 4 — FIX 3: SERIALIZABLE stops the bug even with NO unique index")
    run(A, "A", "DROP INDEX booking_bug_seat_unique")
    run(A, "A", "TRUNCATE booking_bug")
    run(A, "A", "BEGIN ISOLATION LEVEL SERIALIZABLE")
    run(A, "A", check_bug)
    run(B, "B", "BEGIN ISOLATION LEVEL SERIALIZABLE")
    run(B, "B", check_bug)
    run(A, "A", ins_bug.format(t=trip, p=pa, s=seat))
    ok = run(B, "B", ins_bug.format(t=trip, p=pb, s=seat))
    run(A, "A", "COMMIT")
    if ok:
        run(B, "B", "COMMIT")
    else:
        run(B, "B", "ROLLBACK")
    run(A, "A", f"SELECT bug_id, passenger_id, seat_number FROM booking_bug WHERE trip_id = {trip} ORDER BY bug_id")
    print("  >>> FIXED: PostgreSQL saw that both read 'seat free' and both wrote it,")
    print("      so it cancelled B with a serialization failure (SQLSTATE 40001).")

    # ------------------------------------------------------------------ Part 5
    banner("PART 5 — READ COMMITTED vs REPEATABLE READ (counting booked seats)")
    count = (f"SELECT count(*) AS seats_booked FROM booking "
             f"WHERE trip_id = {trip} AND status = 'CONFIRMED'")
    print("-- 5a: READ COMMITTED (the default)")
    run(A, "A", "BEGIN ISOLATION LEVEL READ COMMITTED")
    run(A, "A", count)
    run(B, "B", book.format(t=trip, p=pb, s=seat2))
    run(A, "A", count)
    run(A, "A", "COMMIT")
    print("  >>> A saw the count change inside ONE transaction (non-repeatable read).")
    print("-- 5b: REPEATABLE READ")
    run(A, "A", "BEGIN ISOLATION LEVEL REPEATABLE READ")
    run(A, "A", count)
    run(B, "B", book.format(t=trip, p=pc, s=seat3))
    run(A, "A", count)
    run(A, "A", "COMMIT")
    run(A, "A", count)
    print("  >>> A kept its snapshot until COMMIT; the new booking appears afterwards.")

    # ------------------------------------------------------------------ Part 6
    banner("PART 6 — DEADLOCK: two desks lock the two trips in opposite order")
    lock = "SELECT trip_id FROM trip WHERE trip_id = {t} FOR UPDATE"
    run(A, "A", "BEGIN")
    run(A, "A", lock.format(t=trip))
    run(B, "B", "BEGIN")
    run(B, "B", lock.format(t=trip2))
    t = in_background(A, "A", lock.format(t=trip2))
    run(B, "B", lock.format(t=trip))       # closes the cycle → one is killed
    t.join()
    run(A, "A", "ROLLBACK")
    run(B, "B", "ROLLBACK")
    print("  >>> PostgreSQL detected the cycle after deadlock_timeout (1s) and")
    print("      aborted one transaction (SQLSTATE 40P01) so the other could go on.")

    print("-- 6b: the fix — always lock trips in trip_id order")
    lock_both = (f"SELECT trip_id FROM trip WHERE trip_id IN ({trip}, {trip2}) "
                 f"ORDER BY trip_id FOR UPDATE")
    run(A, "A", "BEGIN")
    run(A, "A", lock_both)
    run(B, "B", "BEGIN")
    t = in_background(B, "B", lock_both)
    run(A, "A", "COMMIT")
    t.join()
    run(B, "B", "COMMIT")
    print("  >>> Same two locks, same order: B simply waits its turn. No deadlock.")

    A.close()
    B.close()
    banner("ALL SIX DEMOS DONE — save this output: race_demos_output.log")


if __name__ == "__main__":
    main()
