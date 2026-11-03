#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_negative_security.sh
# Purpose: Verifies negative assertions: security hardening blocks, network
#          boundary isolation, and mandatory authentication enforcement.
# ==============================================================================
set -euo pipefail

test_security_postgres_port_isolated_from_host() {
  if ! is_service_enabled "postgresql"; then
    printf "Service 'postgresql' omitted or disabled"
    return 77
  fi
  if curl -sS --connect-timeout 2 "http://127.0.0.1:5432" >/dev/null 2>&1; then
    printf "Host port 5432 is unexpectedly accessible from host!"
    return 1
  fi
  printf "Port 5432 is not exposed on host interfaces (isolated to Docker bridge)"
  return 0
}

test_security_radarr_api_unauthenticated_rejected() {
  if ! is_service_enabled "radarr"; then
    printf "Service 'radarr' omitted or disabled"
    return 77
  fi
  local code
  code="$(docker exec radarr curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    "http://radarr:7878/api/v3/system/status" 2>/dev/null || true)"

  if [[ "${code}" == "401" ]]; then
    printf "HTTP 401 Unauthorized (Auth required and rejected as expected)"
    return 0
  fi

  printf "Received HTTP %s (expected 401 Unauthorized)" "${code}"
  return 1
}

test_security_sonarr_api_unauthenticated_rejected() {
  if ! is_service_enabled "sonarr"; then
    printf "Service 'sonarr' omitted or disabled"
    return 77
  fi
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

  run_test test_security_postgres_port_isolated_from_host "Confirm PostgreSQL port 5432 is isolated from host"
  run_test test_security_radarr_api_unauthenticated_rejected "Confirm Radarr REST API requires API key"
  run_test test_security_sonarr_api_unauthenticated_rejected "Confirm Sonarr REST API requires API key"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_negative_security
  print_summary
fi
