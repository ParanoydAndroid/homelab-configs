#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_backup.sh
# Purpose: Verifies restic backup tooling, environment configuration, systemd
#          timer units, and repository integrity.
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

test_backup_restic_binary() {
  if ! command -v restic >/dev/null 2>&1; then
    printf "Restic binary not found in PATH"
    return 1
  fi

  local version
  version="$(restic version 2>/dev/null | head -n 1)"
  printf "%s" "${version}"
  return 0
}

test_backup_env_config() {
  local root_env="${REPO_DIR}/.env"
  if [[ ! -f "${root_env}" ]]; then
    printf "Missing %s" "${root_env}"
    return 1
  fi

  local repo retention
  repo="$(grep -E '^BACKUP_RESTIC_REPO=' "${root_env}" | cut -d'=' -f2- || true)"
  retention="$(grep -E '^BACKUP_RETENTION_DAYS=' "${root_env}" | cut -d'=' -f2- || true)"

  if [[ -z "${repo}" || -z "${retention}" ]]; then
    printf "BACKUP_RESTIC_REPO or BACKUP_RETENTION_DAYS not set in %s" "${root_env}"
    return 1
  fi

  printf "repo=%s, retention=%sd" "${repo}" "${retention}"
  return 0
}

test_backup_systemd_units() {
  local svc="${REPO_DIR}/.configs/systemd/homelab-backup.service"
  local timer="${REPO_DIR}/.configs/systemd/homelab-backup.timer"

  if [[ ! -f "${svc}" || ! -f "${timer}" ]]; then
    printf "Missing homelab-backup service or timer in .configs/systemd/"
    return 1
  fi

  if ! grep -q "homelab.sh backup" "${svc}"; then
    printf "Service does not invoke homelab.sh backup"
    return 1
  fi

  if ! grep -q "OnCalendar=" "${timer}"; then
    printf "Timer does not define OnCalendar schedule"
    return 1
  fi

  printf "Systemd backup service and timer validated"
  return 0
}

test_backup_semver_bumping() {
  source "${REPO_DIR}/.scripts/common.sh"
  source "${REPO_DIR}/.scripts/backup.sh"

  local latest cur_maj cur_min cur_patch
  latest="$(run_git tag -l | grep -E '^v?[0-9]{1,3}\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n 1)"
  latest="${latest#v}"
  IFS='.' read -r cur_maj cur_min cur_patch <<< "${latest}"
  cur_patch="${cur_patch:-0}"

  local exp_patch="${cur_maj}.${cur_min}.$((cur_patch + 1))"
  local exp_minor="${cur_maj}.$((cur_min + 1)).0"
  local exp_major="$((cur_maj + 1)).0.0"

  local patch minor major
  patch="$(bump_semver patch)"
  minor="$(bump_semver minor)"
  major="$(bump_semver major)"

  if [[ "${patch}" != "${exp_patch}" ]]; then
    printf "Expected patch %s, got %s" "${exp_patch}" "${patch}"
    return 1
  fi

  if [[ "${minor}" != "${exp_minor}" ]]; then
    printf "Expected minor %s, got %s" "${exp_minor}" "${minor}"
    return 1
  fi

  if [[ "${major}" != "${exp_major}" ]]; then
    printf "Expected major %s, got %s" "${exp_major}" "${major}"
    return 1
  fi

  printf "patch=%s, minor=%s, major=%s" "${patch}" "${minor}" "${major}"
  return 0
}

test_backup_tag_resolution() {
  source "${REPO_DIR}/.scripts/common.sh"
  source "${REPO_DIR}/.scripts/backup.sh"

  local latest cur_maj cur_min cur_patch exp_patch
  latest="$(run_git tag -l | grep -E '^v?[0-9]{1,3}\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n 1)"
  latest="${latest#v}"
  IFS='.' read -r cur_maj cur_min cur_patch <<< "${latest}"
  cur_patch="${cur_patch:-0}"
  exp_patch="${cur_maj}.${cur_min}.$((cur_patch + 1))"

  BACKUP_TAG_REQUESTS=("SemVer-patch" "CalVer" "custom-tag-123")
  local tags_out
  tags_out="$(resolve_backup_tags)"

  if ! grep -q "${exp_patch}" <<< "${tags_out}"; then
    printf "Missing resolved SemVer patch '%s' in '%s'" "${exp_patch}" "${tags_out}"
    return 1
  fi

  if ! grep -q "custom-tag-123" <<< "${tags_out}"; then
    printf "Missing custom tag in '%s'" "${tags_out}"
    return 1
  fi

  local current_calver
  current_calver="$(date +%Y.%-m.%-d)"
  if ! grep -q "${current_calver}" <<< "${tags_out}"; then
    printf "Missing CalVer prefix '%s' in '%s'" "${current_calver}" "${tags_out}"
    return 1
  fi

  printf "Resolved: %s" "${tags_out}"
  return 0
}

