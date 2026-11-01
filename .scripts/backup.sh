#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/backup.sh
# Description:
#   Restic-powered backup and restore automation for persistent Docker volume data
#   (${DOCKER_DATA_DIR}) and live .env secret archives.
#
# Architecture:
#   1. Zero-Downtime Database Staging:
#      Executes online dumps (pg_dumpall for PostgreSQL and sqlite3 .backup for
#      NPM/Jellyfin/Sonarr/Radarr) into ${DOCKER_DATA_DIR}/.backups before taking
#      the snapshot.
#   2. Untracked Secret Archiving:
#      Packages root and per-stack .env secret files into a date-stamped tarball
#      in ${DOCKER_DATA_DIR}/backup/homelab/.
#   3. Deduplicated & Compressed Snapshotting:
#      Uses native host restic (v0.19.1+) with --insecure-no-password to stream
#      compressed, deduplicated volume snapshots to primary RAID storage
#      (${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}).
#   4. Retention & Pruning:
#      Enforces daily retention policy (--keep-daily 30) and prunes unreferenced
#      data chunks automatically.
#   5. Disaster Recovery & Restoration:
#      Provides full-volume or granular per-service restore capabilities with
#      pre-restore container quiesce checks to prevent database corruption.
# ==============================================================================
set -euo pipefail

# Standard exclusion list for transient caches, logs, and temp files
RESTIC_EXCLUDES=(
  --exclude="*/transcodes/*"
  --exclude="*/cache/*"
  --exclude="*/Cache/*"
  --exclude="*/log/*"
  --exclude="*/logs/*"
  --exclude="*.log"
  --exclude="*/torrents/*"
  --exclude="*/data/torrents/*"
)

