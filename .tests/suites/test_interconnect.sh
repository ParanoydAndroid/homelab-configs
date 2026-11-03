#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_interconnect.sh
# Purpose: Verifies internal container DNS resolution, service-to-service
#          communication paths, database TCP sockets, and background sync daemons.
# ==============================================================================
set -euo pipefail

test_interconnect_jellyfin_to_seerr() {
  if ! is_stack_enabled "media" && (! is_stack_enabled "jellyfin" || ! is_stack_enabled "seerr"); then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  if docker exec jellyfin curl -fsS --max-time 15 "http://seerr:5055/api/v1/status" >/dev/null 2>&1; then
    printf "http://seerr:5055/api/v1/status accessible"
    return 0
  fi
  printf "Failed to reach http://seerr:5055/api/v1/status from jellyfin"
  return 1
}

test_interconnect_radarr_to_qbittorrent() {
  if (! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr") || (! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"); then
    printf "Stack 'media' or 'torrent' omitted or disabled"
    return 77
  fi
  local ver
  ver="$(docker exec radarr curl -fsS --max-time 15 "http://qbittorrentvpn:8081/api/v2/app/version" 2>/dev/null || true)"
  if [[ -n "${ver}" ]]; then
    printf "qBittorrent API responding (%s)" "${ver}"
    return 0
  fi
  printf "Failed to query qBittorrent API from radarr"
  return 1
}

test_interconnect_radarr_to_prowlarr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  if docker exec radarr curl -fsS --max-time 15 "http://prowlarr:9696/ping" >/dev/null 2>&1; then
    printf "http://prowlarr:9696/ping accessible"
    return 0
  fi
  printf "Failed to reach http://prowlarr:9696/ping from radarr"
  return 1
}

test_interconnect_sonarr_to_qbittorrent() {
  if (! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr") || (! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"); then
    printf "Stack 'media' or 'torrent' omitted or disabled"
    return 77
  fi
  local ver
  ver="$(docker exec sonarr curl -fsS --max-time 15 "http://qbittorrentvpn:8081/api/v2/app/version" 2>/dev/null || true)"
  if [[ -n "${ver}" ]]; then
    printf "qBittorrent API responding (%s)" "${ver}"
    return 0
  fi
  printf "Failed to query qBittorrent API from sonarr"
  return 1
}

test_interconnect_prowlarr_to_flaresolverr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  if docker exec prowlarr curl -fsS --max-time 15 "http://flaresolverr:8191/health" >/dev/null 2>&1; then
    printf "http://flaresolverr:8191/health accessible"
    return 0
  fi
  printf "Failed to reach http://flaresolverr:8191/health from prowlarr"
  return 1
}

test_interconnect_tandoor_to_postgres() {
  if ! is_stack_enabled "productivity" && (! is_stack_enabled "tandoor" || ! is_stack_enabled "postgres"); then
    printf "Stack 'productivity' omitted or disabled"
    return 77
  fi
  if docker exec tandoor python3 -c "import socket; s = socket.create_connection(('postgresql', 5432), 15); s.close()" >/dev/null 2>&1; then
    printf "TCP socket to postgresql:5432 open"
    return 0
  fi
  printf "TCP socket to postgresql:5432 unreachable"
  return 1
}

test_interconnect_pia_to_qbittorrent_port_sync() {
  if ! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"; then
    printf "Stack 'torrent' omitted or disabled"
    return 77
  fi
  local pia_port qbt_port
  pia_port="$(docker exec wireguard-pia cat /pia-shared/port.dat 2>/dev/null || true)"
  qbt_port="$(docker exec wireguard-pia curl -fsS --max-time 15 "http://127.0.0.1:8081/api/v2/app/preferences" 2>/dev/null | grep -oE '"listen_port":[0-9]+' | cut -d: -f2 || true)"

  if [[ -n "${pia_port}" && "${pia_port}" == "${qbt_port}" ]]; then
    printf "Port sync verified (PIA: %s == qBittorrent: %s)" "${pia_port}" "${qbt_port}"
    return 0
  fi

  printf "Port mismatch (PIA port: '%s', qBittorrent listen_port: '%s')" "${pia_port}" "${qbt_port}"
  return 1
}

