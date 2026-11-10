#!/usr/bin/env bash
# =============================================================================
# RoadLink Express — MIT 8103 Portfolio 5
# 02_setup_replica.sh — set up a streaming read replica on the same Codespace
# =============================================================================
# We cannot run TWO postgres clusters on the same port on one Codespace,
# so we run the replica on port 5433 with its own data directory. The
# PRIMARY is the existing cluster on port 5432 (data dir
# /var/lib/postgresql/16/main).
#
# Codespaces rules respected:
#   * sudo used as root, drop to postgres user with `sudo runuser -u postgres -- …`
#   * PostgreSQL 16 config in /etc/postgresql/16/main/
#   * pg_ctl is at /usr/lib/postgresql/16/bin/pg_ctl
#   * A replica made with pg_basebackup needs its own postgresql.conf,
#     pg_hba.conf and pg_ident.conf (Ubuntu keeps them in /etc, outside the
#     data directory, so pg_basebackup does not copy them)
#   * pg_hba.conf trust lines are added at the TOP of the file
#   * No TCP password needed (we connect through Unix socket or localhost
#     with trust for the local replica)
#   * We never use postgres_fdw
#
# Run:
#   bash 02_setup_replica.sh
# =============================================================================

set -euo pipefail

PG_BIN=/usr/lib/postgresql/16/bin
PG_PRIMARY_DATA=/var/lib/postgresql/16/main
PG_REPLICA_DATA=/var/lib/postgresql/16/replica
PG_REPLICA_PORT=5433
REPL_USER=roadlink_repl
REPL_PASS=roadlink_repl_pwd

echo "================================================================"
echo "  P5 — Streaming replica setup"
echo "================================================================"

# 1. Create a replication role on the primary (idempotent)
echo "[1/8] creating replication role ${REPL_USER} on the primary …"
sudo runuser -u postgres -- psql -d roadlink -v ON_ERROR_STOP=0 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} LOGIN REPLICATION PASSWORD '${REPL_PASS}';
  END IF;
END
\$\$;
SQL

# 2. Allow replication connections from localhost at the TOP of pg_hba.conf
# (Trust for 127.0.0.1 because the codespace sandbox has no network exposure
# and we want pg_basebackup to work without prompting for a password.)
HBA=/etc/postgresql/16/main/pg_hba.conf
if ! sudo grep -q "^host.*replication.*${REPL_USER}" "$HBA"; then
  echo "[2/8] prepending replication trust line to TOP of pg_hba.conf …"
  sudo cp "$HBA" "${HBA}.bak.$(date +%s)"
  # sed -i '1i' inserts at line 1 in place. (The old version piped
  # `cat "$HBA"` into `sudo tee "$HBA"`: cat runs WITHOUT sudo and cannot read
  # pg_hba.conf, so tee emptied the file down to these two lines.)
  sudo sed -i "1i host    replication    ${REPL_USER}    ::1/128         trust" "$HBA"
  sudo sed -i "1i host    replication    ${REPL_USER}    127.0.0.1/32    trust" "$HBA"
fi

# 3. Enable WAL level = replica + max_wal_senders on the primary
echo "[3/8] setting wal_level=replica + max_wal_senders=10 on the primary …"
sudo sed -i "s/^#\?wal_level.*/wal_level = replica/" /etc/postgresql/16/main/postgresql.conf
sudo sed -i "s/^#\?max_wal_senders.*/max_wal_senders = 10/" /etc/postgresql/16/main/postgresql.conf
sudo sed -i "s/^#\?max_replication_slots.*/max_replication_slots = 10/" /etc/postgresql/16/main/postgresql.conf
sudo sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" /etc/postgresql/16/main/postgresql.conf
sudo pg_ctlcluster 16 main restart

# 4. Stop the replica if it is already running, drop its old replication
#    slot, wipe its data dir, and run pg_basebackup from the primary.
echo "[4/8] stopping any old replica + cleaning ${PG_REPLICA_DATA} …"
if sudo test -f "${PG_REPLICA_DATA}/postmaster.pid"; then
  sudo runuser -u postgres -- ${PG_BIN}/pg_ctl -D "${PG_REPLICA_DATA}" -m fast stop || true
fi
sudo runuser -u postgres -- psql -d roadlink -X -q -c \
  "SELECT pg_drop_replication_slot('replica_slot') FROM pg_replication_slots WHERE slot_name = 'replica_slot';" > /dev/null
