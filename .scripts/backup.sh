#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/backup.sh
# Description:
#   Restic-powered backup, verification, and restore automation for persistent
#   Docker volume data (${DOCKER_DATA_DIR}) and live .env secret archives.
#
# Architecture:
#   1. Declarative Zero-Downtime Staging:
#      Dynamically discovers containers declaring 'homelab.backup.sqlite' labels,
#      resolves internal container paths to host volume mounts, and executes safe
#      online checkpoints ('sqlite3 .backup') into ${DOCKER_DATA_DIR}/.backups/sqlite
#      prior to snapshotting.
#   2. Dynamic Exclusion Engine:
#      Discovers scratch/transient volumes via 'homelab.backup.exclude' labels
#      (e.g. qBittorrent scratch incomplete buffers) and appends dynamic exclusions
#      alongside standard static cache and log exclusion patterns.
#   3. Untracked Secret Archiving & 30-Day Retention:
#      Packages root and per-stack .env secret files into a date-stamped tarball
#      in ${DOCKER_DATA_DIR}/backup/homelab/ and automatically prunes archives
#      older than BACKUP_RETENTION_DAYS (30 days).
#   4. Git Decoupling:
#      Scheduled backups capture active git commit SHAs as snapshot metadata
#      without mutating or auto-committing working tree changes. Explicit commits
#      are triggered only when requested via --commit or -m.
#   5. Pre-Flight Disk Safety & Health Auditing:
#      Enforces minimum free capacity thresholds on staging and target arrays, and
#      exposes repository verification ('manage.sh backup check').
#   6. Disaster Recovery & Restoration:
#      Provides full-volume or granular per-service restore capabilities with
#      pre-restore container quiesce checks and dry-run manifest inspection.
# ==============================================================================
set -euo pipefail

# Ensure common environment and versioning functions are loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/common.sh" ]] && source "${SCRIPT_DIR}/common.sh"

# Standard baseline exclusion list for transient caches, logs, and temp files
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

# Global variables for repeatable backup tagging and git commit operations
BACKUP_TAG_REQUESTS=()
BACKUP_COMMIT_MSG=""
BACKUP_DO_COMMIT=0

