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
#   Waits until qBittorrent's WebUI HTTP listener (127.0.0.1:8081 inside the
#   shared container network namespace) is ready, then sends an HTTP POST
#   request to '/api/v2/app/setPreferences' to update 'listen_port' to '$1'.
#   Because 'WebUI\LocalHostAuth=false' is enabled in 'qBittorrent.conf',
#   localhost API calls inside the isolated container namespace do not require
#   session cookie authentication.
# ==============================================================================

set -euo pipefail

PORT="${1:-}"
if [[ -z "${PORT}" ]]; then
  printf "[ERROR] set-qbt-port.sh: No port number argument provided.\n" >&2
  exit 1
fi

printf "[INFO] set-qbt-port.sh: Updating qBittorrent listen_port to %s...\n" "${PORT}"

# Retry up to 30 times (2 seconds apart) in case the WireGuard container
# negotiates the port before the companion qBittorrent container finishes
# starting its HTTP server on 127.0.0.1:8081.
for attempt in $(seq 1 30); do
  if curl -fsS \
    --retry 0 \
    --data-urlencode "json={\"listen_port\":${PORT}}" \
    "http://127.0.0.1:8081/api/v2/app/setPreferences" >/dev/null 2>&1; then
    printf "[INFO] set-qbt-port.sh: Successfully set qBittorrent listen_port=%s (attempt %d).\n" "${PORT}" "${attempt}"
    exit 0
  fi
  sleep 2
done

printf "[ERROR] set-qbt-port.sh: Failed to update qBittorrent listen_port after 30 attempts.\n" >&2
exit 1

