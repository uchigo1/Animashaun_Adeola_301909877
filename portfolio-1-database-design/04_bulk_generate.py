#!/usr/bin/env python3
"""
RoadLink Express — MIT 8103 Portfolio 1
04_bulk_generate.py

Generates 50,000+ bookings spread over the last 2 years (relative to today)
PLUS the next 14 days of upcoming trips (partly booked, so P2/P3/P5 always
have real future seats to sell), with:
  * realistic Nigerian passenger names,
  * the real seeded routes/buses/drivers (loaded from 03_seed.sql),
  * Nigerian Naira (₦) fares scaled by date (December + Sallah + Easter get
    more trips AND a festive surcharge),
  * no seat sold twice on the same trip,
  * no bus on two overlapping trips (btree_gist EXCLUDE respected),
  * no driver on two overlapping trips (btree_gist EXCLUDE respected),
  * ~6% cancellations (with refund ≈ 85% of fare).

Connects through the Unix socket (host=/var/run/postgresql) — no password.

CONTRACT:
    This script ASSUMES 01_schema.sql + 03_seed.sql have already been run, so
    the terminal / route / bus / driver / passenger tables already contain
    the seed rows. It only inserts into trip / booking / payment / cancellation.

    It does NOT truncate those seed tables. To start fresh, re-run
    01_schema.sql + 03_seed.sql first.

Run:
    python3 04_bulk_generate.py
"""

from __future__ import annotations

import random
import sys
from datetime import date, datetime, timedelta, timezone
from typing import List, Tuple
from zoneinfo import ZoneInfo

import psycopg

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DB_NAME = "roadlink"
DB_USER = "roadlink"             # trust line in pg_hba.conf (no password)
DB_HOST = "/var/run/postgresql"  # Unix socket
DB_PORT = 5432

random.seed(8103)                # reproducible

LAGOS          = ZoneInfo("Africa/Lagos")             # departures are Lagos local time
NOW            = datetime.now(timezone.utc)
START_DATE     = date.today() - timedelta(days=730)   # 2 years back
END_DATE       = date.today() + timedelta(days=15)    # exclusive: includes the next 14 days
TARGET_BOOKINGS = 55_000                              # > 50k

# ---------------------------------------------------------------------------
# Realistic Nigerian names (large pool so duplicates are plausible)
# ---------------------------------------------------------------------------
FIRST_NAMES = [
    "Adebayo","Adeyemi","Aisha","Aminu","Babatunde","Bashir","Bisi","Bola",
    "Bukola","Blessing","Chioma","Chinedu","Chika","Daniel","Dorcas","Emeka",
    "Ekene","Fatima","Funke","Farida","Gbenga","Garba","Hauwa","Hassan",
    "Ibrahim","Idris","Joy","Joseph","Kunle","Khadija","Lami","Lola","Maryam",
    "Mohammed","Murtala","Ngozi","Nasir","Nonso","Oluwaseun","Olubunmi","Olaide",
    "Patience","Philip","Rabiat","Rita","Saheed","Samuel","Sani","Tunde","Titilayo",
    "Uche","Wale","Yakubu","Yusuf","Zainab","Adaeze","Tope","Adesola","Stephen",
    "Kemi","Sekinat","Nnamdi","Ifeanyi","Olumide","Clement","Halima","Usman",
    "Amaka","Obinna","Temitope","Folake","Abubakar","Hadiza","Chiamaka","Femi",
    "Ebuka","Nkechi","Segun","Hajara","Ahmed","Tolani","Ugochi","Musa","Esther",
]
LAST_NAMES = [
    "Adeola","Adeyemi","Adeyemo","Adesanya","Adekunle","Akinbiyi","Akinola",
    "Aliyu","Anozie","Audu","Bakare","Bankole","Bawa","Bello","Coker","Damaturu",
    "Edo","Effa","Eze","Ezeudu","Ibrahim","Idris","Lawal","Mohammed","Musa",
    "Nwankwo","Nwafor","Nwokocha","Nwosu","Obi","Obiefuna","Odufuwa","Ojo",
    "Okafor","Okon","Okonkwo","Oyelaran","Oke","Olaniyan","Onuoha","Osinbajo",
    "Sani","Solarin","Sule","Suleiman","Tella","Tijjani","Umar","Waziri","Yusuf",
    "Akpan","Adewale","Buba","Lawan","Anozie","Osinbajo","Obiefuna","Uchendu",
    "Ali","Hassan","Ezeudu","Effa","Adamu","Idris","Bawa","Audu","Damaturu",
    "Sule","Tijjani","Buba","Idris","Adamu","Bawa","Audu","Damaturu","Sule",
]
PHONE_PREFIX = ["0803", "0805", "0807", "0809", "0810", "0811", "0813",
                "0814", "0815", "0816", "0703", "0705", "0706", "0708",
                "0909", "0913", "0916"]


