#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio
# setup.sh — Provision PostgreSQL 16 + MongoDB 8 inside a GitHub Codespace
# =============================================================================
# Student : Animashaun Adeola
# Matric  : 2026/A/MIT/0432
# Course  : MIT 8103 — Advanced Database Systems (Miva Open University)
#
# This script is idempotent — it is safe to re-run.
# Codespaces rules respected:
#   * sudo is used as root, then we drop to the postgres user with:
#         sudo runuser -u postgres -- <cmd>
#     (never `sudo -u postgres`, which breaks under Codespaces' PAM config)
#   * /etc/apt/sources.list.d/yarn.list is removed BEFORE apt-get update
#     (the yarn list ships a malformed repo that 404s and aborts apt)
#   * PostgreSQL 16 config lives in /etc/postgresql/16/main/
#   * pg_ctl is at /usr/lib/postgresql/16/bin/pg_ctl
#   * TCP login needs a password; we connect through the Unix socket at
#     /var/run/postgresql so no PGPASSWORD is required.
# =============================================================================

set -euo pipefail

echo "================================================================"
echo "  RoadLink Express — portfolio setup (PostgreSQL 16 + MongoDB 8)"
echo "================================================================"

# ---------------------------------------------------------------------------
# 0. Codespaces hygiene — remove the broken yarn source list if present
# ---------------------------------------------------------------------------
if [ -f /etc/apt/sources.list.d/yarn.list ]; then
  echo "[setup] removing /etc/apt/sources.list.d/yarn.list (breaks apt-get update)"
  sudo rm -f /etc/apt/sources.list.d/yarn.list
fi

# ---------------------------------------------------------------------------
# 1. Install PostgreSQL 16 + MongoDB 8 + helper tools
# ---------------------------------------------------------------------------
echo "[setup] apt-get update"
sudo apt-get update -qq

echo "[setup] installing PostgreSQL 16 (postgresql-16 + contrib + btree_gist)"
sudo apt-get install -y -qq \
  postgresql-16 \
  postgresql-contrib \
  libpq-dev \
  > /dev/null
# (btree_gist and pgcrypto ship inside postgresql-16 — nothing else needed)

echo "[setup] installing MongoDB 8.0 (mongodb-org) — official repo"
# Install gnupg + curl for the MongoDB signing key
sudo apt-get install -y -qq gnupg curl ca-certificates > /dev/null

if [ ! -f /usr/bin/mongod ]; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
    | sudo gpg --yes -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  . /etc/os-release   # VERSION_CODENAME = this Ubuntu release (noble, jammy …)
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${VERSION_CODENAME}/mongodb-org/8.0 multiverse" \
    | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq mongodb-org > /dev/null
fi

echo "[setup] installing the Python driver (psycopg 3) used by the P1 generator and P3 demos"
python3 -m pip install --user --quiet "psycopg[binary]" pymongo 2>/dev/null \
  || python3 -m pip install --user --quiet --break-system-packages "psycopg[binary]" pymongo
python3 -c "import psycopg; print('[setup] psycopg', psycopg.__version__, 'OK')"

# ---------------------------------------------------------------------------
# 2. Start PostgreSQL 16 — Codespaces does not auto-start it
# ---------------------------------------------------------------------------
echo "[setup] starting PostgreSQL 16 cluster"
sudo pg_ctlcluster 16 main start 2>/dev/null || true
# Make sure it's accepting local socket connections
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/main -l /tmp/pg16.log status 2>/dev/null || \
  sudo pg_ctlcluster 16 main start

# Create the application role + database for the portfolio
echo "[setup] creating PostgreSQL role 'roadlink' + database 'roadlink'"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'roadlink') THEN
    CREATE ROLE roadlink LOGIN PASSWORD 'roadlink';
  END IF;
END$$;

SELECT 'CREATE DATABASE roadlink OWNER roadlink'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'roadlink')\gexec
-- show every date/time in Lagos time (WAT, UTC+1)
ALTER DATABASE roadlink SET timezone TO 'Africa/Lagos';
SQL

# Trust roadlink on the local socket so scripts don't need a password.
# IMPORTANT: pg_hba.conf lines are ORDER SENSITIVE — the trust line must go
# at the TOP of the file (before any `host all all 127.0.0.1/32 md5`).
echo "[setup] adding trust line at TOP of pg_hba.conf for local socket"
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo grep -q "^local.*roadlink.*roadlink.*trust" "$HBA"; then
  sudo cp "$HBA" "${HBA}.bak.$(date +%s)"
  # sed -i '1i …' puts the line at the very top, before Ubuntu's own rules
  sudo sed -i '1i local   roadlink       roadlink                           trust' "$HBA"
fi

sudo pg_ctlcluster 16 main reload

# ---------------------------------------------------------------------------
# 3. Start MongoDB 8 (mongod) — no auth, localhost only, default port 27017
# ---------------------------------------------------------------------------
echo "[setup] starting MongoDB 8 (mongod) on 127.0.0.1:27017"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true

# Start mongod in the background (--fork) unless it is already running
if ! pgrep -x mongod > /dev/null; then
  sudo mongod \
    --dbpath /data/db \
    --logpath /var/log/mongodb/mongod.log --logappend \
    --bind_ip 127.0.0.1 \
    --port 27017 \
    --fork > /dev/null
fi

# Wait for mongod to come up
for i in $(seq 1 30); do
  if mongosh --quiet --eval "db.runCommand({ping:1}).ok" 2>/dev/null | grep -q 1; then
    echo "[setup] MongoDB is up (pid $(pgrep -x mongod | head -1))"
    break
  fi
  sleep 1
done

# ---------------------------------------------------------------------------
# 4. Smoke-test both stacks
# ---------------------------------------------------------------------------
echo "[setup] smoke test: PostgreSQL"
sudo runuser -u postgres -- psql -d roadlink -c "SELECT version();" | head -3
echo
echo "[setup] smoke test: MongoDB"
mongosh --quiet --eval "db.version()"
echo

echo "================================================================"
echo "  setup.sh DONE"
echo "  PostgreSQL 16 : unix socket /var/run/postgresql  db=roadlink"
echo "  MongoDB 8     : 127.0.0.1:27017"
echo "  Next: cd into a portfolio folder and run ./run_pN.sh"
echo "================================================================"