# ------------------------------------------------------------------------------
# Function: check_root_privileges
# Description:
#   Validates that the current execution process has root privileges (EUID 0).
#   Root is strictly required to capture and restore exact numeric UIDs/GIDs
#   (e.g., 70:70 for PostgreSQL, 1000:100 for non-root apps, 0:0 for root).
# ------------------------------------------------------------------------------
check_root_privileges() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_error "This operation requires root privileges to preserve container UIDs/GIDs. Please run with sudo."
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Function: ensure_restic_available
# Description:
#   Verifies that the restic binary is installed and executable on the host.
# ------------------------------------------------------------------------------
ensure_restic_available() {
  if ! command -v restic >/dev/null 2>&1; then
    log_error "Restic binary not found on host. Install or update restic before proceeding."
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# Function: init_restic_repo
# Description:
#   Checks if the target restic repository exists and initializes it with
#   --insecure-no-password if missing.
# Globals Read:
#   BACKUP_RESTIC_REPO
# ------------------------------------------------------------------------------
init_restic_repo() {
  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  mkdir -p "${repo}"

  # Test if repository is already initialized by probing snapshots
  if ! restic -r "${repo}" --insecure-no-password snapshots >/dev/null 2>&1; then
    log_info "Initializing new restic repository at ${repo} (--insecure-no-password)..."
    restic init -r "${repo}" --insecure-no-password
    log_info "Restic repository successfully initialized at ${repo}."
  fi
}

# ------------------------------------------------------------------------------
# Function: unlock_restic_repo
# Description:
#   Removes stale locks left in the repository by previously interrupted or
#   crashed backup operations.
# Globals Read:
#   BACKUP_RESTIC_REPO
# ------------------------------------------------------------------------------
unlock_restic_repo() {
  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  if [[ -d "${repo}" ]]; then
    restic -r "${repo}" --insecure-no-password unlock >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
# Function: stage_database_dumps
# Description:
#   Performs non-disruptive online database backups prior to taking the restic
#   volume snapshot:
#     - PostgreSQL: Executes 'pg_dumpall' inside the container if running.
#     - SQLite: Executes safe online '.backup' or WAL checkpoints for NPM,
#       Jellyfin, Sonarr, and Radarr databases.
# Globals Read:
#   DOCKER_DATA_DIR
# ------------------------------------------------------------------------------
stage_database_dumps() {
  local staging_dir="${DOCKER_DATA_DIR}/.backups"
  mkdir -p "${staging_dir}/sqlite"

  # 1. PostgreSQL online dump
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'postgresql'; then
    log_info "Creating online PostgreSQL dump for database 'recipes'..."
    if docker exec postgresql pg_dumpall -U postgres > "${staging_dir}/postgres_dumpall.sql" 2>/dev/null; then
      chmod 0600 "${staging_dir}/postgres_dumpall.sql" 2>/dev/null || true
      log_info "PostgreSQL online dump created at ${staging_dir}/postgres_dumpall.sql."
    else
      log_warn "PostgreSQL dump command returned non-zero status; proceeding with live volume snapshot."
    fi
  fi

  # 2. SQLite online backups
  if command -v sqlite3 >/dev/null 2>&1; then
    local sqlite_dbs=(
      "${DOCKER_DATA_DIR}/nginx/data/db.sqlite"
      "${DOCKER_DATA_DIR}/jellyfin/data/data/jellyfin.db"
      "${DOCKER_DATA_DIR}/sonarr-radarr/data/sonarr/sonarr.db"
      "${DOCKER_DATA_DIR}/sonarr-radarr/data/radarr/radarr.db"
    )
    local db db_name
    for db in "${sqlite_dbs[@]}"; do
      if [[ -f "${db}" ]]; then
        db_name="$(basename "${db}")"
        # Perform online backup into staging directory
        sqlite3 "${db}" ".backup '${staging_dir}/sqlite/${db_name}.bak'" 2>/dev/null || true
      fi
    done
    log_info "SQLite online checkpoints staged under ${staging_dir}/sqlite/."
  fi
}

# ------------------------------------------------------------------------------
# Function: clean_database_staging
# Description:
#   Removes temporary database dumps after restic completes the snapshot.
# Globals Read:
#   DOCKER_DATA_DIR
# ------------------------------------------------------------------------------
clean_database_staging() {
  local staging_dir="${DOCKER_DATA_DIR}/.backups"
  if [[ -d "${staging_dir}" ]]; then
    rm -rf "${staging_dir}"
  fi
}

# ------------------------------------------------------------------------------
# Function: archive_env_secrets
# Description:
#   Archives all untracked root and per-stack .env secret files into a date-stamped
#   tarball in ${DOCKER_DATA_DIR}/backup/homelab/.
# Globals Read:
#   REPO_DIR, DOCKER_DATA_DIR, STACKS, TARGET_USER, TARGET_GROUP
# ------------------------------------------------------------------------------
archive_env_secrets() {
  local backup_dir="${DOCKER_DATA_DIR}/backup/homelab"
  local date_prefix env_archive latest_link
  date_prefix="$(date +%Y.%-m.%-d)"
  env_archive="${backup_dir}/${date_prefix}_env_secrets.tar.gz"
  latest_link="${backup_dir}/latest_env_secrets.tar.gz"

  mkdir -p "${backup_dir}"

  local env_files=()
  [[ -f "${REPO_DIR}/.env" ]] && env_files+=(".env")

  local stack
  for stack in "${STACKS[@]}"; do
    [[ -f "${REPO_DIR}/${stack}/.env" ]] && env_files+=("${stack}/.env")
  done

  if [[ "${#env_files[@]}" -gt 0 ]]; then
    tar -czf "${env_archive}" -C "${REPO_DIR}" "${env_files[@]}"
    chmod 0600 "${env_archive}" 2>/dev/null || true
    ln -sf "$(basename "${env_archive}")" "${latest_link}"
    chown -h "${TARGET_USER}:${TARGET_GROUP}" "${env_archive}" "${latest_link}" 2>/dev/null || true
    log_info "Archived ${#env_files[@]} live .env secret files to: ${env_archive} (symlinked at ${latest_link})"
  else
    log_warn "No live .env files found to archive."
  fi
}

# ------------------------------------------------------------------------------
# Function: backup_homelab
# Description:
#   Orchestrates end-to-end homelab volume backup:
#     1. Enforces root privileges and checks restic availability.
#     2. Unlocks stale repository locks and initializes repository if missing.
#     3. Archives untracked .env secrets.
#     4. Stages zero-downtime database dumps.
#     5. Executes incremental deduplicated restic backup with cache exclusions.
#     6. Applies retention policy (--keep-daily 30) and prunes repository.
#     7. Cleans temporary database staging files.
# Globals Read:
#   BACKUP_RESTIC_REPO, BACKUP_RETENTION_DAYS, DOCKER_DATA_DIR
# ------------------------------------------------------------------------------
backup_homelab() {
  check_root_privileges
  ensure_restic_available
  init_and_sync_env

  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  local retention="${BACKUP_RETENTION_DAYS:-30}"

  unlock_restic_repo
  init_restic_repo
  archive_env_secrets

  log_info "Staging zero-downtime database dumps..."
  stage_database_dumps

  # Ensure staging directory is cleaned up even on unexpected termination
  trap clean_database_staging EXIT

  log_info "Starting Restic backup of ${DOCKER_DATA_DIR} to ${repo}..."
  restic -r "${repo}" --insecure-no-password backup \
    "${RESTIC_EXCLUDES[@]}" \
    --tag homelab \
    "${DOCKER_DATA_DIR}"

  log_info "Applying ${retention}-day retention policy and pruning repository..."
  restic -r "${repo}" --insecure-no-password forget \
    --tag homelab \
    --keep-daily "${retention}" \
    --prune

  clean_database_staging
  trap - EXIT

  log_info "Homelab volume backup completed successfully."
}

# ------------------------------------------------------------------------------
# Function: snapshots_homelab
# Description:
#   Displays list of available restic snapshots in the backup repository.
# Globals Read:
#   BACKUP_RESTIC_REPO
# ------------------------------------------------------------------------------
snapshots_homelab() {
  ensure_restic_available
  init_and_sync_env
  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"

  if [[ ! -d "${repo}" ]]; then
    log_error "Backup repository not found at ${repo}. Run 'homelab.sh backup' first."
    exit 1
  fi

  restic -r "${repo}" --insecure-no-password snapshots
}

# ------------------------------------------------------------------------------
# Function: restore_homelab
# Description:
#   Restores persistent volume state from a restic snapshot:
#     - Arguments:
#       $1 - Optional snapshot ID (defaults to 'latest').
#       $2 - Optional specific service name to restore (e.g. 'jellyfin', 'nginx').
#     - Flags:
#       -f, --force - Bypass running container check and overwrite safety prompt.
# Globals Read:
#   BACKUP_RESTIC_REPO, DOCKER_DATA_DIR
# ------------------------------------------------------------------------------
restore_homelab() {
  check_root_privileges
  ensure_restic_available
  init_and_sync_env

  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  local snapshot_id="latest"
  local target_service=""
  local force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        force=1
        shift
        ;;
      *)
        if [[ "${snapshot_id}" == "latest" && "$1" != "latest" ]]; then
          snapshot_id="$1"
        elif [[ -z "${target_service}" ]]; then
          target_service="$1"
        fi
        shift
        ;;
    esac
  done

  # Safety Guard: Check if containers are running
  local running_containers=""
  if command -v docker >/dev/null 2>&1; then
    running_containers="$(docker ps --format '{{.Names}}' 2>/dev/null || true)"
  fi

  if [[ -n "${running_containers}" && "${force}" -eq 0 ]]; then
    log_warn "Active Docker containers detected:"
    printf "%s\n" "${running_containers}"
    log_warn "Restoring active volume files while containers are running can cause database corruption."
    if [[ -t 0 ]]; then
      read -r -p "Proceed with restore anyway? [y/N]: " confirm
      if [[ "${confirm}" != [yY] && "${confirm}" != [yY][eE][sS] ]]; then
        log_info "Restore aborted by user. Stop running containers before restoring."
        exit 0
      fi
    else
      log_error "Refusing to restore over running containers in non-interactive mode. Stop containers or pass -f/--force."
      exit 1
    fi
  fi

  log_info "Restoring from snapshot '${snapshot_id}'..."
  if [[ -n "${target_service}" ]]; then
    local service_path="${DOCKER_DATA_DIR}/${target_service}"
    log_info "Restoring specific service path: ${service_path}"
    restic -r "${repo}" --insecure-no-password restore "${snapshot_id}" \
      --target / \
      --include "${service_path}"
  else
    log_info "Performing full volume restore to ${DOCKER_DATA_DIR}..."
    restic -r "${repo}" --insecure-no-password restore "${snapshot_id}" \
      --target /
  fi

  # Verify and ensure PostgreSQL ownership integrity
  if [[ -d "${DOCKER_DATA_DIR}/postgres/data" ]]; then
    chown -R 70:70 "${DOCKER_DATA_DIR}/postgres/data" 2>/dev/null || true
  fi

  log_info "Restore operation completed successfully."
}
