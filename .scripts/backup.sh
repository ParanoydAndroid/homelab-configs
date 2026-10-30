#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/backup.sh
# Description:
#   Configuration backup, chronological PEP 440 / CalVer git tagging, and
#   live .env secret archiving for the homelab repository.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: resolve_chronological_tag
# Description:
#   Generates a chronological PEP 440 / CalVer git tag string (YYYY.M.D[.N]).
# Outputs:
#   Prints resolved unique tag string on stdout.
# ------------------------------------------------------------------------------
resolve_chronological_tag() {
  local base_tag candidate seq=1
  base_tag="$(date +%Y.%-m.%-d)"
  candidate="${base_tag}"

  while git -C "${REPO_DIR}" rev-parse -q --verify "refs/tags/${candidate}" >/dev/null 2>&1; do
    candidate="${base_tag}.${seq}"
    ((seq++))
  done

  printf "%s" "${candidate}"
}

# ------------------------------------------------------------------------------
# Function: backup_homelab
# Description:
#   Performs git-centric configuration backup and secret archiving:
#     1. Invokes 'pull_configs' to capture live configurations.
#     2. Commits working tree changes if modified.
#     3. Applies chronological or custom git tag if requested.
#     4. Archives all untracked .env files to ${DOCKER_DATA_DIR}/backup/homelab/.
# Globals Read:
#   REPO_DIR, DOCKER_DATA_DIR, STACKS, TARGET_USER, TARGET_GROUP,
#   BACKUP_TAG_ENABLED, BACKUP_TAG_NAME, BACKUP_COMMIT_MSG
# ------------------------------------------------------------------------------
backup_homelab() {
  pull_configs

  # Commit configuration changes to git
  if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
    local commit_msg="${BACKUP_COMMIT_MSG:-Backup homelab configuration ($(date '+%Y-%m-%d %H:%M:%S'))}"
    log_info "Committing configuration changes to git: ${commit_msg}"
    git -C "${REPO_DIR}" add -A
    git -C "${REPO_DIR}" commit -m "${commit_msg}"
  else
    log_info "Git working tree is clean; no configuration changes to commit."
  fi

  # Apply git tag if requested
  if [[ "${BACKUP_TAG_ENABLED}" -eq 1 ]]; then
    local tag_to_apply="${BACKUP_TAG_NAME:-$(resolve_chronological_tag)}"
    if git -C "${REPO_DIR}" rev-parse -q --verify "refs/tags/${tag_to_apply}" >/dev/null 2>&1; then
      log_warn "Git tag '${tag_to_apply}' already exists; skipping tag creation."
    else
      git -C "${REPO_DIR}" tag -a "${tag_to_apply}" -m "Homelab configuration backup ${tag_to_apply}"
      log_info "Created git tag: ${tag_to_apply}"
    fi
  fi

  # Archive live .env secret files
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
