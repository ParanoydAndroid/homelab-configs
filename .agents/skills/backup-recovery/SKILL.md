---
name: backup-recovery
description: >-
  Procedural runbook for executing persistent volume backups, online database staging,
  snapshot inspection, and full or granular service disaster recovery via manage.sh.
  Use when backing up containers, verifying restic snapshots, or executing restore operations.
---

# Backup and Disaster Recovery Runbook

This skill provides step-by-step procedures for managing Restic volume snapshots, executing zero-downtime backups, and performing disaster recovery.

## Prerequisites
- Reference [Disaster Recovery and Volume Restoration Reference](./references/restore-runbook.md) for architecture and snapshot pruning details.
- Root or sudo privileges required for backup and restore executions (`sudo ./manage.sh ...`).

---

## Operations

### Operation 1: Execute Zero-Downtime Volume Backup
Runs online database dumps (PostgreSQL `pg_dumpall`), snapshots `/volume2/docker`, archives `.env` secrets, commits git state, and tags the commit:

```bash
sudo ./manage.sh backup
```

#### Custom Tagging and Commit Messages:
- **CalVer Snapshot** (default):
  ```bash
  sudo ./manage.sh backup -t calver -m "chore(backup): scheduled volume snapshot"
  ```
- **SemVer Minor Milestone**:
  ```bash
  sudo ./manage.sh backup -t minor -m "feat(storage): upgraded storage configuration"
  ```
- **Custom Named Snapshot**:
  ```bash
  sudo ./manage.sh backup -t pre-upgrade -m "chore: snapshot prior to major upgrade"
  ```

---

### Operation 2: Inspect Snapshots
List all historical Restic snapshots with timestamps, snapshot IDs, and paths:

```bash
./manage.sh snapshots
```

---

### Operation 3: Perform Disaster Recovery (Restore)

#### 1. Dry-Run Verification (Always recommended):
```bash
sudo ./manage.sh restore latest --dry-run
```

#### 2. Granular Service Restore (Zero disruption to other stacks):
Restore only a specific service data volume:
```bash
sudo ./manage.sh restore latest <service_name>
```
*Example*: `sudo ./manage.sh restore latest mealie`

#### 3. Full Environment Disaster Recovery:
Restore all container data volumes across `${DOCKER_DATA_DIR}`:
```bash
sudo ./manage.sh restore latest
```
*Note: Full restore creates an emergency safety snapshot, stops all running containers, restores volume directories, repairs ownership (`1000:100`), imports PostgreSQL staging dumps, and brings all stacks back up.*
