#!/usr/bin/env bash
# ==============================================================================
# Script Name: set-qbt-port.sh
# Description:
#   Callback script invoked automatically by 'thrnz/docker-wireguard-pia'
#   (via the PORT_SCRIPT environment variable) whenever Private Internet Access
#   (PIA) assigns or refreshes a forwarded port over the WireGuard tunnel.
#
# Arguments:
#   $1 (PORT) - Dynamically allocated incoming TCP/UDP port number provided by
#               PIA's NextGen port-forwarding API.
#
# Operation:
#   Uses curl with built-in connection-refused retries (--retry-connrefused)
#   to wait until qBittorrent's WebUI HTTP listener (127.0.0.1:8081 inside the
#   shared container network namespace) is ready, then sends an HTTP POST
#   request to '/api/v2/app/setPreferences' to update 'listen_port' to '$1'.
#   Because 'WebUI\LocalHostAuth=false' is enabled in 'qBittorrent.conf',
#   localhost API calls inside the isolated container namespace do not require
#   session cookie authentication.
# ==============================================================================

set -euo pipefail

PORT="${1:?ERROR: No port number argument provided to set-qbt-port.sh}"

printf "[INFO] set-qbt-port.sh: Updating qBittorrent listen_port to %s...\n" "${PORT}"

curl -fsS \
  --retry 30 \
  --retry-delay 2 \
  --retry-connrefused \
  --data-urlencode "json={\"listen_port\":${PORT}}" \
  "http://127.0.0.1:8081/api/v2/app/setPreferences"

printf "[INFO] set-qbt-port.sh: Successfully set qBittorrent listen_port=%s.\n" "${PORT}"