# ------------------------------------------------------------------------------
# Function: check_root_privileges
# Description:
#   Validates that the current execution process has root privileges (EUID 0).
#   Root is strictly required to capture and restore exact numeric UIDs/GIDs
#   (e.g., 1000:100 for non-root apps, 0:0 for root).
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
# Function: check_disk_space
# Description:
#   Pre-flight check verifying sufficient storage capacity is available before
#   initiating snapshots or staging dumps:
#     - Staging volume (${DOCKER_DATA_DIR}): Requires >= 5 GB free.
#     - Target backup repo parent directory: Requires >= 10 GB free.
# Globals Read:
#   DOCKER_DATA_DIR, BACKUP_RESTIC_REPO
# ------------------------------------------------------------------------------
check_disk_space() {
  local staging_path="${DOCKER_DATA_DIR}"
  local repo_path="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  local repo_parent
  repo_parent="$(dirname "${repo_path}")"

  # Minimum required kilobytes: 5 GB for staging, 10 GB for repo
  local min_staging_kb=5242880
  local min_repo_kb=10485760

  if [[ -d "${staging_path}" ]]; then
    local avail_staging_kb
    avail_staging_kb="$(df -Pk "${staging_path}" | awk 'NR==2 {print $4}')"
    if [[ "${avail_staging_kb:-0}" -lt "${min_staging_kb}" ]]; then
      log_warn "Low storage space on staging directory (${staging_path}): $(( avail_staging_kb / 1024 )) MB free (minimum 5000 MB recommended)."
    fi
  fi

  if [[ -d "${repo_parent}" ]]; then
    local avail_repo_kb
    avail_repo_kb="$(df -Pk "${repo_parent}" | awk 'NR==2 {print $4}')"
    if [[ "${avail_repo_kb:-0}" -lt "${min_repo_kb}" ]]; then
      log_warn "Low storage space on backup repository target (${repo_parent}): $(( avail_repo_kb / 1024 )) MB free (minimum 10000 MB recommended)."
    fi
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
# Function: check_restic_repo
# Description:
#   Verifies structural integrity and data pack consistency of the Restic
#   backup repository ('restic check').
# Globals Read:
#   BACKUP_RESTIC_REPO
# ------------------------------------------------------------------------------
check_restic_repo() {
  check_root_privileges
  ensure_restic_available
  init_and_sync_env
  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"

  if [[ ! -d "${repo}" ]]; then
    log_error "Backup repository not found at ${repo}. Run 'manage.sh backup' first."
    exit 1
  fi

  unlock_restic_repo
  log_info "Verifying structural integrity of Restic repository at ${repo}..."
  restic -r "${repo}" --insecure-no-password check
  log_info "Restic repository integrity check completed successfully."
}

# ------------------------------------------------------------------------------
# Function: resolve_backup_excludes
# Description:
#   Queries Docker containers for declarative 'homelab.backup.exclude' labels,
#   translates internal container paths to host volume paths, and returns an
#   array of combined static and dynamic '--exclude' flags for Restic.
# Outputs:
#   Prints one '--exclude=<path>' argument per line on stdout.
# ------------------------------------------------------------------------------
resolve_backup_excludes() {
  local excludes=("${RESTIC_EXCLUDES[@]}")

  if ! command -v docker >/dev/null 2>&1; then
    printf "%s\n" "${excludes[@]}"
    return 0
  fi

  local container_list=()
  while IFS= read -r c; do
    [[ -n "${c}" ]] && container_list+=("${c}")
  done < <(docker ps -a --filter "label=homelab.backup.exclude" --format '{{.Names}}' 2>/dev/null || true)

  local container
  for container in "${container_list[@]}"; do
    local is_enabled
    is_enabled="$(docker inspect "${container}" --format '{{ index .Config.Labels "homelab.backup.enable" }}' 2>/dev/null || true)"
    if [[ "${is_enabled}" == "false" || "${is_enabled}" == "0" ]]; then
      continue
    fi

    local raw_exclude
    raw_exclude="$(docker inspect "${container}" --format '{{ index .Config.Labels "homelab.backup.exclude" }}' 2>/dev/null || true)"
    [[ -z "${raw_exclude}" ]] && continue

    local mounts=()
    while IFS= read -r m; do
      [[ -n "${m}" ]] && mounts+=("${m}")
    done < <(docker inspect "${container}" --format '{{ range .Mounts }}{{ .Destination }}:{{ .Source }}{{ println }}{{ end }}' 2>/dev/null || true)

    local internal_excludes=()
    IFS=',' read -ra internal_excludes <<< "${raw_exclude}"
    local p
    for p in "${internal_excludes[@]}"; do
      p="$(echo "${p}" | xargs)"
      [[ -z "${p}" ]] && continue

      local host_path=""
      local m
      for m in "${mounts[@]}"; do
        local dest="${m%%:*}"
        local src="${m#*:}"
        if [[ "${p}" == "${dest}"* ]]; then
          local rel="${p#"${dest}"}"
          rel="${rel#/}"
          if [[ -n "${rel}" ]]; then
            host_path="${src}/${rel}"
          else
            host_path="${src}"
          fi
          break
        fi
      done

      if [[ -n "${host_path}" ]]; then
        excludes+=("--exclude=${host_path}")
        excludes+=("--exclude=${host_path}/*")
      fi
    done
  done

  printf "%s\n" "${excludes[@]}"
}

# ------------------------------------------------------------------------------
# Function: stage_database_dumps
# Description:
#   Performs non-disruptive online database backups prior to taking the restic
#   volume snapshot:
#     - Discovers active containers declaring 'homelab.backup.sqlite' labels.
#     - Resolves internal container paths to host volume mount directories.
#     - Executes safe online 'sqlite3 .backup' checkpoints into
#       ${DOCKER_DATA_DIR}/.backups/sqlite.
# Globals Read:
#   DOCKER_DATA_DIR
# ------------------------------------------------------------------------------
stage_database_dumps() {
  local staging_dir="${DOCKER_DATA_DIR}/.backups"
  mkdir -p "${staging_dir}/sqlite"

  if ! command -v sqlite3 >/dev/null 2>&1; then
    log_warn "sqlite3 binary not available on host; skipping safe online checkpoints."
    return 0
  fi

  local staged_count=0
  local container_list=()
  if command -v docker >/dev/null 2>&1; then
    while IFS= read -r c; do
      [[ -n "${c}" ]] && container_list+=("${c}")
    done < <(docker ps -a --filter "label=homelab.backup.sqlite" --format '{{.Names}}' 2>/dev/null || true)
  fi

  local container
  for container in "${container_list[@]}"; do
    local is_enabled
    is_enabled="$(docker inspect "${container}" --format '{{ index .Config.Labels "homelab.backup.enable" }}' 2>/dev/null || true)"
    if [[ "${is_enabled}" == "false" || "${is_enabled}" == "0" ]]; then
      log_info "Skipping container '${container}' (homelab.backup.enable=false)."
      continue
    fi

    local raw_sqlite
    raw_sqlite="$(docker inspect "${container}" --format '{{ index .Config.Labels "homelab.backup.sqlite" }}' 2>/dev/null || true)"
    [[ -z "${raw_sqlite}" ]] && continue

    local mounts=()
    while IFS= read -r m; do
      [[ -n "${m}" ]] && mounts+=("${m}")
    done < <(docker inspect "${container}" --format '{{ range .Mounts }}{{ .Destination }}:{{ .Source }}{{ println }}{{ end }}' 2>/dev/null || true)

    local internal_paths=()
    IFS=',' read -ra internal_paths <<< "${raw_sqlite}"
    local p
    for p in "${internal_paths[@]}"; do
      p="$(echo "${p}" | xargs)"
      [[ -z "${p}" ]] && continue

      local host_path=""
      local m
      for m in "${mounts[@]}"; do
        local dest="${m%%:*}"
        local src="${m#*:}"
        if [[ "${p}" == "${dest}"* ]]; then
          local rel="${p#"${dest}"}"
          rel="${rel#/}"
          if [[ -n "${rel}" ]]; then
            host_path="${src}/${rel}"
          else
            host_path="${src}"
          fi
          break
        fi
      done

      if [[ -n "${host_path}" && -f "${host_path}" ]]; then
        local db_basename
        db_basename="$(basename "${host_path}")"
        local staged_name="${container}_${db_basename}.bak"
        log_info "Staging online SQLite checkpoint for ${container} (${p} -> ${staged_name})..."
        sqlite3 "${host_path}" ".backup '${staging_dir}/sqlite/${staged_name}'" 2>/dev/null || true
        ((staged_count++)) || true
      elif [[ -n "${host_path}" ]]; then
        log_warn "Declared SQLite file '${p}' for container '${container}' not found at '${host_path}'."
      else
        log_warn "Could not resolve volume mount for '${p}' in container '${container}'."
      fi
    done
  done

  log_info "Staged ${staged_count} SQLite online checkpoints under ${staging_dir}/sqlite/."
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
#   tarball in ${DOCKER_DATA_DIR}/backup/homelab/ and prunes stale secret archives
#   older than BACKUP_RETENTION_DAYS (30 days).
# Globals Read:
#   REPO_DIR, DOCKER_DATA_DIR, STACKS, TARGET_USER, TARGET_GROUP, BACKUP_RETENTION_DAYS
# ------------------------------------------------------------------------------
archive_env_secrets() {
  local backup_dir="${DOCKER_DATA_DIR}/backup/homelab"
  local retention="${BACKUP_RETENTION_DAYS:-30}"
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

  # Prune local .env archives older than retention threshold to prevent NVMe accumulation
  if [[ -d "${backup_dir}" ]]; then
    local pruned
    pruned="$(find "${backup_dir}" -name "*_env_secrets.tar.gz" -mtime +"${retention}" 2>/dev/null || true)"
    if [[ -n "${pruned}" ]]; then
      find "${backup_dir}" -name "*_env_secrets.tar.gz" -mtime +"${retention}" -delete 2>/dev/null || true
      log_info "Pruned stale local .env secret archives older than ${retention} days."
    fi
  fi
}

# ------------------------------------------------------------------------------
# Function: commit_and_tag_git
# Description:
#   Commits working tree changes if present, creates annotated git tags, and
#   pushes commits and tags to remote origin if configured.
# Arguments:
#   $@ - Array of resolved tags to apply.
# Globals Read:
#   BACKUP_COMMIT_MSG
# ------------------------------------------------------------------------------
commit_and_tag_git() {
  local tags=("$@")
  local commit_msg="${BACKUP_COMMIT_MSG:-}"

  # Default commit message if none provided
  if [[ -z "${commit_msg}" ]]; then
    local now
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    commit_msg="Backup homelab configuration (${now})"
  fi

  # Check if repository has uncommitted changes
  if ! run_git diff --quiet || ! run_git diff --cached --quiet || [[ -n "$(run_git status --porcelain)" ]]; then
    log_info "Staging all tracked and untracked changes for commit..."
    run_git add -A

    log_info "Creating git commit: '${commit_msg}'..."
    run_git commit -m "${commit_msg}"
  else
    log_info "Working tree clean; no new changes to commit."
  fi

  # Create and apply resolved tags
  local t
  for t in "${tags[@]}"; do
    [[ -z "${t}" ]] && continue
    if run_git rev-parse -q --verify "refs/tags/${t}" >/dev/null 2>&1; then
      log_warn "Git tag '${t}' already exists; skipping tag creation."
    else
      log_info "Creating annotated git tag: '${t}'..."
      run_git tag -a "${t}" -m "Automated backup snapshot tag: ${t}"
    fi
  done

  # Push commits and tags to remote origin if configured
  if run_git remote | grep -qx "origin"; then
    local current_branch
    current_branch="$(run_git branch --show-current 2>/dev/null || echo "main")"
    log_info "Pushing commits on branch '${current_branch}' to origin..."
    run_git push origin "${current_branch}" || log_warn "Git push failed; continuing with backup."

    if [[ "${#tags[@]}" -gt 0 ]]; then
      log_info "Pushing tags to origin: ${tags[*]}..."
      run_git push origin "${tags[@]}" || log_warn "Git tag push failed; continuing with backup."
    fi
  fi
}

# ------------------------------------------------------------------------------
# Function: backup_homelab
# Description:
#   Orchestrates end-to-end homelab backup:
#     1. Enforces root privileges and checks restic availability.
#     2. Verifies pre-flight storage capacity on staging and target repositories.
#     3. Unlocks stale repository locks and initializes restic repo if missing.
#     4. Archives untracked .env secrets and prunes local archives older than 30d.
#     5. Stages zero-downtime database dumps dynamically discovered from container labels.
#     6. Resolves dynamic volume exclusions alongside baseline cache patterns.
#     7. Executes incremental deduplicated restic backup with correlated tags.
#     8. Applies retention policy (--keep-daily 30) and prunes repository.
#     9. Cleans temporary database staging files.
# Globals Read:
#   BACKUP_RESTIC_REPO, BACKUP_RETENTION_DAYS, DOCKER_DATA_DIR,
#   BACKUP_TAG_REQUESTS, BACKUP_DO_COMMIT, BACKUP_COMMIT_MSG
# ------------------------------------------------------------------------------
backup_homelab() {
  check_root_privileges
  ensure_restic_available
  init_and_sync_env
  check_disk_space

  local repo="${BACKUP_RESTIC_REPO:-/volume1/backups/homelab-docker}"
  local retention="${BACKUP_RETENTION_DAYS:-30}"

  # Step 1: Resolve requested tags
  local resolved_tags_str
  resolved_tags_str="$(resolve_release_tags)"
  local resolved_tags=()
  if [[ -n "${resolved_tags_str}" ]]; then
    read -r -a resolved_tags <<< "${resolved_tags_str}"
  fi

  # Explicit commit handling: Only commit git working tree if explicitly requested
  if [[ "${BACKUP_DO_COMMIT}" -eq 1 || -n "${BACKUP_COMMIT_MSG}" ]]; then
    commit_and_tag_git "${resolved_tags[@]}"
  else
    log_info "Working tree preserved; recording current commit SHA in snapshot metadata."
  fi

  # Step 2: Prepare storage repository and staging
  unlock_restic_repo
  init_restic_repo
  archive_env_secrets

  log_info "Staging zero-downtime database checkpoints..."
  stage_database_dumps

  # Ensure staging directory is cleaned up even on unexpected termination
  trap clean_database_staging EXIT

  # Step 3: Forward resolved tags into Restic snapshot
  local restic_tags=(--tag homelab)
  local current_sha
  current_sha="$(run_git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  restic_tags+=(--tag "git-${current_sha}")

  local t
  for t in "${resolved_tags[@]}"; do
    [[ -n "${t}" ]] && restic_tags+=(--tag "${t}")
  done

  # Step 4: Resolve dynamic and static volume exclusions
  local exclude_args=()
  while IFS= read -r ex; do
    [[ -n "${ex}" ]] && exclude_args+=("${ex}")
  done < <(resolve_backup_excludes)

  log_info "Starting Restic backup of ${DOCKER_DATA_DIR} to ${repo}..."
  restic -r "${repo}" --insecure-no-password backup \
    "${exclude_args[@]}" \
    "${restic_tags[@]}" \
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
    log_error "Backup repository not found at ${repo}. Run 'manage.sh backup' first."
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
#       $2 - Optional specific service name to restore (e.g. 'jellyfin', 'sonarr').
#     - Flags:
#       -f, --force    - Bypass running container check and overwrite safety prompt.
#       -n, --dry-run  - Preview snapshot files without modifying filesystem state.
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
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        force=1
        shift
        ;;
      -n|--dry-run)
        dry_run=1
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

  if [[ "${dry_run}" -eq 1 ]]; then
    log_info "Executing dry-run restore preview from snapshot '${snapshot_id}'..."
    if [[ -n "${target_service}" ]]; then
      local service_path="${DOCKER_DATA_DIR}/${target_service}"
      restic -r "${repo}" --insecure-no-password ls "${snapshot_id}" "${service_path}"
    else
      restic -r "${repo}" --insecure-no-password ls "${snapshot_id}" "${DOCKER_DATA_DIR}"
    fi
    log_info "Dry-run preview complete; no filesystem state modified."
    return 0
  fi

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

  log_info "Restore operation completed successfully."
}
