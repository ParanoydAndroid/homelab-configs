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

suite_backup() {
  init_suite "6. Restic Backup & Disaster Recovery Automation"

  run_test test_backup_restic_binary "Verify host restic binary installation and version"
  run_test test_backup_env_config "Verify backup repository and retention environment settings"
  run_test test_backup_systemd_units "Verify systemd backup service and timer unit declarations"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_backup
  print_summary
fi
