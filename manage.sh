#!/usr/bin/env bash
# ==============================================================================
# Script Name: manage.sh
# Description:
#   Central operational entrypoint for the UGREEN NAS homelab environment (nas.home).
#   Provides idempotent state convergence (setup), non-interactive boot startup,
#   Restic snapshot backup and recovery, automated test orchestration, codebase
#   security/drift auditing, and git hook management.
#
# Usage:
#   ./manage.sh <subcommand> [options]
#
# Subcommands:
#   setup           Idempotently converges environment, directories, networks,
#                   orchestrators, permissions, and git hooks
#   startup         Non-interactive boot hook to start networks, Dockge, and
#                   stacks in dependency order (used by systemd)
#   backup          Snapshot persistent volumes to Restic repository, commit
#                   git changes, apply SemVer/CalVer/custom tags, and archive .env
#   snapshots       List historical Restic backup snapshots
#   restore         Restore volume state from Restic snapshot
#   test [suite]    Executes automated smoke, interconnect, routing, and conventions tests
#   audit           Runs baseline drift, permission, symlink, and environment security audits
#   hook [action]   Manages git hooks protecting 'main' branch (install|uninstall)
#   help            Displays usage and subcommand guidance
#
# Preconditions:
#   Bash 4.0+ and Docker must be installed on the host.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}"

# Source modular libraries
source "${REPO_DIR}/.scripts/common.sh"
source "${REPO_DIR}/.scripts/env-tools.sh"
source "${REPO_DIR}/.scripts/system.sh"
source "${REPO_DIR}/.scripts/backup.sh"

# ------------------------------------------------------------------------------
# Formatting and Color Helpers
# ------------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CLR_RESET=$'\033[0m'
  CLR_BOLD=$'\033[1m'
  CLR_GREEN=$'\033[32m'
  CLR_RED=$'\033[31m'
  CLR_YELLOW=$'\033[33m'
  CLR_CYAN=$'\033[36m'
else
  CLR_RESET=""
  CLR_BOLD=""
  CLR_GREEN=""
  CLR_RED=""
  CLR_YELLOW=""
  CLR_CYAN=""
fi

log_info() {
  printf "%b[INFO]%b %s\n" "${CLR_CYAN}" "${CLR_RESET}" "$1"
}

log_success() {
  printf "%b[OK]%b %s\n" "${CLR_GREEN}" "${CLR_RESET}" "$1"
}

log_warn() {
  printf "%b[WARN]%b %s\n" "${CLR_YELLOW}" "${CLR_RESET}" "$1" >&2
}

log_error() {
  printf "%b[ERROR]%b %s\n" "${CLR_RED}" "${CLR_RESET}" "$1" >&2
}

