#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_routing.sh
# Purpose: Verifies reverse proxy virtual host routing, SSL termination, and
#          HTTP status codes using client impersonation across the internal
#          'homelab' bridge network.
# ==============================================================================
set -euo pipefail

# Helper to execute client-impersonated HTTPS curl against NPM via radarr probe container
_curl_vhost() {
  local domain="$1"
  local path="${2:-/}"
  local expected_regex="${3:-^(200|301|302|307|308)$}"
  local npm_ip
  npm_ip="$(get_npm_bridge_ip)"

  local code
  code="$(docker exec radarr curl -ksS -o /dev/null -w '%{http_code}' \
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
  _curl_vhost "homepage.turing.home" "/" "^200$"
}

test_vhost_proxy_internal() {
  _curl_vhost "proxy.turing.home" "/" "^200$"
}

test_vhost_dockge_internal() {
  _curl_vhost "dockge.turing.home" "/" "^200$"
}

test_vhost_jellyfin_internal() {
  _curl_vhost "jellyfin.turing.home" "/web/index.html" "^200$"
}

test_vhost_radarr_internal() {
  _curl_vhost "radarr.turing.home" "/ping" "^200$"
}

test_vhost_sonarr_internal() {
  _curl_vhost "sonarr.turing.home" "/ping" "^200$"
}

test_vhost_prowlarr_internal() {
  _curl_vhost "prowlarr.turing.home" "/ping" "^200$"
}

test_vhost_flaresolverr_internal() {
  _curl_vhost "flaresolverr.turing.home" "/health" "^200$"
}

test_vhost_seerr_internal() {
  _curl_vhost "seerr.turing.home" "/api/v1/status" "^200$"
}

test_vhost_torrent_internal() {
  _curl_vhost "torrent.turing.home" "/" "^200$"
}

test_vhost_recipes_internal() {
  _curl_vhost "recipes.turing.home" "/" "^(200|302)$"
}

test_vhost_nas_internal() {
  _curl_vhost "nas.turing.home" "/" "^(200|302|307)$"
}

test_vhost_jellyfin_external() {
  _curl_vhost "jellyfin.kamaka.tech" "/web/index.html" "^200$"
}

test_vhost_recipes_external() {
  _curl_vhost "recipes.kamaka.tech" "/" "^(200|302)$"
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
