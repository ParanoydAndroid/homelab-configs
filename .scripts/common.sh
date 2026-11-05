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
# Function: discover_services
# Description:
#   Parses all 'compose.yml' files across non-hidden root directories to discover
#   active, enabled services. A service is enabled if declared and uncommented
#   under the 'services:' block. Captures both top-level service identifiers
#   (e.g. 'qbittorrent', 'vpn') and container names ('container_name: <name>').
# Outputs:
#   Populates the global 'ENABLED_SERVICES' array.
# Returns:
#   0 if one or more services are discovered; 1 otherwise.
# ------------------------------------------------------------------------------
discover_services() {
  ENABLED_SERVICES=()
  local compose_file

  for compose_file in "${REPO_DIR}"/*/compose.yml; do
    [[ -f "${compose_file}" ]] || continue
    local stack_dir
    stack_dir="$(basename "$(dirname "${compose_file}")")"
    [[ "${stack_dir}" =~ ^\. ]] && continue

    while IFS= read -r svc; do
      [[ -n "${svc}" ]] && ENABLED_SERVICES+=("${svc}")
    done < <(awk '
      /^services:/ { in_services=1; next }
      /^[^ #[:space:]]/ { in_services=0 }
      in_services && /^  [a-zA-Z0-9_-]+:/ && !/^  #/ {
        svc=$1; sub(/:.*/, "", svc); if (svc != "") print svc
      }
      in_services && /^[[:space:]]*container_name:[[:space:]]*/ && !/^[[:space:]]*#/ {
        cn=$0
        sub(/^[[:space:]]*container_name:[[:space:]]*/, "", cn)
        sub(/[[:space:]]*#.*/, "", cn)
        gsub(/["'\'' ]/, "", cn)
        if (cn != "") print cn
      }
    ' "${compose_file}")
  done

  [[ ${#ENABLED_SERVICES[@]} -gt 0 ]]
}

# ------------------------------------------------------------------------------
# Function: is_service_enabled
# Description:
#   Checks whether a given service or container is defined and enabled in any
#   active stack compose.yml.
# Arguments:
#   $1 (service_name) - Service key or container name (e.g. "seerr", "postgresql").
# Returns:
#   0 if enabled; 1 if omitted, commented out, or disabled.
# ------------------------------------------------------------------------------
is_service_enabled() {
  local target="$1"
  local s
  for s in "${ENABLED_SERVICES[@]}"; do
    if [[ "${s}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------------------------
# Function: discover_stacks
# Description:
#   Dynamically discovers all active Dockge-compatible stack directories at the
#   repository root. A stack is active as a derived consequence of containing
#   at least one enabled service in its 'compose.yml'.
#
#   Ordering:
#     Applies deterministic bootstrapping precedence across the 6 canonical stacks:
#     'productivity', 'ingress', 'mesh', 'dashboard', 'media', 'torrent'.
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
  local compose_file stack_name

  # Search for all compose.yml files exactly one directory deep under REPO_DIR
  for compose_file in "${REPO_DIR}"/*/compose.yml; do
    [[ -f "${compose_file}" ]] || continue
    stack_name="$(basename "$(dirname "${compose_file}")")"

    # Ignore hidden directories
    [[ "${stack_name}" =~ ^\. ]] && continue

    # A stack is active only if it has at least one active service declared
    local has_services=0
    if awk '
      /^services:/ { in_services=1; next }
      /^[^ #[:space:]]/ { in_services=0 }
      in_services && /^  [a-zA-Z0-9_-]+:/ && !/^  #/ { has_services=1; exit }
      END { exit (has_services ? 0 : 1) }
    ' "${compose_file}"; then
      has_services=1
    fi

    if [[ "${has_services}" -eq 1 ]]; then
      found_stacks+=("${stack_name}")
    fi
  done

  # Sort stacks dynamically by declarative priority label 'homelab.stack.priority',
  # defaulting to 90 for unspecified or ad-hoc stacks, with secondary alphabetical sorting.
  local priority_entries=()
  for s in "${found_stacks[@]}"; do
    local compose_path="${REPO_DIR}/${s}/compose.yml"
    local prio
    prio="$(awk -F'homelab.stack.priority=' '/homelab\.stack\.priority=[0-9]+/ { split($2, a, /[^0-9]/); print a[1]; exit }' "${compose_path}")"
    prio="${prio:-90}"
    priority_entries+=("$(printf "%03d %s" "${prio}" "${s}")")
  done

  local ordered_stacks=()
  if [[ ${#priority_entries[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && ordered_stacks+=("${line#* }")
    done < <(printf "%s\n" "${priority_entries[@]}" | sort -k1,1n -k2,2)
  fi

  STACKS=("${ordered_stacks[@]}")
  [[ ${#STACKS[@]} -gt 0 ]]
}

# ------------------------------------------------------------------------------
# Function: discover_nocow_storage_paths
# Description:
#   Discovers and resolves host filesystem paths declared with No-CoW storage
#   policies ('homelab.storage.nocow' or 'homelab.storage.btrfs.nocow') across
#   all Compose stacks. Matches declared container targets to service volumes
#   and resolves host environment variables (${DOCKER_DATA_DIR}, ${MEDIA_DIR}).
# Global Variables:
#   REPO_DIR, DOCKER_DATA_DIR, MEDIA_DIR
# Returns:
#   Outputs resolved absolute host paths to stdout (one per line).
# ------------------------------------------------------------------------------
discover_nocow_storage_paths() {
  local target_paths=()
  local re_label='homelab\.storage\.(btrfs\.nocow|nocow)=([^"'\''[:space:]]+)'
  local re_service='^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$'
  local re_section='^[[:space:]]{4}(volumes|labels):[[:space:]]*$'

  # Ensure root .env variables are available if unexported in current shell
  if [[ -f "${REPO_DIR}/.env" && -z "${DOCKER_DATA_DIR:-}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${REPO_DIR}/.env"
    set +a
  fi

  local compose_file
  for compose_file in "${REPO_DIR}"/*/compose.yml; do
    [[ -f "${compose_file}" ]] || continue
    local stack_dir
    stack_dir="$(dirname "${compose_file}")"

    # Safely load stack-level .env or .env.example for stack-specific variable bindings
    local stack_env="${stack_dir}/.env"
    [[ -f "${stack_env}" ]] || stack_env="${stack_dir}/.env.example"
    if [[ -f "${stack_env}" ]]; then
      while IFS='=' read -r k v || [[ -n "${k}" ]]; do
        [[ -z "${k}" || "${k}" =~ ^[[:space:]]*# ]] && continue
        v="${v#\"}"; v="${v%\"}"
        v="${v#\'}"; v="${v%\'}"
        export "${k}=${v}"
      done < "${stack_env}"
    fi

    local current_section=""
    local nocow_targets=()
    local volume_pairs=()

    process_service_storage() {
      if [[ ${#nocow_targets[@]} -gt 0 && ${#volume_pairs[@]} -gt 0 ]]; then
        local t pair
        for t in "${nocow_targets[@]}"; do
          for pair in "${volume_pairs[@]}"; do
            local h="${pair%%|*}"
            local c="${pair#*|}"
            if [[ "${c}" == "${t}" ]]; then
              local cleaned
              cleaned="$(echo "${h}" | sed -E 's/:\?[^}:]*//g')"
              local resolved
              set +u
              eval "resolved=\"${cleaned}\""
              set -u
              [[ -n "${resolved}" ]] && target_paths+=("${resolved}")
            fi
          done
        done
      fi
    }

    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" =~ ${re_service} ]]; then
        process_service_storage
        current_section=""
        nocow_targets=()
        volume_pairs=()
      elif [[ "${line}" =~ ${re_section} ]]; then
        current_section="${BASH_REMATCH[1]}"
      elif [[ "${line}" =~ ^[[:space:]]{6,}- ]]; then
        if [[ "${current_section}" == "labels" ]]; then
          if [[ "${line}" =~ ${re_label} ]]; then
            local raw_val="${BASH_REMATCH[2]}"
            local item
            IFS="," read -ra items <<< "${raw_val}"
            for item in "${items[@]}"; do
              [[ -n "${item}" ]] && nocow_targets+=("${item}")
            done
          fi
        elif [[ "${current_section}" == "volumes" ]]; then
          local v="${line#"${line%%[! -]*}"}"
          v="${v#\"}"; v="${v%\"}"
          v="${v#\'}"; v="${v%\'}"
          if [[ "${v}" =~ :[a-zA-Z0-9_,]+$ ]]; then
            local opt="${BASH_REMATCH[0]}"
            if [[ "${opt}" =~ ^:(ro|rw|z|Z) ]]; then
              v="${v%${opt}}"
            fi
          fi
          if [[ "${v}" == *:* ]]; then
            local c_path="${v##*:}"
            local h_path="${v%:*}"
            volume_pairs+=("${h_path}|${c_path}")
          fi
        fi
      fi
    done < "${compose_file}"
    process_service_storage
  done

  printf "%s\n" "${target_paths[@]}"
}

# ------------------------------------------------------------------------------
# Function: is_stack_enabled
# Description:
#   Checks whether a given stack is active and contains at least one enabled service.
# Arguments:
#   $1 (stack_name) - Directory name of the stack (e.g. "productivity", "media").
# Returns:
#   0 if enabled/present; 1 if omitted, empty, or not found.
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

# Dynamically discovered list of enabled services and container names
ENABLED_SERVICES=()
discover_services || true

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
  "DOCKER_SOCK"
  "DRI_RENDER_DEVICE"
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

# ------------------------------------------------------------------------------
# Function: run_git
# Description:
#   Executes git commands within REPO_DIR, automatically delegating to TARGET_USER
#   if running under sudo so user identity, GPG keys, and SSH credentials for
#   remote push operations remain intact.
# Arguments:
#   $@ - Git arguments to execute.
# ------------------------------------------------------------------------------
run_git() {
  if [[ "${EUID}" -eq 0 && -n "${TARGET_USER:-}" && "${TARGET_USER}" != "root" ]]; then
    sudo -u "${TARGET_USER}" git -C "${REPO_DIR}" "$@"
  else
    git -C "${REPO_DIR}" "$@"
  fi
}

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

  while run_git rev-parse -q --verify "refs/tags/${candidate}" >/dev/null 2>&1; do
    candidate="${base_tag}.${seq}"
    ((seq++))
  done

  printf "%s" "${candidate}"
}

# ------------------------------------------------------------------------------
# Function: bump_semver
# Description:
#   Calculates next semantic version (major, minor, or patch) based on the
#   highest existing SemVer tag in the git repository. Deliberately excludes
#   4-digit CalVer years (2024+) so CalVer tags are never misidentified as SemVer.
# Arguments:
#   $1 (bump_type) - One of: major, minor, patch.
# Outputs:
#   Prints incremented X.Y.Z string on stdout.
# ------------------------------------------------------------------------------
bump_semver() {
  local bump_type="$1"
  local latest major minor patch

  latest="$(run_git tag -l | grep -E '^v?[0-9]{1,3}\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -n 1)"
  latest="${latest#v}"

  if [[ -z "${latest}" ]]; then
    major=0; minor=1; patch=0
  else
    IFS='.' read -r major minor patch <<< "${latest}"
    patch="${patch:-0}"
  fi

  case "${bump_type}" in
    major)
      ((major++))
      minor=0
      patch=0
      ;;
    minor)
      ((minor++))
      patch=0
      ;;
    patch)
      ((patch++))
      ;;
    *)
      log_error "Unknown semver bump type: ${bump_type}"
      return 1
      ;;
  esac

  printf "%d.%d.%d" "${major}" "${minor}" "${patch}"
}

# ------------------------------------------------------------------------------
# Function: resolve_release_tags
# Description:
#   Processes an array of requested tag arguments (SemVer-major/minor/patch,
#   CalVer, or custom strings) and outputs a space-delimited list of unique
#   resolved tags.
# Arguments:
#   $@ - List of tag requests. If omitted, reads from BACKUP_TAG_REQUESTS global.
# Outputs:
#   Space-delimited resolved tags on stdout.
# ------------------------------------------------------------------------------
resolve_release_tags() {
  local requests=()
  if [[ $# -gt 0 ]]; then
    requests=("$@")
  elif [[ -n "${BACKUP_TAG_REQUESTS:-}" ]]; then
    requests=("${BACKUP_TAG_REQUESTS[@]}")
  fi

  local tag_req req_lower tag_resolved resolved=()
  for tag_req in "${requests[@]}"; do
    req_lower="$(echo "${tag_req}" | tr '[:upper:]' '[:lower:]')"
    case "${req_lower}" in
      semver-major|semver_major|major)
        tag_resolved="$(bump_semver major)"
        ;;
      semver-minor|semver_minor|minor)
        tag_resolved="$(bump_semver minor)"
        ;;
      semver-patch|semver_patch|patch)
        tag_resolved="$(bump_semver patch)"
        ;;
      calver)
        tag_resolved="$(resolve_chronological_tag)"
        ;;
      *)
        tag_resolved="${tag_req}"
        ;;
    esac
    resolved+=("${tag_resolved}")
  done

  # Deduplicate while preserving order
  local unique=() t u already
  for t in "${resolved[@]}"; do
    already=0
    for u in "${unique[@]}"; do
      [[ "${u}" == "${t}" ]] && already=1 && break
    done
    [[ "${already}" -eq 0 ]] && unique+=("${t}")
  done

  printf "%s\n" "${unique[*]:-}"
}

# Backward-compatible alias for existing callers
resolve_backup_tags() {
  resolve_release_tags "$@"
}