test_backup_declarative_sqlite_discovery() {
  if ! command -v docker >/dev/null 2>&1; then
    printf "Docker CLI not found"
    return 1
  fi

  local containers
  containers="$(docker ps -a --filter "label=homelab.backup.sqlite" --format '{{.Names}}' | sort -u | tr '\n' ' ')"
  if [[ -z "${containers}" ]]; then
    printf "No containers found declaring 'homelab.backup.sqlite' label"
    return 1
  fi

  # Verify core expected services are present
  local expected=("sonarr" "radarr" "prowlarr" "mealie" "bindery" "calibre-web" "cleanuparr" "jellyfin")
  local missing=()
  local svc
  for svc in "${expected[@]}"; do
    if ! grep -qw "${svc}" <<< "${containers}"; then
      missing+=("${svc}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    printf "Missing declared backup.sqlite on: %s" "${missing[*]}"
    return 1
  fi

  printf "Discovered SQLite backup labels on %d containers: %s" "$(wc -w <<< "${containers}")" "${containers}"
  return 0
}

test_backup_declarative_exclusion_discovery() {
  source "${REPO_DIR}/.scripts/common.sh"
  source "${REPO_DIR}/.scripts/backup.sh"

  if ! command -v docker >/dev/null 2>&1; then
    printf "Docker CLI not found"
    return 1
  fi

  local excludes_out
  excludes_out="$(resolve_backup_excludes)"

  if ! grep -q "qbittorrent/data/incomplete" <<< "${excludes_out}"; then
    printf "Expected qbittorrent/data/incomplete exclusion not found in output"
    return 1
  fi

  printf "Declarative exclusion verified: %s" "$(grep 'qbittorrent/data/incomplete' <<< "${excludes_out}" | head -n 1)"
  return 0
}

test_backup_declarative_stack_priority() {
  source "${REPO_DIR}/.scripts/common.sh"

  local mock_repo
  mock_repo="$(mktemp -d)"

  mkdir -p "${mock_repo}/stack_delta" "${mock_repo}/stack_alpha" "${mock_repo}/stack_beta" "${mock_repo}/stack_gamma" "${mock_repo}/stack_unlabeled"

  cat <<EOF > "${mock_repo}/stack_delta/compose.yml"
services:
  delta:
    image: test
    labels:
      - homelab.stack.priority=10
EOF

  cat <<EOF > "${mock_repo}/stack_alpha/compose.yml"
services:
  alpha:
    image: test
    labels:
      - homelab.stack.priority=10
EOF

  cat <<EOF > "${mock_repo}/stack_beta/compose.yml"
services:
  beta:
    image: test
    labels:
      - homelab.stack.priority=20
EOF

  cat <<EOF > "${mock_repo}/stack_gamma/compose.yml"
services:
  gamma:
    image: test
    labels:
      - homelab.stack.priority=50
EOF

  cat <<EOF > "${mock_repo}/stack_unlabeled/compose.yml"
services:
  unlabeled:
    image: test
EOF

  local actual_order
  actual_order="$(
    REPO_DIR="${mock_repo}"
    discover_stacks >/dev/null 2>&1
    echo "${STACKS[*]}"
  )"
  rm -rf "${mock_repo}"

  local expected="stack_alpha stack_delta stack_beta stack_gamma stack_unlabeled"
  if [[ "${actual_order}" != "${expected}" ]]; then
    printf "Expected priority order '%s', got '%s'" "${expected}" "${actual_order}"
    return 1
  fi

  printf "Inferred priority order from mock containers: %s" "${actual_order}"
  return 0
}

test_backup_declarative_storage_nocow_discovery() {
  source "${REPO_DIR}/.scripts/common.sh"

  local mock_repo
  mock_repo="$(mktemp -d)"

  mkdir -p "${mock_repo}/mock_torrent"
  cat <<'EOF' > "${mock_repo}/mock_torrent/compose.yml"
services:
  mock_client:
    volumes:
      - ${TORRENT_INCOMPLETE_DIR:?See env.example for default.}:/mock_scratch
      - ${MEDIA_DIR:?See env.example for default.}/downloads:/downloads
    labels:
      - homelab.storage.btrfs.nocow=/mock_scratch
EOF

  cat <<'EOF' > "${mock_repo}/mock_torrent/.env"
TORRENT_INCOMPLETE_DIR=/tmp/mock_docker/mock_service/scratch
EOF

  local resolved_paths=()
  while IFS= read -r p; do
    [[ -n "${p}" ]] && resolved_paths+=("${p}")
  done < <(REPO_DIR="${mock_repo}" DOCKER_DATA_DIR="/tmp/mock_docker" MEDIA_DIR="/tmp/mock_media" discover_nocow_storage_paths)
  rm -rf "${mock_repo}"

  local expected="/tmp/mock_docker/mock_service/scratch"
  if [[ "${#resolved_paths[@]}" -ne 1 || "${resolved_paths[0]}" != "${expected}" ]]; then
    printf "Expected stack-level path '%s', got '%s'" "${expected}" "${resolved_paths[*]:-empty}"
    return 1
  fi

  printf "Inferred No-CoW host path from stack-level .env: %s" "${resolved_paths[0]}"
  return 0
}

suite_backup() {
  init_suite "6. Restic Backup & Disaster Recovery Automation"

  run_test test_backup_restic_binary "Verify host restic binary installation and version"
  run_test test_backup_env_config "Verify backup repository and retention environment settings"
  run_test test_backup_systemd_units "Verify systemd backup service and timer unit declarations"
  run_test test_backup_semver_bumping "Verify SemVer auto-bumping logic (major, minor, patch)"
  run_test test_backup_tag_resolution "Verify multi-tag resolution (SemVer, CalVer, custom string)"
  run_test test_backup_declarative_sqlite_discovery "Verify declarative discovery of homelab.backup.sqlite labels"
  run_test test_backup_declarative_exclusion_discovery "Verify declarative resolution of homelab.backup.exclude paths"
  run_test test_backup_declarative_stack_priority "Verify declarative decade stack priority sorting"
  run_test test_backup_declarative_storage_nocow_discovery "Verify declarative resolution of homelab.storage.nocow paths"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_backup
  print_summary
fi