sudo rm -rf "${PG_REPLICA_DATA}"
sudo install -d -o postgres -g postgres -m 700 "${PG_REPLICA_DATA}"

echo "[5/8] running pg_basebackup (creates a block-level copy of the primary) …"
# -R writes standby.signal + primary_conninfo; -C -S creates a replication slot
# so the primary keeps the WAL the replica still needs. (The old version also
# passed -T with no value, which is the tablespace-mapping option and made
# pg_basebackup fail.)
sudo runuser -u postgres -- env PGPASSWORD="${REPL_PASS}" ${PG_BIN}/pg_basebackup \
    -h 127.0.0.1 -p 5432 -U "${REPL_USER}" -D "${PG_REPLICA_DATA}" \
    -X stream -C -S replica_slot -R --progress

# 5. Ubuntu keeps postgresql.conf / pg_hba.conf / pg_ident.conf in
#    /etc/postgresql/16/main, NOT in the data directory — so pg_basebackup
#    did not copy them. The replica needs its own copies.
echo "[6/8] writing the replica's own postgresql.conf, pg_hba.conf, pg_ident.conf (port ${PG_REPLICA_PORT}) …"
sudo cp /etc/postgresql/16/main/pg_hba.conf   "${PG_REPLICA_DATA}/pg_hba.conf"
sudo cp /etc/postgresql/16/main/pg_ident.conf "${PG_REPLICA_DATA}/pg_ident.conf"
sudo tee "${PG_REPLICA_DATA}/postgresql.conf" > /dev/null <<CONF
# --- replica configuration (written by 02_setup_replica.sh) ---
port = ${PG_REPLICA_PORT}
listen_addresses = 'localhost'
unix_socket_directories = '/var/run/postgresql'
hot_standby = on                 # allow read-only queries on the replica
hot_standby_feedback = on
# (max_connections etc. are left at the defaults: a standby must not be
#  set LOWER than the primary, or recovery refuses to start)
timezone = 'Africa/Lagos'
log_timezone = 'Africa/Lagos'
CONF
# trust for local socket logins on the replica (lines go at the TOP)
REPL_HBA="${PG_REPLICA_DATA}/pg_hba.conf"
sudo sed -i '1i local   all             all                                     trust' "$REPL_HBA"
sudo chown postgres:postgres "${PG_REPLICA_DATA}/postgresql.conf" "${PG_REPLICA_DATA}/pg_hba.conf" "${PG_REPLICA_DATA}/pg_ident.conf"
sudo chmod 700 "${PG_REPLICA_DATA}"

# 6. Start the replica cluster with pg_ctl (NOT pg_ctlcluster, which only
#    manages the registered 16/main cluster).
echo "[7/8] starting the replica with pg_ctl …"
sudo rm -f /tmp/replica.log
sudo runuser -u postgres -- ${PG_BIN}/pg_ctl \
    -D "${PG_REPLICA_DATA}" -l /tmp/replica.log -w start || { sudo tail -20 /tmp/replica.log; exit 1; }

# 7. Wait for the replica to come up + report its state
echo "[8/8] waiting for the replica to come up …"
for i in $(seq 1 30); do
  if sudo runuser -u postgres -- psql -p ${PG_REPLICA_PORT} -d roadlink \
        -t -A -c "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q '^t'; then
    echo "  replica is up and in recovery mode (read-only)"
    break
  fi
  sleep 1
done

echo
echo "  PRIMARY   : port 5432  (${PG_PRIMARY_DATA})"
echo "  REPLICA   : port ${PG_REPLICA_PORT}  (${PG_REPLICA_DATA})"
echo
echo "  Status:"
sudo runuser -u postgres -- psql -p 5432 -d roadlink -c \
  "SELECT application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn
   FROM pg_stat_replication;"

echo
echo "  Replica recovery status:"
sudo runuser -u postgres -- psql -p ${PG_REPLICA_PORT} -d roadlink -c \
  "SELECT pg_is_in_recovery() AS in_recovery, pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn;"

echo
echo "================================================================"
echo "  P5 — Streaming replica is up on port ${PG_REPLICA_PORT}."
echo "  Next: 03_replica_tests.sql proves write-rejection + replication."
echo "================================================================"
