#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/configs.sh
# Description:
#   Bidirectional configuration deployment and synchronization between tracked
#   repository paths (.configs/) and live host volumes (${DOCKER_DATA_DIR}/...).
# ==============================================================================
set -euo pipefail

# Subdirectories managed for Nginx Proxy Manager generated configurations
NPM_CONFIG_SUBDIRS=("proxy_host" "dead_host" "redirection_host" "default_host" "default_www" "custom")

# ------------------------------------------------------------------------------
# Function: sync_file
# Description:
#   Deploys a single tracked configuration file to its target host path with
#   change detection and interactive conflict resolution:
#     - If target missing: copies immediately and returns 0.
#     - If target identical ('cmp -s'): no-op and returns 1.
#     - If target differs: displays 'diff -u' and prompts or obeys OVERWRITE_MODE.
# Arguments:
#   $1 (src)  - Source file in repository (.configs/...).
#   $2 (dst)  - Destination file on host filesystem.
#   $3 (mode) - Optional octal chmod permission string.
# Returns:
#   0 if installed or overwritten, 1 if identical or kept.
# ------------------------------------------------------------------------------
sync_file() {
  local src="$1"
  local dst="$2"
  local mode="${3:-}"

  mkdir -p "$(dirname "${dst}")"

  if [[ ! -f "${dst}" ]]; then
    cp -p "${src}" "${dst}"
    [[ -n "${mode}" ]] && chmod "${mode}" "${dst}" 2>/dev/null || true
    log_info "Installed: ${dst}"
    return 0
  fi

  if cmp -s "${src}" "${dst}"; then
    return 1
  fi

  printf "\n--- Differences detected for %s ---\n" "${dst}"
  diff -u "${dst}" "${src}" || true

  local action=""
  case "${OVERWRITE_MODE}" in
    overwrite_all) action="overwrite" ;;
    keep_all)      action="keep" ;;
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
        log_warn "Non-interactive shell: keeping existing modified file ${dst} (pass -O to force)."
        action="keep"
      fi
      ;;
  esac

  if [[ "${action}" == "overwrite" ]]; then
    cp -f "${src}" "${dst}"
    [[ -n "${mode}" ]] && chmod "${mode}" "${dst}" 2>/dev/null || true
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
#   Safety guard to prevent Nginx crash loops: checks that all SSL certificates
#   referenced by a .conf file exist on the host filesystem before deployment.
# Arguments:
#   $1 (conf_file) - Path to tracked NPM .conf file.
# ------------------------------------------------------------------------------
npm_conf_certs_exist() {
  local conf_file="$1"
  local cert_line cert_path host_cert_path

  while IFS= read -r cert_line; do
    cert_path="$(printf "%s" "${cert_line}" | sed -E 's/^[[:space:]]*ssl_certificate(_key)?[[:space:]]+([^;]+);.*$/\2/')"

    if [[ "${cert_path}" == /etc/letsencrypt/* ]]; then
      host_cert_path="${DOCKER_DATA_DIR}/nginx/data/letsencrypt/${cert_path#/etc/letsencrypt/}"
    elif [[ "${cert_path}" == /data/* ]]; then
      host_cert_path="${DOCKER_DATA_DIR}/nginx/data/${cert_path#/data/}"
    else
      host_cert_path="${cert_path}"
    fi

    if [[ ! -f "${host_cert_path}" ]]; then
      log_warn "Skipping $(basename "${conf_file}"): referenced SSL file '${host_cert_path}' missing. Complete SSL setup first."
      return 1
    fi
  done < <(grep -E '^[[:space:]]*ssl_certificate(_key)?[[:space:]]+' "${conf_file}" || true)

  return 0
}

# ------------------------------------------------------------------------------
# Function: deploy_configs
# Description:
#   Synchronizes tracked configs from '.configs/' to live host volumes:
#     - Dockge compose.yml
#     - Homepage dashboard files
#     - qBittorrentVPN port-sync script
#     - Nginx Proxy Manager .conf files (with cert validation and reload)
# ------------------------------------------------------------------------------
deploy_configs() {
  init_and_sync_env
  log_info "Deploying tracked configurations to host paths..."

  # 1. Dockge orchestrator compose.yml
  if [[ -f "${REPO_DIR}/.configs/dockge/compose.yml" ]]; then
    sync_file "${REPO_DIR}/.configs/dockge/compose.yml" "${DOCKGE_DIR}/compose.yml" "0644" || true
    chown "${TARGET_USER}:${TARGET_GROUP}" "${DOCKGE_DIR}/compose.yml" 2>/dev/null || true
  fi

  # 2. Homepage dashboard configs
  if [[ -d "${REPO_DIR}/.configs/homepage" ]]; then
    local hp_file
    for hp_file in "${REPO_DIR}/.configs/homepage/"*; do
      [[ -f "${hp_file}" ]] || continue
      sync_file "${hp_file}" "${DOCKER_DATA_DIR}/homepage/data/$(basename "${hp_file}")" "0644" || true
    done
  fi

  # 3. qBittorrentVPN port sync script
  if [[ -f "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh" ]]; then
    sync_file "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh" "${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh" "0755" || true
    chown "${PUID:-1000}:${PGID:-100}" "${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh" 2>/dev/null || true
  fi

  # 4. NPM .conf files
  local npm_updated=0
  if [[ -d "${REPO_DIR}/.configs/nginx/nginx" ]]; then
    local subdir conf_file
    for subdir in "${NPM_CONFIG_SUBDIRS[@]}"; do
      [[ -d "${REPO_DIR}/.configs/nginx/nginx/${subdir}" ]] || continue
      for conf_file in "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"*; do
        [[ -f "${conf_file}" ]] || continue
        if npm_conf_certs_exist "${conf_file}" && sync_file "${conf_file}" "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}/$(basename "${conf_file}")" "0644"; then
          npm_updated=1
        fi
      done
    done
  fi

  # Reload Nginx if any proxy host was updated and container is running
  if [[ "${npm_updated}" -eq 1 ]] && docker ps --format '{{.Names}}' | grep -qx 'nginx'; then
    log_info "Reloading Nginx inside 'nginx' container..."
    docker exec nginx nginx -s reload
  fi
}

# ------------------------------------------------------------------------------
# Function: pull_configs
# Description:
#   Pulls live configurations from '${DOCKER_DATA_DIR}' into '${REPO_DIR}/.configs/'
#   for inspection and git tracking:
#     - Homepage YAML/CSS/JS files
#     - qBittorrentVPN set-qbt-port.sh
#     - NPM non-sensitive SQLite routing tables & generated .conf files
# ------------------------------------------------------------------------------
pull_configs() {
  init_and_sync_env
  log_info "Pulling live service configurations into ${REPO_DIR}/.configs/..."

  # 1. Homepage configs
  mkdir -p "${REPO_DIR}/.configs/homepage"
  if [[ -d "${DOCKER_DATA_DIR}/homepage/data" ]]; then
    local hp_src
    for hp_src in "${DOCKER_DATA_DIR}/homepage/data/"*.yaml "${DOCKER_DATA_DIR}/homepage/data/"*.yml "${DOCKER_DATA_DIR}/homepage/data/"*.css "${DOCKER_DATA_DIR}/homepage/data/"*.js; do
      [[ -f "${hp_src}" ]] && cp -p "${hp_src}" "${REPO_DIR}/.configs/homepage/$(basename "${hp_src}")"
    done
  fi

  # 2. qBittorrentVPN port sync script
  mkdir -p "${REPO_DIR}/.configs/qbittorrentvpn"
  if [[ -f "${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh" ]]; then
    cp -p "${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh" "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh"
    chmod 0755 "${REPO_DIR}/.configs/qbittorrentvpn/set-qbt-port.sh"
  fi

  # 3. NPM SQLite host tables dump
  mkdir -p "${REPO_DIR}/.configs/nginx/nginx"
  if [[ -f "${DOCKER_DATA_DIR}/nginx/data/db.sqlite" ]]; then
    if command -v sqlite3 >/dev/null 2>&1; then
      sqlite3 "${DOCKER_DATA_DIR}/nginx/data/db.sqlite" ".dump proxy_host dead_host redirection_host setting" > "${REPO_DIR}/.configs/nginx/npm_hosts.sql"
    else
      log_warn "sqlite3 not found on host; skipping npm_hosts.sql export."
    fi
  fi

  # 4. NPM .conf files
  if [[ -d "${DOCKER_DATA_DIR}/nginx/data/nginx" ]]; then
    local subdir
    for subdir in "${NPM_CONFIG_SUBDIRS[@]}"; do
      if [[ -d "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}" ]]; then
        mkdir -p "${REPO_DIR}/.configs/nginx/nginx/${subdir}"
        rm -f "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"* 2>/dev/null || true
        cp -rp "${DOCKER_DATA_DIR}/nginx/data/nginx/${subdir}/." "${REPO_DIR}/.configs/nginx/nginx/${subdir}/"
      fi
    done
  fi

  chown -R "${TARGET_USER}:${TARGET_GROUP}" "${REPO_DIR}/.configs" 2>/dev/null || true
  log_info "Completed pulling live configurations into .configs/."
}
