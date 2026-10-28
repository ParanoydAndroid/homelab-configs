#!/usr/bin/env bash
# ==============================================================================
# Script Name: homelab.sh
# Description:
#   Primary lifecycle, configuration synchronization, and backup automation CLI
#   for the UGREEN NAS homelab environment (nas.home / turing.home).
#
# Purpose and Operation:
#   This script manages the declarative convergence of the homelab stack
#   repository (/opt/${USER}/dockge/stacks, symlinked at ~/services) with the
#   live host filesystem (/volume1/docker, /volume1/media, /opt/${USER}/dockge)
#   and the Docker Engine.
#
#   It is designed to be idempotent and safe to run repeatedly on both fresh
#   host installations and routine updates after 'git pull'.
#
# Subcommands:
#   setup           End-to-end host and service convergence:
#                     1. Remediates the UGREEN NAS OS 'GODEBUG=tlskyber=0' bug
#                        that crashes Go 1.23+ binaries.
#                     2. Initializes untracked '.env' files from '.env.example'
#                        templates and propagates global variables from the root
#                        '.env' into every per-stack '.env' and Dockge's '.env'.
#                     3. Creates the 'homelab' (bridge) and 'external_npm'
#                        (macvlan) Docker networks if they do not exist.
#                     4. Deploys tracked configuration files from '.configs/'
#                        to their live host volume locations with diff checks.
#                     5. Starts the external Dockge orchestrator and all Docker
#                        Compose service stacks in dependency order.
#
#   deploy-configs  Synchronizes tracked configuration files from '.configs/'
#                   to live host paths (/volume1/docker/... and Dockge).
#                   Detects local modifications on the host using byte-level
#                   comparison ('cmp -s'), displays unified diffs ('diff -u'),
#                   and prompts interactively before overwriting. Includes a
#                   safety guard for Nginx Proxy Manager '.conf' files to skip
#                   configs referencing SSL certificates not yet present on disk.
#
#   pull-configs    Retrieves live configuration changes made through service
#                   Web UIs (Homepage YAML/CSS/JS, qBittorrentVPN helper scripts,
#                   and Nginx Proxy Manager SQLite host tables + generated Nginx
#                   '.conf' files) back into '.configs/' for git versioning.
#
#   backup          Creates a timestamped compressed tarball in
#                   ${DOCKER_DATA_DIR}/backup/homelab/ containing all repository
#                   definitions, live '.env' secrets, and portable application
#                   configuration files.
#
# Usage:
#   sudo ./homelab.sh setup [--overwrite-all | --keep-all]
#   ./homelab.sh deploy-configs [--overwrite-all | --keep-all]
#   ./homelab.sh pull-configs
#   ./homelab.sh backup
# ==============================================================================

set -euo pipefail

# Resolve the absolute path to the repository root where this script resides,
# resolving any relative invocation paths so all file operations are anchored
# deterministically to the repository directory.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dynamically resolve the non-root homelab user and primary group.
# When invoked via 'sudo ./homelab.sh ...', SUDO_USER holds the invoking user's
# login name. If invoked directly without sudo (or as root without SUDO_USER),
# fall back to inspecting the filesystem owner of REPO_DIR so paths like
# /opt/${USER}/dockge never accidentally resolve to '/opt/root/dockge'.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
else
  TARGET_USER="$(stat -c '%U' "${REPO_DIR}")"
fi
TARGET_GROUP="$(id -gn "${TARGET_USER}" 2>/dev/null || echo "admin")"

# Ordered list of Docker Compose stack directories managed by this repository.
# Order matters during 'setup':
#   1. 'postgres' starts first because 'tandoor' depends on the 'postgresql'
#      database container being reachable on the 'homelab' bridge network.
#   2. 'nginx' starts second so reverse proxy routing is available immediately.
#   3. Remaining application stacks follow.
STACKS=(
  "postgres"
  "nginx"
  "homepage"
  "jellyfin"
  "qbittorrentvpn"
  "sonarr-radarr"
  "tandoor"
)

# Controls conflict resolution behavior in sync_file() when a live host config
# file differs from the tracked version in '.configs/'.
# Valid values:
#   "prompt"        Ask the user interactively for each differing file (default).
#   "overwrite_all" Overwrite all differing host files without prompting (-O).
#   "keep_all"      Preserve all existing host files without prompting (-K).
OVERWRITE_MODE="prompt"

# ------------------------------------------------------------------------------
# Function: log_info
# Description:
#   Writes an informational status message to standard output (stdout) with an
#   '[INFO]' prefix.
# Arguments:
#   $* - Message string to print.
# Outputs:
#   Formatted single-line message on stdout.
# ------------------------------------------------------------------------------
log_info() {
  printf "[INFO] %s\n" "$*"
}

