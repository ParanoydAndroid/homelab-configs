#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_negative_security.sh
# Purpose: Verifies negative assertions: security hardening blocks, network
#          boundary isolation, and mandatory authentication enforcement.
# ==============================================================================
set -euo pipefail

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

  run_test test_security_radarr_api_unauthenticated_rejected "Confirm Radarr REST API requires API key"
  run_test test_security_sonarr_api_unauthenticated_rejected "Confirm Sonarr REST API requires API key"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_negative_security
  print_summary
fi
