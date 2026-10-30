#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/system.sh
# Description:
#   Host OS remediations and external Docker network provisioning for the
#   homelab environment.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: remediate_godebug
# Description:
#   Remediates the UGREEN NAS OS defect where 'GODEBUG=tlskyber=0' is injected
#   globally, which causes Go 1.23+ binaries to panic on startup.
# ------------------------------------------------------------------------------
remediate_godebug() {
  log_info "Checking UGREEN NAS GODEBUG=tlskyber=0 configuration..."
  local systemd_changed=0

  # Check login shell profile script (/etc/profile.d/go.sh)
  if [[ -f /etc/profile.d/go.sh ]] && grep -qE '^[[:space:]]*export[[:space:]]+GODEBUG=tlskyber=0' /etc/profile.d/go.sh; then
    log_info "Commenting out export GODEBUG=tlskyber=0 in /etc/profile.d/go.sh"
    sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
  fi

  # Check systemd global manager config (/etc/systemd/system.conf)
  if [[ -f /etc/systemd/system.conf ]] && grep -qE '^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"' /etc/systemd/system.conf; then
    log_info "Commenting out DefaultEnvironment=\"GODEBUG=tlskyber=0\" in /etc/systemd/system.conf"
    sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
    systemd_changed=1
  fi

  # Unset GODEBUG in running systemd managers
  systemctl unset-environment GODEBUG 2>/dev/null || true
  systemctl --user unset-environment GODEBUG 2>/dev/null || true

  if [[ "${systemd_changed}" -eq 1 ]]; then
    log_info "Reloading systemd manager configuration (daemon-reexec)..."
    systemctl daemon-reexec
  fi
}

# ------------------------------------------------------------------------------
# Function: ensure_networks
# Description:
#   Idempotently verifies and creates the two external Docker networks:
#     1. 'homelab': Bridge network (192.168.255.0/24) for backend interconnections.
#     2. 'external_npm': Macvlan network on the physical LAN interface.
# Globals Read:
#   EXTERNAL_NPM_SUBNET, EXTERNAL_NPM_GATEWAY, EXTERNAL_NPM_PARENT
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