# ------------------------------------------------------------------------------
# Function: log_warn
# Description:
#   Writes a non-fatal warning message to standard error (stderr) with a
#   '[WARN]' prefix.
# Arguments:
#   $* - Warning message string to print.
# Outputs:
#   Formatted single-line message on stderr.
# ------------------------------------------------------------------------------
log_warn() {
  printf "[WARN] %s\n" "$*" >&2
}

# ------------------------------------------------------------------------------
# Function: log_error
# Description:
#   Writes an error message to standard error (stderr) with an '[ERROR]' prefix.
# Arguments:
#   $* - Error message string to print.
# Outputs:
#   Formatted single-line message on stderr.
# ------------------------------------------------------------------------------
log_error() {
  printf "[ERROR] %s\n" "$*" >&2
}

# ------------------------------------------------------------------------------
# Function: upsert_env_var
# Description:
#   Idempotently inserts or updates a single KEY=VALUE assignment inside a
#   dotenv ('.env') file while preserving all other lines, comments, and ordering.
#
#   Why awk instead of sed:
#   Values in '.env' files (such as base64-encoded cryptographic SECRET_KEY
#   values or filesystem paths) frequently contain forward slashes ('/'),
#   ampersands ('&'), or backslashes ('\'). Passing such values into 'sed s///'
#   causes delimiter collisions or backreference corruption. Passing the key and
#   value via awk '-v' variables avoids regex/delimiter escaping issues entirely.
#
# Arguments:
#   $1 (file) - Path to the target '.env' file (created if it does not exist).
#   $2 (key)  - Environment variable name (left of '=').
#   $3 (val)  - Environment variable value (right of '=').
# Side Effects:
#   Atomically rewrites '$1' via a temporary file '${file}.tmp'.
# ------------------------------------------------------------------------------
upsert_env_var() {
  local file="$1"
  local key="$2"
  local val="$3"
  touch "${file}"

  # Match lines starting with literally "KEY=" at column 1 (index == 1).
  # If found, replace the line with the new "KEY=VAL" and mark found=1.
  # At EOF (END), if the key was never encountered, append "KEY=VAL".
  awk -v k="${key}" -v v="${val}" '
    BEGIN { found = 0 }
    index($0, k "=") == 1 { print k "=" v; found = 1; next }
    { print }
    END { if (!found) print k "=" v }
  ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
}

# ------------------------------------------------------------------------------
# Function: get_env_var
# Description:
#   Reads and prints the raw value assigned to a given key in a dotenv ('.env')
#   file without sourcing or executing the file in bash.
# Arguments:
#   $1 (file) - Path to the '.env' file to inspect.
#   $2 (key)  - Environment variable key to look up.
# Outputs:
#   Prints the substring after 'KEY=' for the first matching line, or nothing
#   if the file or key does not exist.
# ------------------------------------------------------------------------------
get_env_var() {
  local file="$1"
  local key="$2"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi

  # Locate the first line starting with "KEY=" and extract everything after
  # the '=' character (offset = length(k) + 2 in 1-based awk indexing).
  awk -v k="${key}" '
    index($0, k "=") == 1 {
      print substr($0, length(k) + 2)
      exit
    }
  ' "${file}"
}

