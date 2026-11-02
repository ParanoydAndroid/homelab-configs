#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/common.sh
# Description:
#   Shared environment primitives, runtime defaults, logging functions, and
#   atomic dotenv manipulation utilities for homelab automation scripts.
# ==============================================================================
set -euo pipefail

# Resolve repository root directory deterministically
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve active non-root homelab user and primary group
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
else
  TARGET_USER="$(stat -c '%U' "${REPO_DIR}")"
fi
TARGET_GROUP="$(id -gn "${TARGET_USER}" 2>/dev/null || echo "admin")"

# ------------------------------------------------------------------------------
# Function: discover_stacks
# Description:
#   Dynamically discovers all active Dockge-compatible stack directories at the
#   repository root. A valid stack is a non-hidden directory containing a
#   'compose.yml' file without a '.disabled' marker.
#
#   Ordering:
#     Applies deterministic bootstrapping precedence: foundational network and
#     database services ('postgres', 'nginx', 'tailscale', 'vpn-bridge') are
#     ordered first, followed alphabetically by remaining application stacks.
#
# Arguments:
#   None.
# Outputs:
#   Populates the global 'STACKS' array.
# Returns:
#   0 if one or more stacks are discovered; 1 if no valid stacks are found.
# ------------------------------------------------------------------------------
discover_stacks() {
  local found_stacks=()
  local dir stack_name

  # Search for all compose.yml files exactly one directory deep under REPO_DIR
  for dir in "${REPO_DIR}"/*/compose.yml; do
    [[ -f "${dir}" ]] || continue
    stack_name="$(basename "$(dirname "${dir}")")"

    # Ignore hidden directories or explicitly disabled stacks
    if [[ "${stack_name}" =~ ^\. ]] || [[ -f "${REPO_DIR}/${stack_name}/.disabled" ]]; then
      continue
    fi
    found_stacks+=("${stack_name}")
  done

  # Foundational priority order
  local priority_order=("postgres" "nginx" "tailscale" "vpn-bridge")
  local ordered_stacks=()
  local remaining_stacks=()

  # Add priority stacks first if they exist
  for p in "${priority_order[@]}"; do
    for s in "${found_stacks[@]}"; do
      if [[ "${s}" == "${p}" ]]; then
        ordered_stacks+=("${s}")
        break
      fi
    done
  done

  # Collect non-priority stacks
  for s in "${found_stacks[@]}"; do
    local is_priority=0
    for p in "${priority_order[@]}"; do
      if [[ "${s}" == "${p}" ]]; then
        is_priority=1
        break
      fi
    done
    if [[ "${is_priority}" -eq 0 ]]; then
      remaining_stacks+=("${s}")
    fi
  done

  # Sort remaining stacks alphabetically
  if [[ ${#remaining_stacks[@]} -gt 0 ]]; then
    local sorted_remaining=()
    while IFS= read -r line; do
      [[ -n "${line}" ]] && sorted_remaining+=("${line}")
    done < <(printf "%s\n" "${remaining_stacks[@]}" | sort)
    ordered_stacks+=("${sorted_remaining[@]}")
  fi

  STACKS=("${ordered_stacks[@]}")
  [[ ${#STACKS[@]} -gt 0 ]]
}

# ------------------------------------------------------------------------------
# Function: is_stack_enabled
# Description:
#   Checks whether a given stack is active and discovered in the current repository.
# Arguments:
#   $1 (stack_name) - Directory name of the stack (e.g. "postgres", "tandoor").
# Returns:
#   0 if enabled/present; 1 if omitted, disabled, or not found.
# ------------------------------------------------------------------------------
is_stack_enabled() {
  local target="$1"
  for s in "${STACKS[@]}"; do
    if [[ "${s}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

# Dynamically discovered list of Docker Compose stack directories
STACKS=()
discover_stacks || true

# Global runtime flags
OVERWRITE_MODE="${OVERWRITE_MODE:-prompt}"
BACKUP_TAG_ENABLED="${BACKUP_TAG_ENABLED:-0}"
BACKUP_TAG_NAME="${BACKUP_TAG_NAME:-}"
BACKUP_COMMIT_MSG="${BACKUP_COMMIT_MSG:-}"

# Global environment variables synchronized from root .env to stacks and Dockge
GLOBAL_ENV_VARS=(
  "DOCKER_DATA_DIR"
  "MEDIA_DIR"
  "DOCKGE_DIR"
  "DOCKGE_STACKS_DIR"
  "PUID"
  "PGID"
  "TZ"
  "EXTERNAL_NPM_SUBNET"
  "EXTERNAL_NPM_GATEWAY"
  "EXTERNAL_NPM_PARENT"
  "NPM_IPV4_ADDRESS"
  "TAILSCALE_IPV4_ADDRESS"
)

# ------------------------------------------------------------------------------
# Function: log_info
# Description: Prints informational status message to stdout.
# ------------------------------------------------------------------------------
log_info() {
  printf "[INFO] %s\n" "$*"
}

# ------------------------------------------------------------------------------
# Function: log_warn
# Description: Prints warning message to stderr.
# ------------------------------------------------------------------------------
log_warn() {
  printf "[WARN] %s\n" "$*" >&2
}

# ------------------------------------------------------------------------------
# Function: log_error
# Description: Prints error message to stderr.
# ------------------------------------------------------------------------------
log_error() {
  printf "[ERROR] %s\n" "$*" >&2
}

# ------------------------------------------------------------------------------
# Function: upsert_env_var
# Description:
#   Atomically inserts or updates a single KEY=VALUE assignment inside a dotenv
#   file while preserving all other lines, comments, and file structure. Uses awk
#   with '-v' variables to avoid regex delimiter corruption on complex values.
# Arguments:
#   $1 (file) - Path to target .env file (created if non-existent).
#   $2 (key)  - Environment variable name.
#   $3 (val)  - Environment variable value.
# ------------------------------------------------------------------------------
upsert_env_var() {
  local file="$1"
  local key="$2"
  local val="$3"
  touch "${file}"

  awk -v k="${key}" -v v="${val}" '
    BEGIN { found = 0 }
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "${file}" > "${file}.tmp" && mv -f "${file}.tmp" "${file}"
}

# ------------------------------------------------------------------------------
# Function: get_env_var
# Description:
#   Reads the current value of a KEY from a dotenv file, stripping optional quotes.
# Arguments:
#   $1 (file) - Path to .env file.
#   $2 (key)  - Variable name to look up.
# Outputs:
#   Prints resolved variable value to stdout, or empty string if not found.
# ------------------------------------------------------------------------------
get_env_var() {
  local file="$1"
  local key="$2"
  [[ -f "${file}" ]] || return 0

  awk -v k="${key}" '
    index($0, k "=") == 1 {
      val = substr($0, length(k) + 2)
      sub(/^["'"'"']/, "", val)
      sub(/["'"'"']$/, "", val)
      print val
      exit
    }
  ' "${file}"
}