test_interconnect_tailscale_backend_state() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "tailscale"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  local ts_status
  ts_status="$(docker exec tailscale tailscale status --json 2>/dev/null || true)"
  if [[ -n "${ts_status}" ]] && echo "${ts_status}" | grep -qE '"BackendState":[[:space:]]*"Running"'; then
    printf "Tailscale subnet router authenticated and running (BackendState: Running)"
    return 0
  fi
  printf "Tailscale subnet router not running or unauthenticated"
  return 1
}

test_interconnect_vpn_bridge_pia_egress() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "vpn-bridge"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  local egress_info country org
  egress_info="$(docker exec vpn-bridge-pia curl -fsS --max-time 15 https://ipinfo.io/json 2>/dev/null || true)"
  if [[ -z "${egress_info}" ]]; then
    printf "Failed to query public IP egress from vpn-bridge-pia"
    return 1
  fi
  country="$(echo "${egress_info}" | grep -oE '"country":[[:space:]]*"[^"]+"' | cut -d'"' -f4 || true)"
  org="$(echo "${egress_info}" | grep -oE '"org":[[:space:]]*"[^"]+"' | cut -d'"' -f4 || true)"
  if [[ "${country}" == "US" ]]; then
    printf "Egress routed through US VPN endpoint (%s, %s)" "${country}" "${org}"
    return 0
  fi
  printf "Egress country mismatch (expected US, got: %s)" "${country}"
  return 1
}

# ------------------------------------------------------------------------------
# Function: test_interconnect_vpn_bridge_tailscale_backend_state
# Description:
#   Checks that the vpn-bridge-tailscale exit node container daemon is active
#   and authenticated on the Tailscale tailnet.
# ------------------------------------------------------------------------------
test_interconnect_vpn_bridge_tailscale_backend_state() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "vpn-bridge"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  local ts_status
  ts_status="$(docker exec vpn-bridge-tailscale tailscale status --json 2>/dev/null || true)"
  if [[ -n "${ts_status}" ]]; then
    if echo "${ts_status}" | grep -qE '"BackendState":[[:space:]]*"Running"'; then
      printf "VPN Bridge Tailscale exit node authenticated and running (BackendState: Running)"
      return 0
    elif echo "${ts_status}" | grep -qE '"BackendState":[[:space:]]*"NeedsLogin"'; then
      printf "VPN Bridge Tailscale exit node awaiting pre-auth key registration (BackendState: NeedsLogin)"
      return 77
    fi
  fi
  printf "VPN Bridge Tailscale exit node container not running or daemon unreachable"
  return 1
}