# ------------------------------------------------------------------------------
# Function: init_and_sync_env
# Description:
#   Implements the two-tier '.env.example' -> '.env' configuration architecture
#   required for Dockge compatibility:
#     1. Ensures the root '.env' exists (initializing it from '.env.example'
#        if missing) and resolves literal '${USER}' placeholders to the active
#        non-root username (TARGET_USER).
#     2. Sources the root '.env' into the current shell environment so global
#        variables (DOCKER_DATA_DIR, MEDIA_DIR, DOCKGE_DIR, PUID, PGID, etc.)
#        are available to all subsequent script functions.
#     3. Ensures each stack directory ('<stack>/.env') and Dockge's directory
#        ('${DOCKGE_DIR}/.env') have an initialized '.env' file.
#     4. Propagates all global KEY=VALUE pairs from the root '.env' into every
#        '<stack>/.env' and '${DOCKGE_DIR}/.env' so that stacks have access to
#        global variables even when Dockge runs 'docker compose' inside an
#        individual stack subdirectory.
#     5. Audits every per-stack '<stack>/.env.example' and logs a warning if
#        any required secret or API key remains blank in '<stack>/.env'.
#
# Globals Read:
#   REPO_DIR, TARGET_USER, TARGET_GROUP, STACKS
# Globals Exported (from root .env):
#   DOCKER_DATA_DIR, MEDIA_DIR, DOCKGE_DIR, DOCKGE_STACKS_DIR, PUID, PGID, TZ,
#   EXTERNAL_NPM_SUBNET, EXTERNAL_NPM_GATEWAY, EXTERNAL_NPM_PARENT,
#   NPM_IPV4_ADDRESS
# Side Effects:
#   Creates/updates '.env' files across the repository and '${DOCKGE_DIR}/.env',
#   and sets ownership to TARGET_USER:TARGET_GROUP.
# ------------------------------------------------------------------------------
init_and_sync_env() {
  local root_env="${REPO_DIR}/.env"
  local root_example="${REPO_DIR}/.env.example"

  # Step 1: Initialize root .env from .env.example if missing, replacing any
  # literal '${USER}' placeholder with the resolved non-root username.
  if [[ ! -f "${root_env}" ]]; then
    log_info "Initializing ${root_env} from ${root_example} (user: ${TARGET_USER})"
    sed "s|\${USER}|${TARGET_USER}|g" "${root_example}" > "${root_env}"
  else
    # Even if root .env already exists, ensure no unresolved '${USER}' token remains.
    sed -i "s|\${USER}|${TARGET_USER}|g" "${root_env}"
  fi
  chown "${TARGET_USER}:${TARGET_GROUP}" "${root_env}" 2>/dev/null || true

  # Step 2: Export all variables defined in root .env into the current process.
  set -a
  # shellcheck disable=SC1090
  source "${root_env}"
  set +a

  # Step 3: Initialize Dockge's own .env file in DOCKGE_DIR (/opt/<user>/dockge/.env).
  mkdir -p "${DOCKGE_DIR}"
  local dockge_env="${DOCKGE_DIR}/.env"
  if [[ ! -f "${dockge_env}" && -f "${REPO_DIR}/.configs/dockge/.env.example" ]]; then
    sed "s|\${USER}|${TARGET_USER}|g" "${REPO_DIR}/.configs/dockge/.env.example" > "${dockge_env}"
  fi

  # Step 4: Initialize and sync each stack's .env file.
  local stack
  local target_env
  local stack_example
  for stack in "${STACKS[@]}"; do
    [[ -d "${REPO_DIR}/${stack}" ]] || continue
    target_env="${REPO_DIR}/${stack}/.env"
    stack_example="${REPO_DIR}/${stack}/.env.example"

    # If the stack does not yet have a live .env, seed it from its .env.example
    # (if one exists) or create an empty file.
    if [[ ! -f "${target_env}" ]]; then
      if [[ -f "${stack_example}" ]]; then
        sed "s|\${USER}|${TARGET_USER}|g" "${stack_example}" > "${target_env}"
      else
        touch "${target_env}"
      fi
    fi

    # Propagate every non-comment KEY=VALUE line from root .env into the stack's .env.
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
      [[ -z "${key}" || "${key}" =~ ^[[:space:]]*# ]] && continue
      upsert_env_var "${target_env}" "${key}" "${val}"
    done < "${root_env}"

    chown "${TARGET_USER}:${TARGET_GROUP}" "${target_env}" 2>/dev/null || true

    # Step 5: Check that all per-stack secret keys defined in <stack>/.env.example
    # have non-empty values in <stack>/.env.
    if [[ -f "${stack_example}" ]]; then
      while IFS='=' read -r req_key _ || [[ -n "${req_key}" ]]; do
        [[ -z "${req_key}" || "${req_key}" =~ ^[[:space:]]*# ]] && continue
        local cur_val
        cur_val="$(get_env_var "${target_env}" "${req_key}")"
        if [[ -z "${cur_val}" ]]; then
          log_warn "Required variable '${req_key}' in ${stack}/.env is currently blank."
        fi
      done < "${stack_example}"
    fi
  done

  # Sync root .env globals into Dockge's .env file as well.
  while IFS='=' read -r key val || [[ -n "${key}" ]]; do
    [[ -z "${key}" || "${key}" =~ ^[[:space:]]*# ]] && continue
    upsert_env_var "${dockge_env}" "${key}" "${val}"
  done < "${root_env}"
  chown "${TARGET_USER}:${TARGET_GROUP}" "${dockge_env}" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Function: remediate_godebug
# Description:
#   Idempotently remediates a UGREEN NAS OS defect where 'GODEBUG=tlskyber=0'
#   is injected globally via '/etc/profile.d/go.sh' and '/etc/systemd/system.conf'.
#
#   Background:
#   Go 1.23 removed the experimental 'tlskyber' GODEBUG setting and panics on
#   startup if 'GODEBUG=tlskyber=0' is present in the process environment. This
#   breaks Go 1.23+ binaries on the host, including the Antigravity remote server
#   and modern CLI tools.
#
#   Operation:
#   1. Comments out active 'export GODEBUG=tlskyber=0' lines in /etc/profile.d/go.sh.
#   2. Comments out active 'DefaultEnvironment="GODEBUG=tlskyber=0"' lines in
#      /etc/systemd/system.conf.
#   3. Clears GODEBUG from the running system and user systemd manager environments
#      and re-executes systemd ('daemon-reexec') in place without requiring a
#      host reboot.
# ------------------------------------------------------------------------------
remediate_godebug() {
  log_info "Checking UGREEN NAS GODEBUG=tlskyber=0 configuration..."
  local systemd_changed=0

  # Check login shell profile script (/etc/profile.d/go.sh) for uncommented export.
  if [[ -f /etc/profile.d/go.sh ]]; then
    if grep -qE '^[[:space:]]*export[[:space:]]+GODEBUG=tlskyber=0' /etc/profile.d/go.sh; then
      log_info "Commenting out export GODEBUG=tlskyber=0 in /etc/profile.d/go.sh"
      sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
    fi
  fi

  # Check systemd global manager config (/etc/systemd/system.conf) for uncommented DefaultEnvironment.
  if [[ -f /etc/systemd/system.conf ]]; then
    if grep -qE '^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"' /etc/systemd/system.conf; then
      log_info "Commenting out DefaultEnvironment=\"GODEBUG=tlskyber=0\" in /etc/systemd/system.conf"
      sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
      systemd_changed=1
    fi
  fi

  # Immediately unset GODEBUG in both the system-wide and user systemd managers
  # so newly spawned services/sessions do not inherit it prior to next reboot.
  systemctl unset-environment GODEBUG 2>/dev/null || true
  systemctl --user unset-environment GODEBUG 2>/dev/null || true

  # If /etc/systemd/system.conf was modified, reload PID 1 in place.
  if [[ "${systemd_changed}" -eq 1 ]]; then
    log_info "Reloading systemd manager configuration (daemon-reexec)..."
    systemctl daemon-reexec
  fi
}

# ------------------------------------------------------------------------------
# Function: ensure_networks
# Description:
#   Idempotently verifies and creates the two external Docker networks required
#   by the homelab stacks:
#     1. 'homelab': Internal container-to-container bridge network on
#        192.168.255.0/24 (gateway 192.168.255.1) linking Nginx Proxy Manager
#        with all backend services.
#     2. 'external_npm': Macvlan network on the physical LAN interface
#        (default parent 'eth0', subnet 192.168.0.0/24, gateway 192.168.0.1)
#        allowing Nginx Proxy Manager to bind directly to its dedicated LAN IP
#        (192.168.0.4 / turing.home).
#
# Globals Read:
#   EXTERNAL_NPM_SUBNET, EXTERNAL_NPM_GATEWAY, EXTERNAL_NPM_PARENT
# Side Effects:
#   Creates Docker networks 'homelab' and 'external_npm' if absent.
# ------------------------------------------------------------------------------
ensure_networks() {
  if ! docker network inspect homelab >/dev/null 2>&1; then
    log_info "Creating Docker bridge network 'homelab' (192.168.255.0/24)..."
    docker network create -d bridge \
      --subnet=192.168.255.0/24 \
      --gateway=192.168.255.1 \
      homelab
  else
    log_info "Docker network 'homelab' already exists."
  fi

  if ! docker network inspect external_npm >/dev/null 2>&1; then
    log_info "Creating Docker macvlan network 'external_npm' (${EXTERNAL_NPM_SUBNET})..."
    docker network create -d macvlan \
      --subnet="${EXTERNAL_NPM_SUBNET}" \
      --gateway="${EXTERNAL_NPM_GATEWAY}" \
      -o "parent=${EXTERNAL_NPM_PARENT}" \
      external_npm
  else
    log_info "Docker network 'external_npm' already exists."
  fi
}

# ------------------------------------------------------------------------------
# Function: sync_file
# Description:
#   Deploys a single tracked configuration file from the repository to its
#   target host path with change detection and interactive conflict resolution.
#
#   Operation:
#   - If the destination file does not exist, copies the source file into place
#     immediately and returns 0 (indicating the target was modified).
#   - If the destination file exists and is byte-for-byte identical ('cmp -s'),
#     does nothing and returns 1 (no modification).
#   - If the destination file exists and differs from the tracked source file,
#     prints a unified diff ('diff -u') showing local host changes vs. repo
#     changes, then resolves the conflict according to OVERWRITE_MODE:
#       * 'overwrite_all': Overwrites destination without prompting.
#       * 'keep_all':      Keeps destination without prompting.
#       * 'prompt':        Prompts the user on stdin (if interactive TTY) with
#                          [o]verwrite / [k]eep / [O]verwrite all / [K]eep all.
#
# Arguments:
#   $1 (src)  - Source file path inside the repository ('.configs/...').
#   $2 (dst)  - Target file path on the host filesystem.
#   $3 (mode) - Optional octal chmod permission string (e.g., '0644' or '0755').
# Globals Read/Modified:
#   OVERWRITE_MODE (may transition from 'prompt' to 'overwrite_all' or 'keep_all'
#   if the user selects 'O' or 'K').
# Returns:
#   0 if the destination file was newly installed or overwritten.
#   1 if the destination file was already identical or preserved ('keep').
# ------------------------------------------------------------------------------
sync_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-}"

  mkdir -p "$(dirname "${dst}")"

  # Case 1: Target file does not exist yet on the host; install cleanly.
  if [[ ! -f "${dst}" ]]; then
    cp -p "${src}" "${dst}"
    if [[ -n "${mode}" ]]; then
      chmod "${mode}" "${dst}" 2>/dev/null || true
    fi
    log_info "Installed: ${dst}"
    return 0
  fi

  # Case 2: Target file is byte-for-byte identical to the tracked source; no-op.
  if cmp -s "${src}" "${dst}"; then
    return 1
  fi

  # Case 3: Target file exists and differs; display unified diff and resolve conflict.
  printf "\n--- Differences detected for %s ---\n" "${dst}"
  diff -u "${dst}" "${src}" || true

  local action=""
  case "${OVERWRITE_MODE}" in
    overwrite_all)
      action="overwrite"
      ;;
    keep_all)
      action="keep"
      ;;
    *)
      if [[ -t 0 ]]; then
        while [[ -z "${action}" ]]; do
          read -r -p "Conflict on ${dst}: [o]verwrite / [k]eep / [O]verwrite all / [K]eep all? " choice
          case "${choice}" in
            o) action="overwrite" ;;
            k) action="keep" ;;
            O) OVERWRITE_MODE="overwrite_all"; action="overwrite" ;;
            K) OVERWRITE_MODE="keep_all"; action="keep" ;;
            *) printf "Please enter o, k, O, or K.\n" ;;
          esac
        done
      else
        log_warn "Non-interactive shell: keeping existing modified file ${dst} (pass --overwrite-all to force)."
        action="keep"
      fi
      ;;
  esac

  if [[ "${action}" == "overwrite" ]]; then
    cp -f "${src}" "${dst}"
    if [[ -n "${mode}" ]]; then
      chmod "${mode}" "${dst}" 2>/dev/null || true
    fi
    log_info "Updated: ${dst}"
    return 0
  else
    log_info "Kept existing: ${dst}"
    return 1
  fi
}

