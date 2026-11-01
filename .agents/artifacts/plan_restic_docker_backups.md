# Implementation Plan: Restic Backup & Restore Architecture for Homelab

## 1. Executive Summary & Objective

The existing homelab configuration management relies on a bidirectional pull/deploy workflow (`pull-configs` and `deploy-configs` in `.scripts/configs.sh`) paired with git commits and tarball `.env` archives in `.scripts/backup.sh`. Because stateful container databases (such as Jellyfin's SQLite database, NPM SQLite routing tables, and PostgreSQL) must be backed up from the NVMe storage array (`/volume2/docker`) to the primary RAID storage pool (`/volume1`), tracking extracted text configurations in git is redundant and introduces maintenance overhead.

This plan details the replacement of the existing pull/deploy and git-archive mechanisms with an automated, incremental, deduplicated **restic** backup and restore engine targeting `/volume2/docker` (volume data) and associated configurations.

---

## 2. Key Architecture Decisions & Parameters

| Parameter | Specification | Notes |
| :--- | :--- | :--- |
| **Source Path** | `${DOCKER_DATA_DIR}` (`/volume2/docker`) | Stacks and compose configs remain in git; live `.env` files continue to be archived as tarballs. |
| **Backup Destination** | `${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}` | Stored on primary RAID array (`/volume1`), configurable in `.env`. |
| **Tooling** | Native host `/usr/bin/restic` (v0.19.1) | Verified on UGREEN NAS host with format version 2 & compression. |
| **Database Consistency** | Lightweight pre-backup hooks | Online `pg_dumpall` for PostgreSQL and SQLite `.backup` / WAL checkpoint for high-churn DBs before snapshot. |
| **Retention Policy** | `--keep-daily 30` + automatic `--prune` | Preserves 30 daily snapshots within ~100 GB budget. |
| **Repository Key / Auth** | Native `--insecure-no-password` | Truly passwordless repository; no keyfiles, passwords, or secrets needed. |
| **Scheduling** | `homelab-backup.service` + `homelab-backup.timer` | Runs nightly (03:00) with jitter. |
| **Deprecated Subcommands** | `pull-configs`, `deploy-configs` | Removed from `homelab.sh`, `.scripts/configs.sh`, and documentation. |
| **New Subcommands** | `backup`, `restore`, `backup-snapshots` | Unified backup lifecycle in `homelab.sh`. |

---

## 3. Database Consistency & Live Backup Strategy

Containers continuously write to SQLite databases (Jellyfin, Nginx Proxy Manager, Sonarr, Radarr) and PostgreSQL (`recipes` DB).
To ensure consistency without service disruption or container restarts, the backup workflow executes online database dumps prior to triggering restic:

1. **PostgreSQL**:
   - If the `postgresql` container is running, execute `docker exec postgresql pg_dumpall -U postgres` to write a consistent text SQL dump to `${DOCKER_DATA_DIR}/.backups/postgres_dumpall.sql`.
2. **SQLite (NPM, Jellyfin, Sonarr, Radarr)**:
   - For high-churn databases, perform an online backup via `sqlite3 <source_db> ".backup <dest_db>"` or trigger a non-blocking `PRAGMA wal_checkpoint(PASSIVE)` into `${DOCKER_DATA_DIR}/.backups/sqlite/` prior to snapshotting.
3. **Snapshot Phase**:
   - Restic snapshots `${DOCKER_DATA_DIR}` including the consistent database dump directories.
   - Clean up or rotate the staging dumps after snapshot completion.

---

## 4. Phased Implementation Plan

### Phase 1: Environment & Repository Initialization
- Define backup configuration variables in root `.env.example` and `.env`:
  - `BACKUP_RESTIC_REPO=/volume1/backups/homelab-docker`
  - `BACKUP_RETENTION_DAYS=30`
- Add restic repo auto-initialization (`restic init --insecure-no-password`) if repository directory does not exist or has not been initialized. No password files or variables required.

### Phase 2: Restic Backup & Restore Module (`.scripts/backup.sh`)
- Replace existing `.scripts/backup.sh` with modular restic automation:
  - **Permission Enforcement**: Require root (`sudo`) execution for both `backup` and `restore` to ensure exact numeric UIDs/GIDs (`70:70` PostgreSQL, `1000:100` non-root apps, `0:0` root services) are captured and restored without ownership drift.
  - **Lock Safety**: Auto-detect and unlock stale restic repository locks (`restic unlock --insecure-no-password`) prior to backup operations.
  - `backup_homelab`:
    1. Pre-backup database hooks (online `pg_dumpall` for PostgreSQL, SQLite `.backup` / WAL checkpoint for NPM and Jellyfin).
    2. Archive live `.env` files into `${DOCKER_DATA_DIR}/backup/homelab/${date_prefix}_env_secrets.tar.gz`.
    3. Execute `restic backup` targeting `${DOCKER_DATA_DIR}` with explicit exclusion filters:
       - `--exclude="*/transcodes/*"`
       - `--exclude="*/cache/*"`
       - `--exclude="*/Cache/*"`
       - `--exclude="*/log/*"`
       - `--exclude="*/logs/*"`
       - `--exclude="*.log"`
       - `--exclude="*/torrents/*"`
    4. Execute `restic forget --keep-daily ${BACKUP_RETENTION_DAYS:-30} --prune`.
    5. Clean up temporary database dump staging files.
    6. Output summary metrics (snapshot ID, files processed, pruned snapshots, repo size).
  - `restore_homelab`:
    1. Interactive or flag-driven snapshot selection (`latest` or specific snapshot ID) and optional single-service target path (e.g. `jellyfin` or full restore).
    2. Pre-restore container safety check: verify if containers using `${DOCKER_DATA_DIR}` are currently active. Refuse or prompt to stop containers before overwriting live database files (bypassable via `-f` / `--force`).
    3. Execute `restic restore <snapshot> --target /` (or specific `--include <service>` path).
    4. Verify filesystem ownership integrity across restored service directories.
  - `snapshots_homelab`:
    1. Wrapper around `restic snapshots` to view snapshot IDs, timestamps, tags, and summary sizes.

### Phase 3: Deprecate `deploy-configs` & `pull-configs`
- Remove `deploy-configs` and `pull-configs` from `homelab.sh` CLI parser.
- Deprecate/remove `.scripts/configs.sh`.
- Update `setup_homelab` in `homelab.sh`:
  - Ensure Dockge's orchestrator `compose.yml` (`.configs/dockge/compose.yml`) is placed at `${DOCKGE_DIR}/compose.yml` without relying on `deploy_configs`.
  - Clean up obsolete conflict resolution flags (`-O`, `-K`, `OVERWRITE_MODE`).
- Clean up git-tracked `.configs/`:
  - Keep bootstrap assets (e.g., initial Dockge `compose.yml`, systemd service templates, local cert scripts).
  - Retire exported live dumps (`npm_hosts.sql`, live Nginx `.conf` copies, Homepage YAML overrides) since state will now be restored directly from restic snapshots.

### Phase 4: Documentation, Rule Governance & Verification
- Update project documentation:
  - `README.md`: Update commands table, backup architecture, and disaster recovery workflow.
  - `.docs/operations.md`: Document restic backup, pruning, manual restore, and disaster recovery.
  - `.docs/project-organization.md`: Remove deprecated config sync references.
  - `.agents/rules/project-conventions.md`: Revise volume and backup conventions to reflect restic architecture instead of bidirectional config sync.
  - `.agents/artifacts/architecture.md`: Document restic retention, volume layout, and recovery model.
- Smoke & Verification Testing:
  - Add automated test assertions in `.tests/` to verify `restic check`, repository accessibility, and snapshot existence.
  - Perform dry-run test of backup creation and snapshot inspection.

---

## 5. Locked Architectural Decisions

1. **Backup Source Scope**:
   - Limited strictly to `${DOCKER_DATA_DIR}` (`/volume2/docker`). All stack Compose files and documentation are preserved in git. Live `.env` secret archives continue to be packaged into `${DOCKER_DATA_DIR}/backup/homelab/` tarballs during the backup run.
2. **Database Backup Policy**:
   - Zero container downtime via non-disruptive online dumps (`pg_dumpall` for PostgreSQL and SQLite `.backup` / WAL checkpointing) staged immediately before restic takes the volume snapshot.
3. **Passwordless Security Model**:
   - Utilizing restic 0.19.1 native `--insecure-no-password` for repository creation, backup, and restore. No passwords, keyfiles, or environment secrets required.
4. **Automated Scheduling**:
   - Deploy `homelab-backup.service` and `homelab-backup.timer` under `.configs/systemd/` to run nightly at 03:00 with randomized jitter.
5. **Operational Safeguards**:
   - **Cache/Transcode Exclusions**: Skip non-essential transient caches (`transcodes/`, `cache/`, `Cache/`, `log/`, `torrents/`) to save space and reduce I/O.
   - **Root Enforcement**: Enforce root (`sudo`) execution on `backup` and `restore` to ensure numeric UIDs/GIDs (`70:70` PostgreSQL, `1000:100` non-root apps, `0:0` root) are preserved and restored faithfully.
   - **Pre-Restore Container Quiesce**: Prevent database corruption during restore by checking for active containers and prompting/stopping them before restoring files.
   - **Stale Lock Auto-Remediation**: Automatically check for and unlock abandoned restic locks (`restic unlock --insecure-no-password`) prior to backup runs.


