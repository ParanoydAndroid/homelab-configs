#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_negative_security.sh
# Purpose: Verifies negative assertions: security hardening blocks, network
#          boundary isolation, and mandatory authentication enforcement.
# ==============================================================================
set -euo pipefail

test_security_jellyfin_metrics_blocked() {
  local npm_ip code
  npm_ip="$(get_npm_bridge_ip)"
  code="$(docker exec radarr curl -ksS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    -A "Mozilla/5.0 (X11; Linux x86_64) HomelabSmokeTest/1.0" \
    --resolve "jellyfin.kamaka.tech:443:${npm_ip}" \
    "https://jellyfin.kamaka.tech/metrics" 2>/dev/null || true)"

  if [[ "${code}" == "403" ]]; then
    printf "HTTP 403 Forbidden (Blocked as expected)"
    return 0
  fi
  printf "Received HTTP %s (expected 403 Forbidden)" "${code}"
  return 1
}

test_security_jellyfin_swagger_blocked() {
  local npm_ip code
  npm_ip="$(get_npm_bridge_ip)"
  code="$(docker exec radarr curl -ksS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    -A "Mozilla/5.0 (X11; Linux x86_64) HomelabSmokeTest/1.0" \
    --resolve "jellyfin.kamaka.tech:443:${npm_ip}" \
    "https://jellyfin.kamaka.tech/swagger" 2>/dev/null || true)"

  if [[ "${code}" == "403" ]]; then
    printf "HTTP 403 Forbidden (Blocked as expected)"
    return 0
  fi
  printf "Received HTTP %s (expected 403 Forbidden)" "${code}"
  return 1
}

test_security_jellyfin_api_docs_blocked() {
  local npm_ip code
  npm_ip="$(get_npm_bridge_ip)"
  code="$(docker exec radarr curl -ksS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    -A "Mozilla/5.0 (X11; Linux x86_64) HomelabSmokeTest/1.0" \
    --resolve "jellyfin.kamaka.tech:443:${npm_ip}" \
    "https://jellyfin.kamaka.tech/api-docs" 2>/dev/null || true)"

  if [[ "${code}" == "403" ]]; then
    printf "HTTP 403 Forbidden (Blocked as expected)"
    return 0
  fi
  printf "Received HTTP %s (expected 403 Forbidden)" "${code}"
  return 1
}

test_security_postgres_port_isolated_from_host() {
  # Port 5432 must NOT be bound to host 0.0.0.0 or 127.0.0.1
  if curl -sS --connect-timeout 2 "http://127.0.0.1:5432" >/dev/null 2>&1; then
    printf "Host port 5432 is unexpectedly accessible from host!"
    return 1
  fi
  printf "Port 5432 is not exposed on host interfaces (isolated to Docker bridge)"
  return 0
}

test_security_npm_api_unauthenticated_rejected() {
  # Accessing protected NPM user management endpoint without Bearer token must return HTTP 401 or 403
  local code
  code="$(docker exec radarr curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    "http://nginx:81/api/users" 2>/dev/null || true)"

  if [[ "${code}" =~ ^(401|403)$ ]]; then
    printf "HTTP %s (Auth required and rejected as expected)" "${code}"
    return 0
  fi

  printf "Received HTTP %s (expected 401 or 403)" "${code}"
  return 1
}

test_security_radarr_api_unauthenticated_rejected() {
  # Requesting Radarr movie REST API without an API key must return HTTP 401 Unauthorized
  local code
  code="$(docker exec radarr curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    "http://radarr:7878/api/v3/movie" 2>/dev/null || true)"

  if [[ "${code}" == "401" ]]; then
    printf "HTTP 401 Unauthorized (Auth required and rejected as expected)"
    return 0
  fi

  printf "Received HTTP %s (expected 401 Unauthorized)" "${code}"
  return 1
}

test_security_sonarr_api_unauthenticated_rejected() {
  # Requesting Sonarr series REST API without an API key must return HTTP 401 Unauthorized
  local code
  code="$(docker exec sonarr curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    "http://sonarr:8989/api/v3/series" 2>/dev/null || true)"

  if [[ "${code}" == "401" ]]; then
    printf "HTTP 401 Unauthorized (Auth required and rejected as expected)"
    return 0
  fi

  printf "Received HTTP %s (expected 401 Unauthorized)" "${code}"
  return 1
}

suite_negative_security() {
  init_suite "5. Security Hardening, Isolation & Authentication Rejection"

  run_test test_security_jellyfin_metrics_blocked "Confirm /metrics on external Jellyfin returns HTTP 403"
  run_test test_security_jellyfin_swagger_blocked "Confirm /swagger on external Jellyfin returns HTTP 403"
  run_test test_security_jellyfin_api_docs_blocked "Confirm /api-docs on external Jellyfin returns HTTP 403"
  run_test test_security_postgres_port_isolated_from_host "Confirm PostgreSQL port 5432 is isolated from host"
  run_test test_security_npm_api_unauthenticated_rejected "Confirm NPM Admin API requires Bearer authentication"
  run_test test_security_radarr_api_unauthenticated_rejected "Confirm Radarr REST API requires API key"
  run_test test_security_sonarr_api_unauthenticated_rejected "Confirm Sonarr REST API requires API key"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_negative_security
  print_summary
fi