# ------------------------------------------------------------------------------
# Function: npm_conf_certs_exist
# Description:
#   Pre-deployment safety check for Nginx Proxy Manager (NPM) '.conf' files.
#
#   Why this check is required:
#   NPM proxy host '.conf' files reference SSL certificates using container-internal
#   paths ('/etc/letsencrypt/live/npm-X/fullchain.pem' or '/data/custom_ssl/npm-X/...').
#   On a fresh host installation where Let's Encrypt or custom certificates have
#   not yet been provisioned via the NPM Admin UI, deploying a '.conf' file that
#   references non-existent certificate files causes 'nginx -t' to fail on
#   startup, placing the 'nginx' container into a crash loop and locking the
#   user out of the NPM Admin UI (port 81).
#
#   Operation:
#   Parses all 'ssl_certificate' and 'ssl_certificate_key' directives from the
#   given '.conf' file, translates their container paths ('/etc/letsencrypt/...'
#   or '/data/...') to the corresponding host bind-mount paths under
#   '${DOCKER_DATA_DIR}/nginx/data/', and verifies that every referenced file
#   exists on disk.
#
# Arguments:
#   $1 (conf_file) - Path to the tracked NPM '.conf' file to validate.
# Globals Read:
#   DOCKER_DATA_DIR
# Returns:
#   0 if the '.conf' file references no SSL certificates or all referenced
#     certificate files exist on the host.
#   1 if any referenced SSL certificate file is missing on the host.
# ------------------------------------------------------------------------------
npm_conf_certs_exist() {
  local conf_file="$1"
  local cert_line
  local cert_path
  local host_cert_path

  # Extract each 'ssl_certificate' or 'ssl_certificate_key' directive line.
  # The sed expression strips leading whitespace, the directive keyword, and
  # the trailing semicolon/comments, leaving only the container file path (\2).
  while IFS= read -r cert_line; do
    cert_path="$(printf "%s" "${cert_line}" | sed -E 's/^[[:space:]]*ssl_certificate(_key)?[[:space:]]+([^;]+);.*$/\2/')"

    # Translate container volume mount paths to host filesystem paths:
    #   /etc/letsencrypt/... -> ${DOCKER_DATA_DIR}/nginx/data/letsencrypt/...
    #   /data/...            -> ${DOCKER_DATA_DIR}/nginx/data/...
    if [[ "${cert_path}" == /etc/letsencrypt/* ]]; then
      host_cert_path="${DOCKER_DATA_DIR}/nginx/data/letsencrypt/${cert_path#/etc/letsencrypt/}"
    elif [[ "${cert_path}" == /data/* ]]; then
      host_cert_path="${DOCKER_DATA_DIR}/nginx/data/${cert_path#/data/}"
    else
      host_cert_path="${cert_path}"
    fi

    if [[ ! -f "${host_cert_path}" ]]; then
      log_warn "Skipping $(basename "${conf_file}"): referenced SSL file '${host_cert_path}' does not exist on host. Complete SSL setup in README.md and re-run './homelab.sh deploy-configs'."
      return 1
    fi
  done < <(grep -E '^[[:space:]]*ssl_certificate(_key)?[[:space:]]+' "${conf_file}" || true)

  return 0
}

# ------------------------------------------------------------------------------
# Function: deploy_configs
# Description:
#   Synchronizes all tracked configuration files from '${REPO_DIR}/.configs/'
#   to their live host destinations:
#     1. '.configs/dockge/compose.yml'        -> '${DOCKGE_DIR}/compose.yml'
#     2. '.configs/homepage/*'                -> '${DOCKER_DATA_DIR}/homepage/data/'
#     3. '.configs/qbittorrentvpn/getvpnport.sh' -> '${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh'
#     4. '.configs/nginx/nginx/<subdir>/*.conf'  -> '${DOCKER_DATA_DIR}/nginx/data/nginx/<subdir>/'
#
#   If any Nginx Proxy Manager '.conf' file is newly installed or updated and
#   the 'nginx' container is currently running, automatically triggers an in-place
#   Nginx configuration reload ('docker exec nginx nginx -s reload').
# ------------------------------------------------------------------------------
deploy_configs() {
  init_and_sync_env

  log_info "Deploying tracked configurations to host paths..."

  # 1. Deploy Dockge's compose.yml outside the stacks directory (${DOCKGE_DIR}/compose.yml)
  # so Dockge does not detect and manage itself as a child stack.
  if [[ -f "${REPO_DIR}/.configs/dockge/compose.yml" ]]; then
    sync_file "${REPO_DIR}/.configs/dockge/compose.yml" "${DOCKGE_DIR}/compose.yml" "0644" || true
    chown "${TARGET_USER}:${TARGET_GROUP}" "${DOCKGE_DIR}/compose.yml" 2>/dev/null || true
  fi

  # 2. Deploy Homepage dashboard configuration files (YAML, CSS, JS).
  if [[ -d "${REPO_DIR}/.configs/homepage" ]]; then
    local hp_file
    for hp_file in "${REPO_DIR}/.configs/homepage/"*; do
      [[ -f "${hp_file}" ]] || continue
      sync_file "${hp_file}" "${DOCKER_DATA_DIR}/homepage/data/$(basename "${hp_file}")" "0644" || true
    done
  fi

  # 3. Deploy qBittorrentVPN PIA port-forwarding script with executable permissions (0755)
  # and non-root service ownership (${PUID}:${PGID}).
  if [[ -f "${REPO_DIR}/.configs/qbittorrentvpn/getvpnport.sh" ]]; then
    sync_file "${REPO_DIR}/.configs/qbittorrentvpn/getvpnport.sh" "${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh" "0755" || true
    chown "${PUID:-1000}:${PGID:-100}" "${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh" 2>/dev/null || true
  fi

  # 4. Deploy Nginx Proxy Manager generated .conf files (subject to SSL certificate guard).
  local npm_updated=0
  if [[ -d "${REPO_DIR}/.configs/nginx/nginx" ]]; then
    local subdir
    local conf_file
    for subdir in proxy_host dead_host redirection_host default_host default_www custom; do
      [[ -d "${REPO_DIR}/.configs/nginx/nginx/${subdir}" ]] || continue
      for conf_file in "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"*; do
        [[ -f "${conf_file}" ]] || continue
        # Verify referenced SSL certificates exist on disk before copying the .conf file.
        if ! npm_conf_certs_exist "${conf_file}"; then
          continue
        fi
        if sync_file "${conf_file}" "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}/$(basename "${conf_file}")" "0644"; then
          npm_updated=1
        fi
      done
    done
  fi

  # If any NPM .conf file was installed or updated and the nginx container is active,
  # reload Nginx gracefully to apply the changes immediately.
  if [[ "${npm_updated}" -eq 1 ]]; then
    if docker ps --format '{{.Names}}' | grep -qx 'nginx'; then
      log_info "Reloading Nginx inside 'nginx' container..."
      docker exec nginx nginx -s reload
    fi
  fi
}

# ------------------------------------------------------------------------------
# Function: pull_configs
# Description:
#   Pulls live service configurations from '${DOCKER_DATA_DIR}' into
#   '${REPO_DIR}/.configs/' so changes made via Web UIs or on the host can be
#   inspected with 'git diff' and committed to version control:
#     1. Copies Homepage '*.yaml', '*.yml', '*.css', and '*.js' files from
#        '${DOCKER_DATA_DIR}/homepage/data/' into '.configs/homepage/' (excluding
#        ephemeral logs or caches).
#     2. Copies '${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh' into
#        '.configs/qbittorrentvpn/getvpnport.sh'.
#     3. Exports a deterministic SQL dump of NPM's host routing tables
#        ('proxy_host', 'dead_host', 'redirection_host', 'setting') from
#        '${DOCKER_DATA_DIR}/nginx/data/db.sqlite' into '.configs/nginx/npm_hosts.sql'
#        (excluding the 'user', 'auth', and 'token' tables so password hashes
#        and session tokens are never committed to git).
#     4. Mirrors the active Nginx '.conf' directories from
#        '${DOCKER_DATA_DIR}/nginx/data/nginx/' into '.configs/nginx/nginx/'.
# ------------------------------------------------------------------------------
pull_configs() {
  init_and_sync_env

  log_info "Pulling live service configurations into ${REPO_DIR}/.configs/..."

  # 1. Pull Homepage YAML/CSS/JS configuration files.
  mkdir -p "${REPO_DIR}/.configs/homepage"
  if [[ -d "${DOCKER_DATA_DIR}/homepage/data" ]]; then
    local hp_src
    for hp_src in "${DOCKER_DATA_DIR}/homepage/data/"*.yaml "${DOCKER_DATA_DIR}/homepage/data/"*.yml "${DOCKER_DATA_DIR}/homepage/data/"*.css "${DOCKER_DATA_DIR}/homepage/data/"*.js; do
      [[ -f "${hp_src}" ]] || continue
      cp -p "${hp_src}" "${REPO_DIR}/.configs/homepage/$(basename "${hp_src}")"
    done
  fi

  # 2. Pull qBittorrentVPN port-forwarding script.
  mkdir -p "${REPO_DIR}/.configs/qbittorrentvpn"
  if [[ -f "${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh" ]]; then
    cp -p "${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh" "${REPO_DIR}/.configs/qbittorrentvpn/getvpnport.sh"
    chmod 0755 "${REPO_DIR}/.configs/qbittorrentvpn/getvpnport.sh"
  fi

  # 3. Export Nginx Proxy Manager non-sensitive routing tables and copy generated .conf files.
  mkdir -p "${REPO_DIR}/.configs/nginx/nginx"
  if [[ -f "${DOCKER_DATA_DIR}/nginx/data/db.sqlite" ]]; then
    if command -v sqlite3 >/dev/null 2>&1; then
      sqlite3 "${DOCKER_DATA_DIR}/nginx/data/db.sqlite" ".dump proxy_host dead_host redirection_host setting" > "${REPO_DIR}/.configs/nginx/npm_hosts.sql"
    else
      log_warn "sqlite3 not found on host; skipping npm_hosts.sql export."
    fi
  fi

  if [[ -d "${DOCKER_DATA_DIR}/nginx/data/nginx" ]]; then
    local subdir
    for subdir in proxy_host dead_host redirection_host default_host default_www custom; do
      if [[ -d "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}" ]]; then
        mkdir -p "${REPO_DIR}/.configs/nginx/nginx/${subdir}"
        # Remove stale .conf files in the repo directory first so deleted proxy hosts
        # do not persist as orphaned files in git.
        rm -f "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"* 2>/dev/null || true
        cp -rp "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}/." "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"
      fi
    done
  fi

  # Ensure all pulled files are owned by the non-root repository owner.
  chown -R "${TARGET_USER}:${TARGET_GROUP}" "${REPO_DIR}/.configs" 2>/dev/null || true
  log_info "Completed pulling live configurations into .configs/."
}

# ------------------------------------------------------------------------------
# Function: backup_homelab
# Description:
#   Creates a comprehensive, timestamped '.tar.gz' backup archive at
#   '${DOCKER_DATA_DIR}/backup/homelab/YYYYMMDD_homelab_config.tar.gz'.
#
#   Archive Contents:
#   - Repository documentation, scripts, '.gitignore', '.env.example', live
#     '.env', '.configs/', and '.agents/'.
#   - Every stack directory ('<stack>/compose.yml', '<stack>/.env.example',
#     and live '<stack>/.env' secrets).
#   - Live Dockge orchestrator files ('${DOCKGE_DIR}/compose.yml' and '.env').
#   - Live Homepage YAML files, qBittorrentVPN 'getvpnport.sh', and NPM's
#     'db.sqlite' and 'nginx/' directory.
# ------------------------------------------------------------------------------
backup_homelab() {
  init_and_sync_env

  local backup_dir="${DOCKER_DATA_DIR}/backup/homelab"
  local archive_name
  archive_name="$(date +%Y%m%d)_homelab_config.tar.gz"
  local archive_path="${backup_dir}/${archive_name}"

  mkdir -p "${backup_dir}"

  local files_to_backup=(
    "${REPO_DIR}/README.md"
    "${REPO_DIR}/homelab.sh"
    "${REPO_DIR}/backup-homelab.bash"
    "${REPO_DIR}/.gitignore"
    "${REPO_DIR}/.env.example"
    "${REPO_DIR}/.env"
    "${REPO_DIR}/.configs"
    "${REPO_DIR}/.agents"
  )

  # Include all stack directories (which contain compose.yml, .env.example, and live .env).
  local stack
  for stack in "${STACKS[@]}"; do
    [[ -d "${REPO_DIR}/${stack}" ]] && files_to_backup+=("${REPO_DIR}/${stack}")
  done

  # Include live deployed orchestrator and portable service configs on the host.
  [[ -f "${DOCKGE_DIR}/compose.yml" ]] && files_to_backup+=("${DOCKGE_DIR}/compose.yml")
  [[ -f "${DOCKGE_DIR}/.env" ]] && files_to_backup+=("${DOCKGE_DIR}/.env")
  [[ -f "${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh" ]] && files_to_backup+=("${DOCKER_DATA_DIR}/qbittorrentvpn/data/getvpnport.sh")
  [[ -f "${DOCKER_DATA_DIR}/nginx/data/db.sqlite" ]] && files_to_backup+=("${DOCKER_DATA_DIR}/nginx/data/db.sqlite")
  [[ -d "${DOCKER_DATA_DIR}/nginx/data/nginx" ]] && files_to_backup+=("${DOCKER_DATA_DIR}/nginx/data/nginx")

  if [[ -d "${DOCKER_DATA_DIR}/homepage/data" ]]; then
    local hp_file
    for hp_file in "${DOCKER_DATA_DIR}/homepage/data/"*.yaml "${DOCKER_DATA_DIR}/homepage/data/"*.yml; do
      [[ -f "${hp_file}" ]] && files_to_backup+=("${hp_file}")
    done
  fi

  tar -czf "${archive_path}" "${files_to_backup[@]}"
  chown "${TARGET_USER}:${TARGET_GROUP}" "${archive_path}" 2>/dev/null || true
  log_info "Backup completed successfully: ${archive_path}"
}

# ------------------------------------------------------------------------------
# Function: setup_homelab
# Description:
#   Executes the complete idempotent host and stack convergence workflow:
#     1. Remediates the UGREEN NAS 'GODEBUG=tlskyber=0' issue.
#     2. Initializes and syncs all '.env' files.
#     3. Ensures the 'homelab' and 'external_npm' Docker networks exist.
#     4. Deploys tracked configuration files from '.configs/' to host volumes.
#     5. Starts the external Dockge orchestrator and every stack in STACKS.
# ------------------------------------------------------------------------------
setup_homelab() {
  remediate_godebug
  init_and_sync_env
  ensure_networks
  deploy_configs

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
# Function: usage
# Description:
#   Prints CLI help and usage documentation to stdout.
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <subcommand> [options]

Subcommands:
  setup           Initialize .env files, apply NAS OS fixes, create networks, deploy configs, and start all stacks
  deploy-configs  Deploy tracked configurations from .configs/ to host volumes with diff inspection
  pull-configs    Pull live service configurations from host volumes into .configs/
  backup          Create a timestamped configuration backup archive in \${DOCKER_DATA_DIR}/backup/homelab/

Options for deploy-configs / setup:
  -O, --overwrite-all  Overwrite all differing target config files without prompting
  -K, --keep-all       Keep all existing target config files without prompting
EOF
}

# ------------------------------------------------------------------------------
# Function: main
# Description:
#   Entrypoint argument parser and subcommand dispatcher.
# Arguments:
#   $@ - Command-line arguments passed to the script.
# ------------------------------------------------------------------------------
main() {
  local subcmd="${1:-}"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -O|--overwrite-all) OVERWRITE_MODE="overwrite_all" ;;
      -K|--keep-all) OVERWRITE_MODE="keep_all" ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done

  case "${subcmd}" in
    setup) setup_homelab ;;
    deploy-configs) deploy_configs ;;
    pull-configs) pull_configs ;;
    backup) backup_homelab ;;
    -h|--help|"") usage; exit 0 ;;
    *) log_error "Unknown subcommand: ${subcmd}"; usage; exit 1 ;;
  esac
}

main "$@"
