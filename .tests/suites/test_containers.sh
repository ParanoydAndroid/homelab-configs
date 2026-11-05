#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_containers.sh
# Purpose: Verifies container runtime states and healthchecks across all
#          services defined in the homelab environment.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: assert_service_running
# Description:
#   Helper to assert running state and healthy/none status for a service's container.
#   If the service is omitted or disabled in compose.yml, returns 77 (SKIP).
# Arguments:
#   $1 (service)   - Service identifier or container name.
#   $2 (container) - Optional container name override (defaults to $1).
# ------------------------------------------------------------------------------
assert_service_running() {
  local service="$1"
  local container="${2:-$1}"

  if ! is_service_enabled "${service}"; then
    printf "Service '%s' omitted or disabled" "${service}"
    return 77
  fi

  local state health
  state="$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null || echo "missing")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}" 2>/dev/null || echo "none")"

  if [[ "${state}" != "running" ]]; then
    printf "State is '%s' (expected 'running')" "${state}"
    return 1
  fi

  if [[ "${health}" == "unhealthy" ]]; then
    printf "Health is '%s'" "${health}"
    return 1
  fi

  printf "running (health: %s)" "${health}"
  return 0
}

test_docker_up_dockge() {
  local state health
  state="$(docker inspect -f '{{.State.Status}}' "dockge" 2>/dev/null || echo "missing")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "dockge" 2>/dev/null || echo "none")"
  if [[ "${state}" != "running" ]]; then
    printf "State is '%s' (expected 'running')" "${state}"
    return 1
  fi
  printf "running (health: %s)" "${health}"
}

test_docker_up_caddy() {
  assert_service_running "caddy"
}

test_docker_up_tailscale() {
  assert_service_running "tailscale"
}

test_docker_up_vpn_bridge_pia() {
  assert_service_running "vpn-bridge-pia"
}

test_docker_up_vpn_bridge_tailscale() {
  assert_service_running "vpn-bridge-tailscale"
}

test_docker_up_homepage() {
  assert_service_running "homepage"
}

test_docker_up_jellyfin() {
  assert_service_running "jellyfin"
}

test_docker_up_wireguard_pia() {
  assert_service_running "wireguard-pia"
}

test_docker_up_qbittorrent() {
  assert_service_running "qbittorrent"
}

test_docker_up_radarr() {
  assert_service_running "radarr"
}

test_docker_up_sonarr() {
  assert_service_running "sonarr"
}

test_docker_up_prowlarr() {
  assert_service_running "prowlarr"
}

test_docker_up_flaresolverr() {
  assert_service_running "flaresolverr"
}

test_docker_up_seerr() {
  assert_service_running "seerr"
}

test_docker_up_mealie() {
  assert_service_running "mealie"
}

test_docker_up_cloudflared() {
  assert_service_running "cloudflared"
}

test_docker_up_calibre_web() {
  assert_service_running "calibre-web"
}

test_docker_up_bindery() {
  assert_service_running "bindery"
}

test_docker_up_royalroad_sync() {
  assert_service_running "royalroad-sync"
}

test_docker_up_cleanuparr() {
  assert_service_running "cleanuparr"
}

suite_containers() {
  init_suite "1. Container Runtime & Health Checks"

  run_test test_docker_up_dockge "Verify Dockge container is running and healthy"
  run_test test_docker_up_caddy "Verify Caddy reverse proxy container is running"
  run_test test_docker_up_tailscale "Verify Tailscale Subnet Router is running"
  run_test test_docker_up_vpn_bridge_pia "Verify VPN Bridge PIA WireGuard container is running and healthy"
  run_test test_docker_up_vpn_bridge_tailscale "Verify VPN Bridge Tailscale exit node container is running"
  run_test test_docker_up_homepage "Verify Homepage Dashboard is running and healthy"
  run_test test_docker_up_jellyfin "Verify Jellyfin media server is running and healthy"
  run_test test_docker_up_wireguard_pia "Verify WireGuard PIA VPN container is running and healthy"
  run_test test_docker_up_qbittorrent "Verify qBittorrent BitTorrent client is running"
  run_test test_docker_up_radarr "Verify Radarr movie indexer is running"
  run_test test_docker_up_sonarr "Verify Sonarr TV indexer is running"
  run_test test_docker_up_prowlarr "Verify Prowlarr indexer aggregator is running"
  run_test test_docker_up_flaresolverr "Verify FlareSolverr proxy is running"
  run_test test_docker_up_seerr "Verify Seerr request management is running and healthy"
  run_test test_docker_up_mealie "Verify Mealie recipe manager is running"
  run_test test_docker_up_cloudflared "Verify Cloudflare Zero Trust Tunnel is running"
  run_test test_docker_up_calibre_web "Verify Calibre-Web e-book catalog manager is running"
  run_test test_docker_up_bindery "Verify Bindery book manager is running"
  run_test test_docker_up_royalroad_sync "Verify Royal Road sync worker is running"
  run_test test_docker_up_cleanuparr "Verify Cleanuparr queue manager container is running and healthy"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_containers
  print_summary
fi
