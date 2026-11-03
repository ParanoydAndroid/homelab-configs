#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_routing.sh
# Purpose: Verifies reverse proxy virtual host routing, SSL termination, and
#          HTTP status codes using client impersonation across the internal
#          'homelab' bridge network.
# ==============================================================================
set -euo pipefail

# Helper to execute client-impersonated HTTPS curl against NPM via any available container on 'homelab'
_curl_vhost() {
  local domain="$1"
  local path="${2:-/}"
  local expected_regex="${3:-^(200|301|302|307|308)$}"
  local stack="${4:-}"

  if ! is_stack_enabled "ingress" && ! is_stack_enabled "nginx"; then
    printf "Reverse proxy stack 'ingress' omitted or disabled"
    return 77
  fi

  if [[ -n "${stack}" ]]; then
    local stack_active=0
    case "${stack}" in
      dashboard) is_stack_enabled "dashboard" || is_stack_enabled "homepage" && stack_active=1 ;;
      ingress) is_stack_enabled "ingress" || is_stack_enabled "nginx" && stack_active=1 ;;
      media) is_stack_enabled "media" || is_stack_enabled "jellyfin" || is_stack_enabled "sonarr-radarr" || is_stack_enabled "seerr" && stack_active=1 ;;
      torrent) is_stack_enabled "torrent" || is_stack_enabled "qbittorrentvpn" && stack_active=1 ;;
      productivity) is_stack_enabled "productivity" || is_stack_enabled "tandoor" && stack_active=1 ;;
      *) is_stack_enabled "${stack}" && stack_active=1 ;;
    esac
    if [[ "${stack_active}" -eq 0 ]]; then
      printf "Stack '%s' omitted or disabled" "${stack}"
      return 77
    fi
  fi

  local probe_container=""
  local c
  for c in radarr sonarr homepage jellyfin seerr nginx; do
    if docker inspect -f '{{.State.Status}}' "${c}" 2>/dev/null | grep -q "running"; then
      probe_container="${c}"
      break
    fi
  done

  if [[ -z "${probe_container}" ]]; then
    printf "No active probe container found on 'homelab' bridge network"
    return 77
  fi

  local npm_ip
  npm_ip="$(get_npm_bridge_ip)"

  local code
  code="$(docker exec "${probe_container}" curl -ksS -o /dev/null -w '%{http_code}' \
    --max-time 25 --retry 2 --retry-delay 1 \
    -A "Mozilla/5.0 (X11; Linux x86_64) HomelabSmokeTest/1.0" \
    --resolve "${domain}:443:${npm_ip}" \
    "https://${domain}${path}" 2>/dev/null || true)"
  [[ -z "${code}" ]] && code="000"

  if [[ "${code}" =~ ${expected_regex} ]]; then
    printf "HTTP %s" "${code}"
    return 0
  fi

  printf "Received HTTP %s (expected regex %s)" "${code}" "${expected_regex}"
  return 1
}

test_vhost_homepage_internal() {
  _curl_vhost "homepage.turing.home" "/" "^200$" "dashboard"
}

test_vhost_proxy_internal() {
  _curl_vhost "proxy.turing.home" "/" "^200$" "ingress"
}

test_vhost_dockge_internal() {
  _curl_vhost "dockge.turing.home" "/" "^200$"
}

test_vhost_jellyfin_internal() {
  _curl_vhost "jellyfin.turing.home" "/web/index.html" "^200$" "media"
}

test_vhost_radarr_internal() {
  _curl_vhost "radarr.turing.home" "/ping" "^200$" "media"
}

test_vhost_sonarr_internal() {
  _curl_vhost "sonarr.turing.home" "/ping" "^200$" "media"
}

test_vhost_prowlarr_internal() {
  _curl_vhost "prowlarr.turing.home" "/ping" "^200$" "media"
}

test_vhost_flaresolverr_internal() {
  _curl_vhost "flaresolverr.turing.home" "/health" "^200$" "media"
}

test_vhost_seerr_internal() {
  _curl_vhost "seerr.turing.home" "/api/v1/status" "^200$" "media"
}

test_vhost_torrent_internal() {
  _curl_vhost "torrent.turing.home" "/" "^200$" "torrent"
}

test_vhost_recipes_internal() {
  _curl_vhost "recipes.turing.home" "/" "^(200|302)$" "productivity"
}

test_vhost_nas_internal() {
  _curl_vhost "nas.turing.home" "/" "^(200|302|307)$"
}

test_vhost_jellyfin_external() {
  _curl_vhost "jellyfin.kamaka.tech" "/web/index.html" "^200$" "media"
}

test_vhost_recipes_external() {
  _curl_vhost "recipes.kamaka.tech" "/" "^(200|302)$" "productivity"
}

suite_routing() {
  init_suite "3. NPM Reverse Proxy VirtualHost Routing (Client Impersonation)"

  run_test test_vhost_homepage_internal "Route https://homepage.turing.home/"
  run_test test_vhost_proxy_internal "Route https://proxy.turing.home/ (NPM Admin UI)"
  run_test test_vhost_dockge_internal "Route https://dockge.turing.home/"
  run_test test_vhost_jellyfin_internal "Route https://jellyfin.turing.home/web/index.html"
  run_test test_vhost_radarr_internal "Route https://radarr.turing.home/ping"
  run_test test_vhost_sonarr_internal "Route https://sonarr.turing.home/ping"
  run_test test_vhost_prowlarr_internal "Route https://prowlarr.turing.home/ping"
  run_test test_vhost_flaresolverr_internal "Route https://flaresolverr.turing.home/health"
  run_test test_vhost_seerr_internal "Route https://seerr.turing.home/api/v1/status"
  run_test test_vhost_torrent_internal "Route https://torrent.turing.home/"
  run_test test_vhost_recipes_internal "Route https://recipes.turing.home/"
  run_test test_vhost_nas_internal "Route https://nas.turing.home/ (UGOS OS Portal)"
  run_test test_vhost_jellyfin_external "Route https://jellyfin.kamaka.tech/web/index.html (External)"
  run_test test_vhost_recipes_external "Route https://recipes.kamaka.tech/ (External)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_routing
  print_summary
fi
