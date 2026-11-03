#!/usr/bin/env bash
# ==============================================================================
# Script Name: homelab.sh
# Description:
#   Primary lifecycle, configuration synchronization, and backup automation CLI
#   for the UGREEN NAS homelab environment (nas.home).
#
# Architecture:
#   Serves as the high-level orchestration entrypoint. Specialized subroutines
#   are organized modularly under .scripts/ (common, env-tools, system, backup)
#   and .tests/ (modular smoke & regression test suites).
#
# Subcommands:
#   setup           Initialize .env files, apply NAS OS fixes, create networks,
#                   and start all stacks
#   startup         Non-interactive boot hook to start networks, Dockge, and
#                   stacks in dependency order (used by systemd)
#   backup          Snapshot persistent volumes to Restic repository, commit
#                   git changes, apply SemVer/CalVer/custom tags, and archive .env
#   snapshots       List historical Restic backup snapshots
#   restore         Restore volume state from Restic snapshot
#   test [suite]    Run modular smoke and regression tests (suites: containers,
#                   direct, routing, interconnect, security)
#
# Usage:
#   sudo ./homelab.sh setup
#   ./homelab.sh startup
#   sudo ./homelab.sh backup [-t <type|name>] [-m <message>]
#   ./homelab.sh snapshots
#   sudo ./homelab.sh restore [snapshot_id] [service_name] [-f]
#   ./homelab.sh test [suite] [test_name]
# ==============================================================================
set -euo pipefail

# Resolve script directory and source library modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/.scripts/common.sh"
source "${SCRIPT_DIR}/.scripts/env-tools.sh"
source "${SCRIPT_DIR}/.scripts/system.sh"
source "${SCRIPT_DIR}/.scripts/backup.sh"

# ------------------------------------------------------------------------------
# Function: setup_homelab
# Description:
#   End-to-end host and service convergence workflow:
#     1. Remediates UGREEN NAS OS GODEBUG=tlskyber=0 defect.
#     2. Initializes and syncs all .env files.
#     3. Creates 'homelab' bridge and 'external_npm' macvlan networks.
#     4. Ensures Dockge orchestrator compose.yml is deployed.
#     5. Starts Dockge orchestrator and all service stacks in dependency order.
# ------------------------------------------------------------------------------
setup_homelab() {
  remediate_godebug
  init_and_sync_env
  ensure_networks

  # Ensure ~/services convenience symlink exists for non-root target user
  if [[ -n "${TARGET_USER:-}" && "${TARGET_USER}" != "root" ]]; then
    local target_home
    target_home="$(eval echo "~${TARGET_USER}")"
    if [[ -d "${target_home}" && ! -e "${target_home}/services" ]]; then
      log_info "Creating convenience symlink ${target_home}/services -> ${REPO_DIR}..."
      ln -sfn "${REPO_DIR}" "${target_home}/services"
      chown -h "${TARGET_USER}:${TARGET_GROUP}" "${target_home}/services" 2>/dev/null || true
    fi
  fi

  log_info "Ensuring Dockge orchestrator compose is present (${DOCKGE_DIR}/compose.yml)..."
  mkdir -p "${DOCKGE_DIR}"
  if [[ -f "${REPO_DIR}/.configs/dockge/compose.yml" ]]; then
    cp -p "${REPO_DIR}/.configs/dockge/compose.yml" "${DOCKGE_DIR}/compose.yml"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${DOCKGE_DIR}/compose.yml" 2>/dev/null || true
  fi

  # Deploy qBittorrent port forwarding and anti-thrashing preference script
  if is_service_enabled "wireguard-pia" || is_service_enabled "qbittorrent"; then
    local qbt_data_dir="${DOCKER_DATA_DIR}/qbittorrentvpn/data"
    if [[ -f "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh" ]]; then
      log_info "Ensuring qBittorrent port sync script is present (${qbt_data_dir}/set-qbt-port.sh)..."
      mkdir -p "${qbt_data_dir}"
      cp -p "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh" "${qbt_data_dir}/set-qbt-port.sh"
      chmod +x "${qbt_data_dir}/set-qbt-port.sh"
      chown "${TARGET_USER}:${TARGET_GROUP}" "${qbt_data_dir}/set-qbt-port.sh" 2>/dev/null || true
    fi

    # Ensure qBittorrent scratch incomplete directory exists with write permissions
    local qbt_incomplete_dir="${qbt_data_dir}/incomplete"
    if [[ -d "${qbt_incomplete_dir}" ]]; then
      chmod 775 "${qbt_incomplete_dir}" 2>/dev/null || true
      chown "${TARGET_USER}:${TARGET_GROUP}" "${qbt_incomplete_dir}" 2>/dev/null || true
    fi
  fi

  # Deploy Caddyfile if caddy service is enabled
  if is_service_enabled "caddy"; then
    local caddy_data_dir="${DOCKER_DATA_DIR}/caddy"
    if [[ -f "${REPO_DIR}/.configs/caddy/Caddyfile" ]]; then
      log_info "Ensuring Caddyfile is present (${caddy_data_dir}/Caddyfile)..."
      mkdir -p "${caddy_data_dir}"
      cp -p "${REPO_DIR}/.configs/caddy/Caddyfile" "${caddy_data_dir}/Caddyfile"
      chown "${TARGET_USER}:${TARGET_GROUP}" "${caddy_data_dir}/Caddyfile" 2>/dev/null || true
    fi
  fi

  log_info "Starting Dockge orchestrator (${DOCKGE_DIR}/compose.yml)..."
  docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d

  local stack
  for stack in "${STACKS[@]}"; do
    if [[ -f "${REPO_DIR}/${stack}/compose.yml" ]]; then
      log_info "Starting stack '${stack}'..."
      (
        cd "${REPO_DIR}/${stack}"
        docker compose up -d
      )
    fi
  done

  log_info "All homelab stacks started successfully."
}