def random_phone() -> str:
    # international format drops the leading 0: 0803… → +234-803-…
    return f"+234-{random.choice(PHONE_PREFIX)[1:]}-{random.randint(100,999)}-{random.randint(1000,9999)}"


def random_name() -> str:
    return f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"


def random_email(name: str, salt: int) -> str:
    slug = name.lower().replace(" ", ".")
    return f"{slug}.{salt}@example.com"


# ---------------------------------------------------------------------------
# Festive multipliers (Nigerian public-traffic peaks)
# ---------------------------------------------------------------------------
# Sallah (Eid al-Fitr & Eid al-Adha) and Easter move every year. We treat
# "month == December" as the most reliable fixed peak, plus a sliding 14-day
# window around each year's Sallah estimates, plus the Easter long weekend.
SALLAH_WINDOWS = {     # year: (eid_al_fitr_start, eid_al_adha_start) approx
    2024: (date(2024, 4, 10), date(2024, 6, 16)),
    2025: (date(2025, 3, 31), date(2025, 6,  7)),
    2026: (date(2026, 3, 20), date(2026, 5, 27)),
    2027: (date(2027, 3, 10), date(2027, 5, 17)),
}
EASTER_SUNDAY = {
    2024: date(2024, 3, 31),
    2025: date(2025, 4, 20),
    2026: date(2026, 4,  5),
    2027: date(2027, 3, 28),
}


def trips_for_day(d: date) -> int:
    """How many departures to schedule on this day."""
    base = 4
    if d.month == 12:
        base = 18                # December festive rush
    for y in (d.year - 1, d.year, d.year + 1):
        if y in SALLAH_WINDOWS:
            for s_start in SALLAH_WINDOWS[y]:
                if 0 <= (d - s_start).days <= 14:
                    base = max(base, 14)
    for y, e in EASTER_SUNDAY.items():
        if (e - timedelta(days=2)) <= d <= (e + timedelta(days=1)):
            base = max(base, 12)
    if d.weekday() in (4, 5):    # Fri, Sat — slightly more traffic
        base += 2
    return base


