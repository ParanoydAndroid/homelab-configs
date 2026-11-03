# Disaster Recovery and Volume Restoration Reference

## Architecture Overview

Homelab persistent state is stored across two primary volumes on the UGREEN NAS:
1. **Container Volumes**: `${DOCKER_DATA_DIR}` (`/volume2/docker`)
   - Houses configurations, databases, and application runtime state.
2. **Restic Snapshot Repository**: `${BACKUP_RESTIC_REPO}` (`/volume1/backups/homelab-docker`)
   - Encrypted, deduplicated snapshots stored on primary RAID storage.

Backups are executed with zero downtime using online database staging. Restorations can be performed at full volume granularity or per-service.

---

## Detailed Restoration Procedures

### 1. Identify Target Snapshot
List available snapshots sorted by timestamp and tagged metadata:
```bash
./homelab.sh snapshots
```
Identify the desired snapshot ID (e.g. `a1b2c3d4` or `latest`).

### 2. Full Docker Volume Disaster Recovery
To restore all container volumes from `latest` or a specific snapshot:

```bash
# Dry-run inspection
sudo ./homelab.sh restore latest --dry-run

# Execute full restore
sudo ./homelab.sh restore latest
```

**Restoration Sequence Executed by `homelab.sh restore`**:
1. Stops all running container stacks to prevent file lock corruption.
2. Creates an emergency pre-restore safety snapshot of `/volume2/docker`.
3. Streams the target Restic snapshot into `/volume2/docker`.
4. Fixes filesystem ownership to `1000:100` for standard service volumes (preserving UID 70 for PostgreSQL).
5. Restores PostgreSQL database dumps from the staged SQL files.
6. Restarts container stacks in dependency order.

### 3. Granular Single-Service Recovery
To restore only a specific service (e.g. `tandoor` or `recipes`) without disrupting other services:

```bash
sudo ./homelab.sh restore latest tandoor
```

**Behavior**:
- Only the `<service>` volume inside `/volume2/docker/<service>` is restored.
- The single target stack is stopped and restarted.
- Remaining stacks continue running uninterrupted.

---

## Online Database Staging Mechanics

To avoid stopping containers during regular backups, `backup.sh` uses online logical dumps:
1. **PostgreSQL**:
   - `pg_dumpall -U postgres` is executed inside the running `postgres` container.
   - The logical dump is staged to `${DOCKER_DATA_DIR}/postgres/staged_backup/postgres_dumpall.sql`.
2. **SQLite**:
   - For SQLite databases (e.g. Mealie, Sonarr, Radarr), SQLite `.backup` API is used or read-consistent snapshots are taken.
3. Restic backs up both the live data directories and the staged logical dumps into the repository.

---

## Restic Repository Maintenance and Pruning

Retention policy is enforced automatically during `homelab.sh backup`:
- **Daily retention**: 30 days (`--keep-daily 30`).
- **Weekly retention**: 4 weeks (`--keep-weekly 4`).
- **Monthly retention**: 12 months (`--keep-monthly 12`).

To manually check repository integrity or prune:
```bash
restic -r "${BACKUP_RESTIC_REPO}" --password-file /root/.restic_password check
restic -r "${BACKUP_RESTIC_REPO}" --password-file /root/.restic_password forget --prune --keep-daily 30
```
