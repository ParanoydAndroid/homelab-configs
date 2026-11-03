#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_interconnect.sh
# Purpose: Verifies internal container DNS resolution, service-to-service
#          communication paths, database TCP sockets, and background sync daemons.
# ==============================================================================
set -euo pipefail

test_interconnect_jellyfin_to_seerr() {
  if ! is_service_enabled "jellyfin" || ! is_service_enabled "seerr"; then
    printf "Service 'jellyfin' or 'seerr' omitted or disabled"
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
  if ! is_service_enabled "radarr" || ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'radarr' or 'qbittorrentvpn' omitted or disabled"
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
  if ! is_service_enabled "radarr" || ! is_service_enabled "prowlarr"; then
    printf "Service 'radarr' or 'prowlarr' omitted or disabled"
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
  if ! is_service_enabled "sonarr" || ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'sonarr' or 'qbittorrentvpn' omitted or disabled"
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
  if ! is_service_enabled "prowlarr" || ! is_service_enabled "flaresolverr"; then
    printf "Service 'prowlarr' or 'flaresolverr' omitted or disabled"
    return 77
  fi
  if docker exec prowlarr curl -fsS --max-time 15 "http://flaresolverr:8191/health" >/dev/null 2>&1; then
    printf "http://flaresolverr:8191/health accessible"
    return 0
  fi
  printf "Failed to reach http://flaresolverr:8191/health from prowlarr"
  return 1
}

test_interconnect_pia_to_qbittorrent_port_sync() {
  if ! is_service_enabled "wireguard-pia" || ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'wireguard-pia' or 'qbittorrentvpn' omitted or disabled"
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
  if ! is_service_enabled "tailscale"; then
    printf "Service 'tailscale' omitted or disabled"
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
  if ! is_service_enabled "vpn-bridge-pia"; then
    printf "Service 'vpn-bridge-pia' omitted or disabled"
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

test_interconnect_vpn_bridge_tailscale_backend_state() {
  if ! is_service_enabled "vpn-bridge-tailscale"; then
    printf "Service 'vpn-bridge-tailscale' omitted or disabled"
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

test_interconnect_qbittorrent_volume_write_permissions() {
  if ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'qbittorrentvpn' omitted or disabled"
    return 77
  fi
  local target_user="abc"
  local dirs=(/config /incomplete /media)
  local failed_dirs=()

  for dir in "${dirs[@]}"; do
    local probe="${dir}/.perm_probe_$$"
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

test_interconnect_qbittorrent_torrent_error_status() {
  if ! is_service_enabled "wireguard-pia" || ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'wireguard-pia' or 'qbittorrentvpn' omitted or disabled"
    return 77
  fi
  local errored_json errored_trimmed
  errored_json="$(docker exec wireguard-pia curl -fsS --max-time 15 "http://127.0.0.1:8081/api/v2/torrents/info?filter=errored" 2>/dev/null || true)"

  if [[ -z "${errored_json}" ]]; then
    printf "Failed to query qBittorrent API for errored torrents"
    return 1
  fi

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

test_interconnect_readarr_to_qbittorrent() {
  if ! is_service_enabled "readarr" || ! is_service_enabled "qbittorrentvpn"; then
    printf "Service 'readarr' or 'qbittorrentvpn' omitted or disabled"
    return 77
  fi
  local ver
  ver="$(docker exec readarr curl -fsS --max-time 15 "http://qbittorrentvpn:8081/api/v2/app/version" 2>/dev/null || true)"
  if [[ -n "${ver}" ]]; then
    printf "qBittorrent API responding (%s)" "${ver}"
    return 0
  fi
  printf "Failed to query qBittorrent API from readarr"
  return 1
}

test_interconnect_readarr_to_prowlarr() {
  if ! is_service_enabled "readarr" || ! is_service_enabled "prowlarr"; then
    printf "Service 'readarr' or 'prowlarr' omitted or disabled"
    return 77
  fi
  if docker exec readarr curl -fsS --max-time 15 "http://prowlarr:9696/ping" >/dev/null 2>&1; then
    printf "http://prowlarr:9696/ping accessible"
    return 0
  fi
  printf "Failed to reach http://prowlarr:9696/ping from readarr"
  return 1
}

test_interconnect_calibre_web_opds() {
  if ! is_service_enabled "calibre-web"; then
    printf "Service 'calibre-web' omitted or disabled"
    return 77
  fi
  local feed
  feed="$(docker exec readarr curl -fsS --max-time 15 -u admin:admin123 "http://calibre-web:8083/opds" 2>/dev/null || true)"
  if echo "${feed}" | grep -q "http://www.w3.org/2005/Atom"; then
    printf "OPDS Atom feed valid and responding"
    return 0
  fi
  printf "Failed to query valid OPDS Atom feed from calibre-web"
  return 1
}

suite_interconnect() {
  init_suite "4. Inter-Container DNS, Sockets & Service Interconnections"

  run_test test_interconnect_jellyfin_to_seerr "Check Jellyfin -> Seerr (http://seerr:5055/api/v1/status)"
  run_test test_interconnect_radarr_to_qbittorrent "Check Radarr -> qBittorrent (http://qbittorrentvpn:8081)"
  run_test test_interconnect_radarr_to_prowlarr "Check Radarr -> Prowlarr (http://prowlarr:9696/ping)"
  run_test test_interconnect_sonarr_to_qbittorrent "Check Sonarr -> qBittorrent (http://qbittorrentvpn:8081)"
  run_test test_interconnect_readarr_to_qbittorrent "Check Readarr -> qBittorrent (http://qbittorrentvpn:8081)"
  run_test test_interconnect_readarr_to_prowlarr "Check Readarr -> Prowlarr (http://prowlarr:9696/ping)"
  run_test test_interconnect_calibre_web_opds "Check Calibre-Web OPDS catalog endpoint (http://calibre-web:8083/opds)"
  run_test test_interconnect_prowlarr_to_flaresolverr "Check Prowlarr -> FlareSolverr (http://flaresolverr:8191/health)"
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