def fare_multiplier(d: date) -> float:
    if d.month == 12:
        return 1.20
    for y in (d.year - 1, d.year, d.year + 1):
        if y in SALLAH_WINDOWS:
            for s_start in SALLAH_WINDOWS[y]:
                if 0 <= (d - s_start).days <= 14:
                    return 1.15
    for y, e in EASTER_SUNDAY.items():
        if (e - timedelta(days=2)) <= d <= (e + timedelta(days=1)):
            return 1.10
    return 1.00


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    print(f"[bulk] target = {TARGET_BOOKINGS} bookings")
    print(f"[bulk] window = {START_DATE} → {END_DATE}")

    conn = psycopg.connect(
        dbname=DB_NAME, user=DB_USER, host=DB_HOST, port=DB_PORT
    )
    conn.autocommit = False
    cur = conn.cursor()

    # ---- 0) load reference data -------------------------------------------
    cur.execute("SELECT route_id, distance_km, base_fare_ngn FROM route")
    routes: List[Tuple[int, float, float]] = cur.fetchall()
    if not routes:
        print("[bulk] FATAL: no routes in DB. Run 03_seed.sql first.")
        return 1

    cur.execute("SELECT bus_id, seat_capacity FROM bus ORDER BY bus_id")
    buses: List[Tuple[int, int]] = cur.fetchall()
    if not buses:
        print("[bulk] FATAL: no buses in DB.")
        return 1

    cur.execute("SELECT driver_id FROM driver ORDER BY driver_id")
    drivers: List[int] = [r[0] for r in cur.fetchall()]
    if not drivers:
        print("[bulk] FATAL: no drivers in DB.")
        return 1

    print(f"[bulk] {len(routes)} routes, {len(buses)} buses, {len(drivers)} drivers")

    # ---- 1) ensure ~10k passengers exist (extend if seed has fewer) -------
    cur.execute("SELECT COUNT(*) FROM passenger")
    n_existing_passengers = cur.fetchone()[0]
    n_to_add = max(0, 10_000 - n_existing_passengers)
    if n_to_add:
        print(f"[bulk] adding {n_to_add} passengers (have {n_existing_passengers})")
        new_passengers = []
        for i in range(n_to_add):
            nm = random_name()
            new_passengers.append((nm, random_phone(), random_email(nm, n_existing_passengers + i + 1)))
        cur.executemany(
            "INSERT INTO passenger (full_name, phone, email) VALUES (%s,%s,%s)",
            new_passengers,
        )
    cur.execute("SELECT passenger_id FROM passenger")
    passenger_ids: List[int] = [r[0] for r in cur.fetchall()]
    print(f"[bulk] {len(passenger_ids)} passengers available")

    # ---- 2) clear old trip/booking/payment/cancellation rows --------------
    # (we keep dims: terminal/route/bus/driver/passenger)
    cur.execute("TRUNCATE cancellation, payment, booking, trip RESTART IDENTITY CASCADE")

    # ---- 3) build trips across the 2-year window --------------------------
    # Maintain Python-side "busy" lists so we never even propose a trip that
    # would violate the EXCLUDE(bus) or EXCLUDE(driver) constraints.
    bus_busy:    dict[int, List[Tuple[datetime, datetime]]] = {b[0]: [] for b in buses}
    driver_busy: dict[int, List[Tuple[datetime, datetime]]] = {d: [] for d in drivers}

    def free_in(busy_list, s, e):
        for (bs, be) in busy_list:
            if s < be and bs < e:
                return False
        return True

    DEPART_HOURS = [6, 8, 10, 12, 14, 16, 18, 20, 22]
    trip_rows = []          # (route_id, bus_id, driver_id, depart_at, arrive_at)

    d = START_DATE
    while d < END_DATE:
        for _ in range(trips_for_day(d)):
            route_id, dist_km, base_fare = random.choice(routes)
            hour = random.choice(DEPART_HOURS)
            depart = datetime(d.year, d.month, d.day, hour, 0, tzinfo=LAGOS) + timedelta(
                minutes=random.choice([0, 15, 30, 45])
            )
            arrive = depart + timedelta(hours=float(dist_km) / 60.0)

            free_buses = [b for b in buses if free_in(bus_busy[b[0]], depart, arrive)]
            if not free_buses:
                continue
            bus_id, seat_cap = random.choice(free_buses)
            free_drivers = [dr for dr in drivers if free_in(driver_busy[dr], depart, arrive)]
            if not free_drivers:
                continue
            driver_id = random.choice(free_drivers)

            trip_rows.append((route_id, bus_id, driver_id, depart, arrive))
            bus_busy[bus_id].append((depart, arrive))
            driver_busy[driver_id].append((depart, arrive))
        d += timedelta(days=1)

    print(f"[bulk] prepared {len(trip_rows)} candidate trips")

    # ---- 4) bulk COPY trips ------------------------------------------------
    with cur.copy("COPY trip (route_id, bus_id, driver_id, depart_at, arrive_at) FROM STDIN") as cp:
        for row in trip_rows:
            cp.write_row(row)

    cur.execute("SELECT trip_id, depart_at, bus_id, seat_capacity, base_fare_ngn "
                "FROM trip JOIN bus b USING(bus_id) JOIN route r USING(route_id) "
                "ORDER BY trip_id")
    inserted_trips = cur.fetchall()
    if len(inserted_trips) != len(trip_rows):
        print(f"[bulk] WARN: only {len(inserted_trips)} trips inserted "
              f"(expected {len(trip_rows)}). Some proposed trips were rejected "
              "by constraints — this is OK.")
    print(f"[bulk] inserted {len(inserted_trips)} trips into DB")

    # ---- 5) generate bookings per trip ------------------------------------
    # Past trips: 70-95% full. Upcoming trips: the further away, the emptier
    # (tomorrow ~60-85%, two weeks out ~10-30%), so there are free seats.
    # Every booking gets its OWN booked_at (0-14 days before departure, never
    # in the future), and cancellations happen before departure.
    booking_rows = []       # (trip_id, passenger_id, seat, booked_at, status)
    payment_rows = []       # parallel: (amount, channel, paid_at, status)
    cancel_info  = []       # parallel: None or (cancelled_at, refund)

    for trip_id, depart_dt, bus_id, seat_cap, base_fare in inserted_trips:
        if depart_dt <= NOW:
            lo, hi = 0.70, 0.95
        else:
            days_ahead = (depart_dt - NOW).total_seconds() / 86400
            hi = max(0.30, 0.85 - 0.04 * days_ahead)
            lo = max(0.10, hi - 0.25)
        load = random.randint(int(seat_cap * lo), int(seat_cap * hi))
        load = max(1, min(load, seat_cap))
        seats = random.sample(range(1, seat_cap + 1), load)
        trip_passengers = random.sample(passenger_ids, load)
        f = round(float(base_fare) * fare_multiplier(depart_dt.astimezone(LAGOS).date()), 2)
        latest = min(depart_dt - timedelta(minutes=30), NOW - timedelta(minutes=5))
        earliest = depart_dt - timedelta(days=14)
        span = max(60, int((latest - earliest).total_seconds()))
        for seat, pid in zip(seats, trip_passengers):
            booked_at = earliest + timedelta(seconds=random.randint(0, span))
            if booked_at > latest:
                booked_at = latest
            paid_at = booked_at + timedelta(seconds=random.randint(5, 240))
            cxl = None
            status, pay_status = "CONFIRMED", "SUCCESS"
            if random.random() < 0.06:
                cxl_latest = min(depart_dt - timedelta(hours=1), NOW - timedelta(minutes=1))
                if cxl_latest > paid_at + timedelta(minutes=10):
                    gap = int((cxl_latest - paid_at).total_seconds())
                    cancelled_at = paid_at + timedelta(seconds=random.randint(600, gap))
                    cxl = (cancelled_at, round(f * 0.85, 2))
                    status, pay_status = "CANCELLED", "REFUNDED"
            booking_rows.append((trip_id, pid, seat, booked_at, status))
            payment_rows.append((f, random.choice(["CARD", "BANK_TRANSFER", "USSD", "WALLET", "CARD", "BANK_TRANSFER"]),
                                 paid_at, pay_status))
            cancel_info.append(cxl)

    print(f"[bulk] prepared {len(booking_rows)} booking rows")

    # ---- 6) bulk COPY bookings ---------------------------------------------
    with cur.copy("COPY booking (trip_id, passenger_id, seat_number, booked_at, status) FROM STDIN") as cp:
        for row in booking_rows:
            cp.write_row(row)

    # booking_id is an identity that restarted at 1, so ids follow COPY order
    cur.execute("SELECT booking_id FROM booking ORDER BY booking_id")
    booking_ids = [r[0] for r in cur.fetchall()]
    if len(booking_ids) != len(booking_rows):
        print("[bulk] FATAL: booking count mismatch")
        return 1
    print(f"[bulk] inserted {len(booking_ids)} bookings")

    # ---- 7) bulk COPY payments --------------------------------------------
    with cur.copy("COPY payment (booking_id, amount_ngn, channel, paid_at, status) FROM STDIN") as cp:
        for bid, (amt, chan, paid_at, status) in zip(booking_ids, payment_rows):
            cp.write_row((bid, amt, chan, paid_at, status))

    # ---- 8) bulk COPY cancellations (~6%, refund = 85% of fare) -----------
    reasons = ["Change of plans", "Trip postponed", "Family emergency",
               "Booked wrong date", "Travelling by air instead", "Work schedule changed"]
    with cur.copy("COPY cancellation (booking_id, cancelled_at, reason, refund_ngn) FROM STDIN") as cp:
        for bid, cxl in zip(booking_ids, cancel_info):
            if cxl:
                cp.write_row((bid, cxl[0], random.choice(reasons), cxl[1]))

    conn.commit()

    # ---- 9) sanity printout ----------------------------------------------
    cur.execute("SELECT COUNT(*) FROM trip");        n_trips = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM booking");     n_bk    = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM payment");     n_pay   = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM cancellation"); n_cxl  = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM passenger");   n_ps   = cur.fetchone()[0]
    cur.execute(
        "SELECT to_char(t.depart_at,'YYYY-MM') AS ym, COUNT(b.booking_id) AS bk "
        "FROM trip t LEFT JOIN booking b USING(trip_id) "
        "WHERE t.depart_at <= now() GROUP BY ym ORDER BY ym DESC LIMIT 6"
    )
    top_months = cur.fetchall()
    cur.execute(
        "SELECT to_char(t.depart_at,'YYYY-MM') AS ym, COUNT(b.booking_id) AS bk "
        "FROM trip t LEFT JOIN booking b USING(trip_id) "
        "WHERE EXTRACT(MONTH FROM t.depart_at) = 12 "
        "GROUP BY ym ORDER BY ym"
    )
    dec_months = cur.fetchall()
    cur.execute("SELECT COUNT(*), COALESCE(SUM(c.seat_capacity - c.seats_booked),0) "
                "FROM (SELECT t.trip_id, b.seat_capacity, COUNT(bk.booking_id) AS seats_booked "
                "      FROM trip t JOIN bus b USING (bus_id) "
                "      LEFT JOIN booking bk ON bk.trip_id = t.trip_id AND bk.status='CONFIRMED' "
                "      WHERE t.depart_at > now() GROUP BY t.trip_id, b.seat_capacity) c")
    n_up, free_up = cur.fetchone()
    cur.close()
    conn.close()

    print()
    print("=" * 60)
    print(f"  trips         : {n_trips:>8}")
    print(f"  bookings      : {n_bk:>8}")
    print(f"  payments      : {n_pay:>8}")
    print(f"  cancellations : {n_cxl:>8}")
    print(f"  passengers    : {n_ps:>8}")
    print(f"  upcoming trips (next 14 days): {n_up}  with {free_up} free seats")
    print("  busiest 6 months (most recent):")
    for ym, c in top_months:
        print(f"    {ym} : {c} bookings")
    print("  December months (festive-rush check):")
    for ym, c in dec_months:
        print(f"    {ym} : {c} bookings")
    print("=" * 60)
    if n_bk < TARGET_BOOKINGS:
        print(f"[bulk] WARN: generated {n_bk} bookings (target {TARGET_BOOKINGS}). "
              "Increase TARGET_BOOKINGS or expand the date window if needed.")
        return 2
    print("[bulk] DONE — all integrity constraints (UNIQUE trip+seat, "
          "EXCLUDE bus/driver overlap, seat capacity trigger) held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
