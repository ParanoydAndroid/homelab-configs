#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_interconnect.sh
# Purpose: Verifies internal container DNS resolution, service-to-service
#          communication paths, database TCP sockets, and background sync daemons.
# ==============================================================================
set -euo pipefail

test_interconnect_jellyfin_to_seerr() {
  if docker exec jellyfin curl -fsS --max-time 15 "http://seerr:5055/api/v1/status" >/dev/null 2>&1; then
    printf "http://seerr:5055/api/v1/status accessible"
    return 0
  fi
  printf "Failed to reach http://seerr:5055/api/v1/status from jellyfin"
  return 1
}

test_interconnect_radarr_to_qbittorrent() {
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
  if docker exec radarr curl -fsS --max-time 15 "http://prowlarr:9696/ping" >/dev/null 2>&1; then
    printf "http://prowlarr:9696/ping accessible"
    return 0
  fi
  printf "Failed to reach http://prowlarr:9696/ping from radarr"
  return 1
}

test_interconnect_sonarr_to_qbittorrent() {
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
  if docker exec prowlarr curl -fsS --max-time 15 "http://flaresolverr:8191/health" >/dev/null 2>&1; then
    printf "http://flaresolverr:8191/health accessible"
    return 0
  fi
  printf "Failed to reach http://flaresolverr:8191/health from prowlarr"
  return 1
}

test_interconnect_tandoor_to_postgres() {
  if docker exec tandoor python3 -c "import socket; s = socket.create_connection(('postgresql', 5432), 15); s.close()" >/dev/null 2>&1; then
    printf "TCP socket to postgresql:5432 open"
    return 0
  fi
  printf "TCP socket to postgresql:5432 unreachable"
  return 1
}

test_interconnect_pia_to_qbittorrent_port_sync() {
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
  local ts_status
  ts_status="$(docker exec tailscale tailscale status --json 2>/dev/null || true)"
  if [[ -n "${ts_status}" ]] && echo "${ts_status}" | grep -qE '"BackendState":[[:space:]]*"Running"'; then
    printf "Tailscale subnet router authenticated and running (BackendState: Running)"
    return 0
  fi
  printf "Tailscale subnet router not running or unauthenticated"
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_interconnect
  print_summary
fi
