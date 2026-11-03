#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_routing.sh
# Purpose: Verifies reverse proxy virtual host routing, SSL termination, and
#          HTTP status codes using client impersonation across the internal
#          'homelab' bridge network.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: _curl_vhost
# Description:
#   Executes client-impersonated HTTPS curl against NPM via any available
#   container on the 'homelab' bridge network.
# Arguments:
#   $1 (domain)         - Virtual host FQDN to query.
#   $2 (path)           - URI path (defaults to '/').
#   $3 (expected_regex) - Regex pattern of acceptable HTTP status codes.
#   $4 (service)        - Optional target service identifier. Skips if disabled.
# ------------------------------------------------------------------------------
_curl_vhost() {
  local domain="$1"
  local path="${2:-/}"
  local expected_regex="${3:-^(200|301|302|307|308)$}"
  local service="${4:-}"

  if ! is_service_enabled "nginx" && ! is_service_enabled "caddy"; then
    printf "Reverse proxy service ('caddy' or 'nginx') omitted or disabled"
    return 77
  fi

  if [[ -n "${service}" ]] && ! is_service_enabled "${service}"; then
    printf "Target service '%s' omitted or disabled" "${service}"
    return 77
  fi

  local probe_container=""
  local c
  for c in radarr sonarr homepage jellyfin seerr; do
    if is_service_enabled "${c}" && docker inspect -f '{{.State.Status}}' "${c}" 2>/dev/null | grep -q "running"; then
      probe_container="${c}"
      break
    fi
  done

  if [[ -z "${probe_container}" ]]; then
    printf "No active probe container found on 'homelab' bridge network"
    return 77
  fi

  local ingress_ip
  ingress_ip="$(get_ingress_bridge_ip)"

  local code
  code="$(docker exec "${probe_container}" curl -ksS -o /dev/null -w '%{http_code}' \
    --max-time 25 --retry 2 --retry-delay 1 \
    -A "Mozilla/5.0 (X11; Linux x86_64) HomelabSmokeTest/1.0" \
    --resolve "${domain}:443:${ingress_ip}" \
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
  _curl_vhost "homepage.kamaka.tech" "/" "^200$" "homepage"
}

test_vhost_dockge_internal() {
  _curl_vhost "dockge.kamaka.tech" "/" "^200$"
}

test_vhost_jellyfin_internal() {
  _curl_vhost "jellyfin.kamaka.tech" "/web/index.html" "^200$" "jellyfin"
}

test_vhost_radarr_internal() {
  _curl_vhost "radarr.kamaka.tech" "/ping" "^200$" "radarr"
}

test_vhost_sonarr_internal() {
  _curl_vhost "sonarr.kamaka.tech" "/ping" "^200$" "sonarr"
}

test_vhost_prowlarr_internal() {
  _curl_vhost "prowlarr.kamaka.tech" "/ping" "^200$" "prowlarr"
}

test_vhost_flaresolverr_internal() {
  _curl_vhost "flaresolverr.kamaka.tech" "/health" "^200$" "flaresolverr"
}

test_vhost_seerr_internal() {
  _curl_vhost "seerr.kamaka.tech" "/api/v1/status" "^200$" "seerr"
}

test_vhost_torrent_internal() {
  _curl_vhost "torrent.kamaka.tech" "/" "^200$" "qbittorrentvpn"
}

test_vhost_mealie_internal() {
  _curl_vhost "recipes.kamaka.tech" "/" "^200$" "mealie"
}

test_vhost_nas_internal() {
  _curl_vhost "nas.kamaka.tech" "/" "^(200|302|307)$"
}

test_vhost_download_internal() {
  _curl_vhost "download.kamaka.tech" "/" "^200$"
}

test_vhost_jellyfin_external() {
  _curl_vhost "jellyfin.kamakakai.com" "/web/index.html" "^200$" "jellyfin"
}

test_vhost_mealie_external() {
  _curl_vhost "recipes.kamakakai.com" "/" "^200$" "mealie"
}

test_vhost_mom_external() {
  _curl_vhost "mom.kamakakai.com" "/" "^200$" "mealie"
}

suite_routing() {
  init_suite "3. Reverse Proxy VirtualHost Routing (Client Impersonation)"

  run_test test_vhost_homepage_internal "Route https://homepage.kamaka.tech/"
  run_test test_vhost_dockge_internal "Route https://dockge.kamaka.tech/"
  run_test test_vhost_jellyfin_internal "Route https://jellyfin.kamaka.tech/web/index.html"
  run_test test_vhost_radarr_internal "Route https://radarr.kamaka.tech/ping"
  run_test test_vhost_sonarr_internal "Route https://sonarr.kamaka.tech/ping"
  run_test test_vhost_prowlarr_internal "Route https://prowlarr.kamaka.tech/ping"
  run_test test_vhost_flaresolverr_internal "Route https://flaresolverr.kamaka.tech/health"
  run_test test_vhost_seerr_internal "Route https://seerr.kamaka.tech/api/v1/status"
  run_test test_vhost_torrent_internal "Route https://torrent.kamaka.tech/"
  run_test test_vhost_mealie_internal "Route https://recipes.kamaka.tech/"
  run_test test_vhost_nas_internal "Route https://nas.kamaka.tech/ (UGOS OS Portal)"
  run_test test_vhost_download_internal "Route https://download.kamaka.tech/ (File Delivery)"
  run_test test_vhost_jellyfin_external "Route https://jellyfin.kamakakai.com/web/index.html (External)"
  run_test test_vhost_mealie_external "Route https://recipes.kamakakai.com/ (External)"
  run_test test_vhost_mom_external "Route https://mom.kamakakai.com/ (External)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_routing
  print_summary
fi