# ------------------------------------------------------------------------------
# Function: test_interconnect_qbittorrent_volume_write_permissions
# Description:
#   Verifies that the non-root container user ('abc', UID 1000) inside
#   'qbittorrentvpn' has write and delete permissions across all mounted persistent
#   storage directories (/config, /incomplete, /media). Prevents regressions
#   caused by host POSIX permission drift or UGOS proprietary ACL masks
#   (system.ugacl_self) blocking downloads and file movement.
# Arguments:
#   None.
# Outputs:
#   Writes human-readable diagnostic status or failure details to stdout.
# Side Effects:
#   Creates and immediately unlinks a temporary probe file (.perm_probe_<PID>)
#   in each target directory as user 'abc'.
# Returns:
#   0 on full write/delete success across all volumes; 1 if any directory fails.
# ------------------------------------------------------------------------------
test_interconnect_qbittorrent_volume_write_permissions() {
  if ! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"; then
    printf "Stack 'torrent' omitted or disabled"
    return 77
  fi
  local target_user="abc"
  local dirs=(/config /incomplete /media)
  local failed_dirs=()

  for dir in "${dirs[@]}"; do
    local probe="${dir}/.perm_probe_$$"
    # Execute write probe inside container under non-root user 'abc' (UID 1000)
    if ! docker exec -u "${target_user}" qbittorrentvpn sh -c "touch '${probe}' && rm -f '${probe}'" >/dev/null 2>&1; then
      failed_dirs+=("${dir}")
    fi
  done

  if [[ ${#failed_dirs[@]} -eq 0 ]]; then
    printf "Write permissions verified for user %s across all volume mounts (%s)" "${target_user}" "${dirs[*]}"
    return 0
  fi

  printf "Permission denied writing to volume mounts as user %s: %s" "${target_user}" "${failed_dirs[*]}"
  return 1
}

# ------------------------------------------------------------------------------
# Function: test_interconnect_qbittorrent_torrent_error_status
# Description:
#   Queries the qBittorrent WebAPI (/api/v2/torrents/info?filter=errored) from the
#   shared network namespace container ('wireguard-pia') to assert that zero
#   torrents have entered an errored state. Catches runtime file I/O failures,
#   permission errors, or corrupted torrent states.
# Arguments:
#   None.
# Outputs:
#   Writes verification summary or failure error counts to stdout.
# Side Effects:
#   Executes HTTP GET request against local qBittorrent WebAPI.
# Returns:
#   0 if zero torrents are errored; 1 if API fails or any errored torrents found.
# ------------------------------------------------------------------------------
test_interconnect_qbittorrent_torrent_error_status() {
  if ! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"; then
    printf "Stack 'torrent' omitted or disabled"
    return 77
  fi
  local errored_json errored_trimmed
  errored_json="$(docker exec wireguard-pia curl -fsS --max-time 15 "http://127.0.0.1:8081/api/v2/torrents/info?filter=errored" 2>/dev/null || true)"

  if [[ -z "${errored_json}" ]]; then
    printf "Failed to query qBittorrent API for errored torrents"
    return 1
  fi

  # Trim whitespace to verify an empty JSON array '[]'
  errored_trimmed="$(echo "${errored_json}" | tr -d '[:space:]')"
  if [[ "${errored_trimmed}" == "[]" ]]; then
    printf "Zero torrents in error state"
    return 0
  fi

  local count
  count="$(echo "${errored_json}" | grep -o '"hash":' | wc -l || echo "unknown")"
  printf "%s torrents reported in error state" "${count}"
  return 1
}

suite_interconnect() {
  init_suite "4. Inter-Container DNS, Sockets & Service Interconnections"

  run_test test_interconnect_jellyfin_to_seerr "Check Jellyfin -> Seerr (http://seerr:5055/api/v1/status)"
  run_test test_interconnect_radarr_to_qbittorrent "Check Radarr -> qBittorrent (http://qbittorrentvpn:8081)"
  run_test test_interconnect_radarr_to_prowlarr "Check Radarr -> Prowlarr (http://prowlarr:9696/ping)"
  run_test test_interconnect_sonarr_to_qbittorrent "Check Sonarr -> qBittorrent (http://qbittorrentvpn:8081)"
  run_test test_interconnect_prowlarr_to_flaresolverr "Check Prowlarr -> FlareSolverr (http://flaresolverr:8191/health)"
  run_test test_interconnect_tandoor_to_postgres "Check Tandoor -> PostgreSQL (postgresql:5432)"
  run_test test_interconnect_pia_to_qbittorrent_port_sync "Check WireGuard PIA port forward sync to qBittorrent"
  run_test test_interconnect_tailscale_backend_state "Check Tailscale Subnet Router status and authentication"
  run_test test_interconnect_vpn_bridge_pia_egress "Verify VPN Bridge PIA WireGuard egress through US endpoint"
  run_test test_interconnect_vpn_bridge_tailscale_backend_state "Check VPN Bridge Tailscale exit node status"
  run_test test_interconnect_qbittorrent_volume_write_permissions "Verify non-root volume write permissions in qbittorrentvpn"
  run_test test_interconnect_qbittorrent_torrent_error_status "Verify qBittorrent torrent queue has zero errored torrents"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_interconnect
  print_summary
fi
