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
#   request to '/api/v2/app/setPreferences' to configure:
#     1. 'listen_port' - Sets active listening port to PIA forwarded port ($1).
#     2. 'disk_cache' (512 MiB) - Allocates in-memory write buffer to smooth out
#        random I/O and prevent mechanical HDD thrashing.
#     3. 'enable_piece_extent_affinity' (true) - Instructs libtorrent to write
#        contiguous file chunks, minimizing Btrfs fragmentation.
#     4. 'enable_upload_suggestions' (true) - Enables BEP 54 suggestion mode
#        for peer piece allocation alignment.
#     5. 'current_network_interface' ("wg0") - Enforces strict socket binding
#        to WireGuard tunnel interface.
#     6. 'upnp' (false) - Disables redundant router-level UPnP/NAT-PMP requests.
#     7. 'temp_path' ("/incomplete") & 'temp_path_enabled' (true) - Routes active
#        downloads to high-IOPS NVMe scratch storage.
#
#   Because 'WebUI\LocalHostAuth=false' is enabled in 'qBittorrent.conf',
#   localhost API calls inside the isolated container namespace do not require
#   session cookie authentication.
# ==============================================================================
set -euo pipefail

PORT="${1:?ERROR: No port number argument provided to set-qbt-port.sh}"

printf "[INFO] set-qbt-port.sh: Synchronizing qBittorrent listen_port (%s) and anti-thrashing preferences...\n" "${PORT}"

# Construct preference payload
PREFS_JSON=$(cat <<EOF
{
  "listen_port": ${PORT},
  "disk_cache": 512,
  "enable_piece_extent_affinity": true,
  "enable_upload_suggestions": true,
  "current_network_interface": "wg0",
  "upnp": false,
  "temp_path": "/incomplete",
  "temp_path_enabled": true
}
EOF
)

curl -fsS \
  --retry 30 \
  --retry-delay 2 \
  --retry-connrefused \
  --data-urlencode "json=${PREFS_JSON}" \
  "http://127.0.0.1:8081/api/v2/app/setPreferences"

printf "[INFO] set-qbt-port.sh: Successfully updated qBittorrent listen_port=%s and optimized preferences.\n" "${PORT}"
