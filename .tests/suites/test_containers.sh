#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_containers.sh
# Purpose: Verifies container runtime states and healthchecks across all 15
#          services defined in the homelab environment.
# ==============================================================================
set -euo pipefail

# Helper to assert running state and healthy/none status for a single container.
# If an associated stack name is provided, checks whether the stack is enabled first.
_assert_container_running() {
  local container="$1"
  local stack="${2:-}"

  if [[ -n "${stack}" ]] && ! is_stack_enabled "${stack}"; then
    printf "Stack '%s' omitted or disabled" "${stack}"
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
  _assert_container_running "dockge"
}

test_docker_up_postgresql() {
  if ! is_stack_enabled "productivity" && ! is_stack_enabled "postgres"; then
    printf "Stack 'productivity' omitted or disabled"
    return 77
  fi
  _assert_container_running "postgresql"
}

test_docker_up_nginx() {
  if ! is_stack_enabled "ingress" && ! is_stack_enabled "nginx"; then
    printf "Stack 'ingress' omitted or disabled"
    return 77
  fi
  _assert_container_running "nginx"
}

test_docker_up_tailscale() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "tailscale"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  _assert_container_running "tailscale"
}

test_docker_up_homepage() {
  if ! is_stack_enabled "dashboard" && ! is_stack_enabled "homepage"; then
    printf "Stack 'dashboard' omitted or disabled"
    return 77
  fi
  _assert_container_running "homepage"
}

test_docker_up_jellyfin() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "jellyfin"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "jellyfin"
}

test_docker_up_wireguard_pia() {
  if ! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"; then
    printf "Stack 'torrent' omitted or disabled"
    return 77
  fi
  _assert_container_running "wireguard-pia"
}

test_docker_up_qbittorrentvpn() {
  if ! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn"; then
    printf "Stack 'torrent' omitted or disabled"
    return 77
  fi
  _assert_container_running "qbittorrentvpn"
}

test_docker_up_radarr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "radarr"
}

test_docker_up_sonarr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "sonarr"
}

test_docker_up_prowlarr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "prowlarr"
}

test_docker_up_flaresolverr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "flaresolverr"
}

test_docker_up_seerr() {
  if ! is_stack_enabled "media" && ! is_stack_enabled "seerr"; then
    printf "Stack 'media' omitted or disabled"
    return 77
  fi
  _assert_container_running "seerr"
}

test_docker_up_tandoor() {
  if ! is_stack_enabled "productivity" && ! is_stack_enabled "tandoor"; then
    printf "Stack 'productivity' omitted or disabled"
    return 77
  fi
  _assert_container_running "tandoor"
}

test_docker_up_cloudflared() {
  if ! is_stack_enabled "ingress" && ! is_stack_enabled "cloudflared"; then
    printf "Stack 'ingress' omitted or disabled"
    return 77
  fi
  _assert_container_running "cloudflared"
}

test_docker_up_vpn_bridge_pia() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "vpn-bridge"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  _assert_container_running "vpn-bridge-pia"
}

test_docker_up_vpn_bridge_tailscale() {
  if ! is_stack_enabled "mesh" && ! is_stack_enabled "vpn-bridge"; then
    printf "Stack 'mesh' omitted or disabled"
    return 77
  fi
  _assert_container_running "vpn-bridge-tailscale"
}

suite_containers() {
  init_suite "1. Container Runtime & Health Checks"

  run_test test_docker_up_dockge "Verify Dockge container is running and healthy"
  run_test test_docker_up_postgresql "Verify PostgreSQL container is running"
  run_test test_docker_up_nginx "Verify Nginx Proxy Manager container is running"
  run_test test_docker_up_tailscale "Verify Tailscale Subnet Router is running"
  run_test test_docker_up_vpn_bridge_pia "Verify VPN Bridge PIA WireGuard container is running and healthy"
  run_test test_docker_up_vpn_bridge_tailscale "Verify VPN Bridge Tailscale exit node container is running"
  run_test test_docker_up_homepage "Verify Homepage Dashboard is running and healthy"
  run_test test_docker_up_jellyfin "Verify Jellyfin media server is running and healthy"
  run_test test_docker_up_wireguard_pia "Verify WireGuard PIA VPN container is running and healthy"
  run_test test_docker_up_qbittorrentvpn "Verify qBittorrent BitTorrent client is running"
  run_test test_docker_up_radarr "Verify Radarr movie indexer is running"
  run_test test_docker_up_sonarr "Verify Sonarr TV indexer is running"
  run_test test_docker_up_prowlarr "Verify Prowlarr indexer aggregator is running"
  run_test test_docker_up_flaresolverr "Verify FlareSolverr proxy is running"
  run_test test_docker_up_seerr "Verify Seerr request management is running and healthy"
  run_test test_docker_up_tandoor "Verify Tandoor Recipes application server is running"
  run_test test_docker_up_cloudflared "Verify Cloudflare Zero Trust Tunnel is running"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_containers
  print_summary
fi