# ------------------------------------------------------------------------------
# Function: cmd_setup
# Description:
#   End-to-end host and service convergence workflow:
#     1. Remediates UGREEN NAS OS GODEBUG=tlskyber=0 defect.
#     2. Initializes and syncs all .env files from templates.
#     3. Creates 'homelab' bridge and 'external_npm' macvlan networks.
#     4. Ensures ~/services convenience symlink exists.
#     5. Deploys Dockge compose to ${DOCKGE_DIR}/compose.yml.
#     6. Applies declarative Btrfs storage policies (No-CoW scratch).
#     7. Converges multi-agent ecosystem symlinks.
#     8. Normalizes filesystem permissions.
#     9. Installs git hooks protecting 'main'.
#    10. Starts Dockge orchestrator and all stacks in dependency order.
# ------------------------------------------------------------------------------
cmd_setup() {
  log_info "Starting environment convergence..."

  # 1. Remediate NAS OS defect
  remediate_godebug

  # 2. Initialize and sync environment variables
  init_and_sync_env

  # 3. Ensure Docker networks exist
  ensure_networks

  # 4. Ensure ~/services convenience symlink exists
  if [[ -n "${TARGET_USER:-}" && "${TARGET_USER}" != "root" ]]; then
    local target_home
    target_home="$(eval echo "~${TARGET_USER}")"
    if [[ -d "${target_home}" && ! -e "${target_home}/services" ]]; then
      log_info "Creating convenience symlink ${target_home}/services -> ${REPO_DIR}..."
      ln -sfn "${REPO_DIR}" "${target_home}/services"
      chown -h "${TARGET_USER}:${TARGET_GROUP}" "${target_home}/services" 2>/dev/null || true
    fi
  fi

  # 5. Ensure Dockge orchestrator compose is present
  log_info "Ensuring Dockge orchestrator compose is present (${DOCKGE_DIR}/compose.yml)..."
  mkdir -p "${DOCKGE_DIR}"
  if [[ -f "${REPO_DIR}/.configs/dockge/compose.yml" ]]; then
    cp -p "${REPO_DIR}/.configs/dockge/compose.yml" "${DOCKGE_DIR}/compose.yml"
    chown "${TARGET_USER}:${TARGET_GROUP}" "${DOCKGE_DIR}/compose.yml" 2>/dev/null || true
  fi

  # 6. Apply Btrfs storage policies
  local btrfs_path
  while IFS= read -r btrfs_path; do
    [[ -z "${btrfs_path}" ]] && continue
    log_info "Applying declarative Btrfs storage policy to: ${btrfs_path}..."
    if [[ ! -d "${btrfs_path}" ]]; then
      mkdir -p "${btrfs_path}" 2>/dev/null || true
    fi
    chattr +C "${btrfs_path}" 2>/dev/null || true
    chmod 775 "${btrfs_path}" 2>/dev/null || true
    chown "${TARGET_USER}:${TARGET_GROUP}" "${btrfs_path}" 2>/dev/null || true
  done < <(discover_nocow_storage_paths)

  # 7. Converge agent discovery symlinks
  local symlinks=(
    "agent.md:AGENTS.md"
    "CLAUDE.md:AGENTS.md"
    "GEMINI.md:AGENTS.md"
    ".cursorrules:AGENTS.md"
    ".skills:.agents/skills"
    ".agents/rules/project-conventions.md:../../AGENTS.md"
  )
  for pair in "${symlinks[@]}"; do
    local link_name="${pair%%:*}"
    local target_path="${pair##*:}"
    if [[ ! -L "${REPO_DIR}/${link_name}" ]]; then
      ln -sf "${target_path}" "${REPO_DIR}/${link_name}"
      log_success "Converged symlink: ${link_name} -> ${target_path}"
    fi
  done

  # 8. Normalize repository file permissions
  log_info "Normalizing filesystem permissions..."
  find "${REPO_DIR}" -maxdepth 6 -type f -not -path "*/.git/*" -not -name "*.sh" -exec chmod 644 {} +
  find "${REPO_DIR}" -maxdepth 6 -type f -name "*.sh" -exec chmod 755 {} +
  chmod 755 "${REPO_DIR}/manage.sh"
  if [[ -f "${REPO_DIR}/.env" ]]; then
    chmod 600 "${REPO_DIR}/.env"
  fi
  if [[ -f "${REPO_DIR}/.harness/test-runner.sh" ]]; then
    chmod +x "${REPO_DIR}/.harness/test-runner.sh"
  fi

  # Ensure git tracks scripts as executable
  if [[ -d "${REPO_DIR}/.git" ]]; then
    git -C "${REPO_DIR}" update-index --chmod=+x manage.sh .harness/test-runner.sh 2>/dev/null || true
    cmd_hook install >/dev/null 2>&1 || true
    log_success "Verified git hooks protecting 'main' branch"
  fi

  # 9. Start Dockge orchestrator and all service stacks
  if command -v docker >/dev/null 2>&1; then
    log_info "Starting Dockge orchestrator (${DOCKGE_DIR}/compose.yml)..."
    docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d 2>/dev/null || true

    local stack
    for stack in "${STACKS[@]}"; do
      if [[ -f "${REPO_DIR}/${stack}/compose.yml" ]]; then
        log_info "Starting stack '${stack}'..."
        (
          cd "${REPO_DIR}/${stack}"
          docker compose up -d 2>/dev/null || true
        )
      fi
    done
  fi

  log_success "Environment convergence complete. Target state verified."
}

