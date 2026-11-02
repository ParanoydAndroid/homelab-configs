---
name: disaster-recovery-drill
description: >-
  Operational runbook for conducting zero-downtime disaster recovery drills. Restores
  Restic persistent volume snapshots into an isolated sandbox staging directory,
  verifies logical database dump integrity (PostgreSQL and SQLite PRAGMA checks),
  and tests configuration recovery without impacting active production services.
---

# Disaster Recovery Drill Runbook (Sandbox Verification)

An unverified backup is an untested liability. This skill provides an automated procedure for running periodic disaster recovery drills in an isolated sandbox directory (`/tmp/dr-drill`) to verify Restic snapshot integrity, logical database dump validity, and configuration completeness.

---

## Safety Guarantees
- **Zero Production Impact**: Active containers in `/volume2/docker` are never stopped or touched.
- **Isolated Target Directory**: Snapshots are restored strictly into `/tmp/dr-drill`.
- **Automatic Sandbox Teardown**: Temporary files are unlinked and cleaned up after drill completion.

---

## Execution Procedure

### Step 1: Prepare Sandbox Staging Environment
```bash
DRILL_DIR="/tmp/dr-drill-$(date +%Y%m%d%H%M%S)"
mkdir -p "${DRILL_DIR}"
```

### Step 2: Query Latest Snapshot ID
Query available snapshots in the Restic repository:
```bash
SNAPSHOT_ID="$(sudo restic -r "${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}" --insecure-no-password snapshots --latest 1 --json | grep -oE '"short_id":"[a-f0-9]+"' | head -n1 | cut -d'"' -f4)"
echo "Testing Snapshot: ${SNAPSHOT_ID}"
```

### Step 3: Granular Restore into Sandbox
Restore a representative database-backed service (e.g. `postgres`, `jellyfin`, or `tandoor`):
```bash
sudo restic -r "${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}" --insecure-no-password \
  restore "${SNAPSHOT_ID}" \
  --target "${DRILL_DIR}" \
  --include "/volume2/docker/.backups" \
  --include "/volume2/docker/postgres"
```

### Step 4: Verify Logical Database Dump Integrity

#### 1. PostgreSQL Global Dump Integrity
Verify the staged plain-text SQL logical dump exists and is parseable:
```bash
PG_DUMP="${DRILL_DIR}/volume2/docker/.backups/postgres_globals.sql"
if [[ -f "${PG_DUMP}" ]]; then
  echo "PostgreSQL dump size: $(du -h "${PG_DUMP}" | cut -f1)"
  grep -q "PostgreSQL database cluster dump" "${PG_DUMP}" && echo "PostgreSQL header: VALID"
else
  echo "WARNING: PostgreSQL logical dump not found in snapshot"
fi
```

#### 2. SQLite Database Integrity Probes
Verify that application databases staged with `.backup` have zero corruption:
```bash
for db in $(find "${DRILL_DIR}" -name "*.db" -o -name "*.sqlite"); do
  integrity="$(sqlite3 "${db}" "PRAGMA integrity_check;" 2>/dev/null || echo "failed")"
  echo "Checking ${db}: ${integrity}"
  if [[ "${integrity}" != "ok" ]]; then
    echo "CORRUPTION DETECTED in ${db}!"
  fi
done
```

### Step 5: Verify Environment & Secret Bundle Restoration
Verify that the encrypted/archived `.env` bundle can be unpacked:
```bash
ENV_BUNDLE="${DRILL_DIR}/volume2/docker/.backups/env_bundle.tar.gz"
if [[ -f "${ENV_BUNDLE}" ]]; then
  tar -tzf "${ENV_BUNDLE}" && echo "Environment bundle archive: VALID"
fi
```

### Step 6: Teardown & Drill Report
Clean up the temporary drill directory:
```bash
sudo rm -rf "${DRILL_DIR}"
```

Compile and present the Drill Report:
- **Snapshot Tested**: Short ID and timestamp.
- **Files Restored**: Total count and byte size.
- **Database Status**: PostgreSQL cluster dump valid, SQLite integrity OK.
- **Secret Bundle Status**: Valid archive.