# ------------------------------------------------------------------------------
# Function: startup_homelab
# Description:
#   Non-interactive boot hook designed for systemd execution on host boot:
#     1. Initializes root .env and exports variables.
#     2. Waits for storage volume mount (${DOCKER_DATA_DIR}).
#     3. Ensures external Docker networks exist.
#     4. Starts Dockge orchestrator and stacks with database readiness verification.
# ------------------------------------------------------------------------------
startup_homelab() {
  init_and_sync_env
  log_info "Initiating homelab boot orchestration..."

  # Step 1: Wait for storage volume mount
  local timeout=60
  while [[ ! -d "${DOCKER_DATA_DIR}" ]] && (( timeout > 0 )); do
    log_info "Waiting for ${DOCKER_DATA_DIR} to mount (${timeout}s remaining)..."
    sleep 2
    (( timeout -= 2 )) || true
  done

  if [[ ! -d "${DOCKER_DATA_DIR}" ]]; then
    log_error "Timeout waiting for storage directory: ${DOCKER_DATA_DIR}"
    exit 1
  fi

  # Step 2: Ensure Docker networks
  ensure_networks

  # Step 3: Start Dockge orchestrator
  if [[ -f "${DOCKGE_DIR}/compose.yml" ]]; then
    log_info "Starting Dockge orchestrator (${DOCKGE_DIR}/compose.yml)..."
    docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d
  fi

  # Step 4: Start stacks in dependency order
  local stack
  for stack in "${STACKS[@]}"; do
    if [[ -f "${REPO_DIR}/${stack}/compose.yml" ]]; then
      log_info "Bootstrapping stack '${stack}'..."
      (
        cd "${REPO_DIR}/${stack}"
        docker compose up -d
      )
    fi
  done

  log_info "Homelab boot orchestration completed successfully."
}

# ------------------------------------------------------------------------------
# Function: test_homelab
# Description:
#   Delegates execution to the modular test suite runner in '.tests/run.sh'.
# Arguments:
#   $@ - Optional suite name (containers, direct, routing, interconnect, security)
#        or specific test function name.
# ------------------------------------------------------------------------------
test_homelab() {
  "${REPO_DIR}/.tests/run.sh" "$@"
}

# ------------------------------------------------------------------------------
# Function: usage
# Description: Prints CLI help and usage documentation to stdout.
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <subcommand> [options]

Subcommands:
  setup                    Initialize .env files, apply NAS OS fixes, create networks, and start all stacks
  startup                  Non-interactive boot hook to start networks, Dockge, and stacks in dependency order
  backup                   Snapshot persistent volumes to Restic repository, stage DB dumps, and archive .env
  snapshots                List historical Restic backup snapshots
  restore [snap] [svc]     Restore persistent volume state from Restic snapshot (optional specific service)
  test [suite]             Run modular smoke and regression tests (suites: containers, direct, routing, interconnect, security)

Options for backup:
  -t, --tag [type|name]    Repeatable tag request: SemVer-major, SemVer-minor, SemVer-patch,
                           CalVer (default if omitted), or any custom tag string
  -m, --message <msg>      Custom git commit message for repository changes

Options for restore:
  -f, --force              Bypass active container checks and overwrite prompts
EOF
}

# ------------------------------------------------------------------------------
# Function: main
# Description: Argument parsing and subcommand dispatching.
# ------------------------------------------------------------------------------
main() {
  local subcmd="${1:-}"
  shift || true

  # Subcommands with passthrough arguments
  if [[ "${subcmd}" == "test" ]]; then
    test_homelab "$@"
    return $?
  fi

  if [[ "${subcmd}" == "restore" ]]; then
    restore_homelab "$@"
    return $?
  fi

  BACKUP_TAG_REQUESTS=()
  BACKUP_COMMIT_MSG=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--tag)
        if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
          BACKUP_TAG_REQUESTS+=("$2")
          shift
        else
          BACKUP_TAG_REQUESTS+=("calver")
        fi
        ;;
      -m|--message)
        if [[ $# -lt 2 ]]; then
          log_error "Option '$1' requires a commit message argument."
          usage
          exit 1
        fi
        BACKUP_COMMIT_MSG="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done

  case "${subcmd}" in
    setup) setup_homelab ;;
    startup) startup_homelab ;;
    backup) backup_homelab ;;
    snapshots) snapshots_homelab ;;
    -h|--help|"") usage; exit 0 ;;
    *) log_error "Unknown subcommand: ${subcmd}"; usage; exit 1 ;;
  esac
}

main "$@"