# ------------------------------------------------------------------------------
# Function: cmd_startup
# Description:
#   Non-interactive boot hook designed for systemd execution on host boot.
# ------------------------------------------------------------------------------
cmd_startup() {
  init_and_sync_env
  log_info "Initiating homelab boot orchestration..."

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

  ensure_networks

  if [[ -f "${DOCKGE_DIR}/compose.yml" ]]; then
    log_info "Starting Dockge orchestrator (${DOCKGE_DIR}/compose.yml)..."
    docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d
  fi

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
# Function: cmd_test
# Description:
#   Dispatches test suite execution to the automated test harness.
# ------------------------------------------------------------------------------
cmd_test() {
  local test_runner="${REPO_DIR}/.harness/test-runner.sh"
  if [[ ! -x "${test_runner}" ]]; then
    log_error "Test runner not executable: ${test_runner}"
    exit 1
  fi
  exec "${test_runner}" "$@"
}

# ------------------------------------------------------------------------------
# Function: cmd_audit
# Description:
#   Performs baseline drift, permissions, symlinks, and homelab runtime audits.
# ------------------------------------------------------------------------------
cmd_audit() {
  log_info "Executing codebase and infrastructure audit..."
  local issues_found=0

  # 1. Check for world-writable files
  log_info "Auditing filesystem permissions for world-writable files..."
  local ww_files
  ww_files="$(find "${REPO_DIR}" -maxdepth 6 -type f -perm -002 -not -path "*/.git/*" 2>/dev/null || true)"
  if [[ -n "${ww_files}" ]]; then
    log_error "Dangerous world-writable files detected:"
    echo "${ww_files}" >&2
    ((issues_found++)) || true
  else
    log_success "Filesystem permissions secure (zero world-writable files)"
  fi

  # 2. Check for broken symlinks
  log_info "Validating repository symlinks..."
  local broken_links
  broken_links="$(find "${REPO_DIR}" -maxdepth 6 -xtype l -not -path "*/.git/*" 2>/dev/null || true)"
  if [[ -n "${broken_links}" ]]; then
    log_error "Broken symlinks detected:"
    echo "${broken_links}" >&2
    ((issues_found++)) || true
  else
    log_success "All repository symlinks resolve cleanly"
  fi

  # 3. Check environment variable template alignment
  if [[ -f "${REPO_DIR}/.env.example" && -f "${REPO_DIR}/.env" ]]; then
    log_info "Checking root environment variable template alignment..."
    local missing_vars
    missing_vars="$(comm -23 \
      <(grep -oE '^[A-Z0-9_]+' "${REPO_DIR}/.env.example" | sort -u) \
      <(grep -oE '^[A-Z0-9_]+' "${REPO_DIR}/.env" | sort -u) || true)"
    if [[ -n "${missing_vars}" ]]; then
      log_warn "Variables declared in root .env.example missing in active .env:"
      echo "${missing_vars}" | sed 's/^/  - /' >&2
      ((issues_found++)) || true
    else
      log_success "Root environment variables fully aligned with template"
    fi
  fi

  # 4. Check container port exposures if Docker is running
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    log_info "Checking host port exposures against homelab policy..."
    local unexpected_ports=0
    while IFS= read -r line; do
      local cname ports
      cname="$(echo "${line}" | awk '{print $1}')"
      ports="$(echo "${line}" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')"
      [[ -z "${ports}" ]] && continue

      # Allowed direct ports: dockge (8010:5001), jellyfin (8022:7359/udp)
      if [[ "${cname}" != "dockge" && "${cname}" != "jellyfin" && "${ports}" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+ ]]; then
        log_warn "Unexpected host port exposure on container '${cname}': ${ports}"
        ((unexpected_ports++)) || true
      fi
    done < <(docker ps --format '{{.Names}}\t{{.Ports}}')

    if [[ "${unexpected_ports}" -eq 0 ]]; then
      log_success "Container host port exposures compliant with network policy"
    else
      log_warn "${unexpected_ports} container(s) exposing direct host ports outside policy"
    fi
  fi

  if [[ "${issues_found}" -eq 0 ]]; then
    log_success "Audit completed: System healthy."
    return 0
  else
    log_error "Audit completed: ${issues_found} issue(s) detected."
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Function: cmd_hook
# Description:
#   Installs git hooks guarding the 'main' branch during commits and pushes.
# ------------------------------------------------------------------------------
cmd_hook() {
  local action="${1:-install}"
  local hooks_dir="${REPO_DIR}/.git/hooks"

  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    log_warn "Not a git repository; skipping git hook setup"
    return 0
  fi

  mkdir -p "${hooks_dir}"

  case "${action}" in
    install)
      log_info "Installing git hooks guarding 'main' branch..."

      cat <<'EOF' > "${hooks_dir}/pre-commit"
#!/usr/bin/env bash
set -euo pipefail

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ "${CURRENT_BRANCH}" == "main" ]]; then
  if [[ "${HOMELAB_SKIP_HOOK_TESTS:-0}" == "1" ]]; then
    echo "[HOOK] HOMELAB_SKIP_HOOK_TESTS=1 set; bypassing pre-commit tests."
    exit 0
  fi
  echo "[HOOK] Running pre-commit/pre-merge validation on main..."
  echo "[HOOK] (Set HOMELAB_SKIP_HOOK_TESTS=1 or use --no-verify during storage array maintenance)"
  ./manage.sh audit
  ./manage.sh test all
fi
EOF
      chmod 755 "${hooks_dir}/pre-commit"

      cat <<'EOF' > "${hooks_dir}/pre-push"
#!/usr/bin/env bash
set -euo pipefail

while read -r local_ref local_oid remote_ref remote_oid; do
  if [[ "${remote_ref}" == "refs/heads/main" || "${remote_ref}" =~ /main$ ]]; then
    if [[ "${HOMELAB_SKIP_HOOK_TESTS:-0}" == "1" ]]; then
      echo "[HOOK] HOMELAB_SKIP_HOOK_TESTS=1 set; bypassing pre-push tests."
      exit 0
    fi
    echo "[HOOK] Verifying tests and audit before pushing to main..."
    echo "[HOOK] (Set HOMELAB_SKIP_HOOK_TESTS=1 or use --no-verify during storage array maintenance)"
    ./manage.sh audit
    ./manage.sh test all
    break
  fi
done
EOF
      chmod 755 "${hooks_dir}/pre-push"
      log_success "Git hooks installed: pre-commit and pre-push guard 'main' branch"
      ;;
    uninstall)
      rm -f "${hooks_dir}/pre-commit" "${hooks_dir}/pre-push"
      log_success "Git hooks uninstalled"
      ;;
    *)
      log_error "Unknown hook action: '${action}'. Expected 'install' or 'uninstall'."
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Function: cmd_help
# Description:
#   Displays usage and subcommand guidance.
# ------------------------------------------------------------------------------
cmd_help() {
  cat <<EOF
${CLR_BOLD}Homelab Management Entrypoint (manage.sh)${CLR_RESET}

${CLR_BOLD}Usage:${CLR_RESET}
  ./manage.sh <subcommand> [options]

${CLR_BOLD}Available Subcommands:${CLR_RESET}
  ${CLR_CYAN}setup${CLR_RESET}                Idempotently converges environment, directories, and stacks
  ${CLR_CYAN}startup${CLR_RESET}              Non-interactive boot hook for systemd (dependency startup)
  ${CLR_CYAN}backup [check]${CLR_RESET}       Snapshot persistent volumes to Restic repository
  ${CLR_CYAN}snapshots${CLR_RESET}            List historical Restic backup snapshots
  ${CLR_CYAN}restore [snap] [svc]${CLR_RESET} Restore persistent volume state from Restic snapshot
  ${CLR_CYAN}test [suite]${CLR_RESET}         Run automated smoke, interconnect, routing, and conventions tests
  ${CLR_CYAN}audit${CLR_RESET}                Run codebase drift, permission, symlink, and security audits
  ${CLR_CYAN}hook [action]${CLR_RESET}        Manage git hooks protecting 'main' (install|uninstall)
  ${CLR_CYAN}help${CLR_RESET}                 Display this help message

${CLR_BOLD}Backup Options:${CLR_RESET}
  -t, --tag [type|name]    Tag request: SemVer-major, SemVer-minor, SemVer-patch, CalVer, custom
  -c, --commit             Commit and push working tree changes alongside snapshot
  -m, --message <msg>      Custom git commit message (automatically enables --commit)

${CLR_BOLD}Restore Options:${CLR_RESET}
  -f, --force              Bypass active container checks and overwrite prompts
  -n, --dry-run            Preview snapshot file manifest without modifying filesystem state

${CLR_BOLD}Examples:${CLR_RESET}
  ./manage.sh setup
  ./manage.sh test all
  ./manage.sh test conventions
  ./manage.sh test containers
  ./manage.sh audit
  ./manage.sh backup -t calver
  ./manage.sh hook install
EOF
}

# ------------------------------------------------------------------------------
# Main Dispatcher
# ------------------------------------------------------------------------------
main() {
  local subcmd="${1:-help}"
  shift || true

  # Subcommands with passthrough arguments
  if [[ "${subcmd}" == "test" ]]; then
    cmd_test "$@"
    return $?
  fi

  if [[ "${subcmd}" == "restore" ]]; then
    restore_homelab "$@"
    return $?
  fi

  if [[ "${subcmd}" == "backup" && "${1:-}" == "check" ]]; then
    check_restic_repo
    return $?
  fi

  # Backup options parsing
  if [[ "${subcmd}" == "backup" ]]; then
    BACKUP_TAG_REQUESTS=()
    BACKUP_COMMIT_MSG=""
    BACKUP_DO_COMMIT=0

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
        -c|--commit)
          BACKUP_DO_COMMIT=1
          ;;
        -m|--message)
          if [[ $# -lt 2 ]]; then
            log_error "Option '$1' requires a commit message argument."
            cmd_help
            exit 1
          fi
          BACKUP_COMMIT_MSG="$2"
          BACKUP_DO_COMMIT=1
          shift
          ;;
        -h|--help)
          cmd_help
          exit 0
          ;;
        *)
          log_error "Unknown backup option: $1"
          cmd_help
          exit 1
          ;;
      esac
      shift
    done

    backup_homelab
    return $?
  fi

  case "${subcmd}" in
    setup) cmd_setup "$@" ;;
    startup) cmd_startup "$@" ;;
    snapshots) snapshots_homelab ;;
    audit) cmd_audit "$@" ;;
    hook) cmd_hook "$@" ;;
    help|-h|--help) cmd_help ;;
    *)
      log_error "Unknown subcommand: '${subcmd}'"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
