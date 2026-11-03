#!/usr/bin/env bash
# ==============================================================================
# Suite:   .tests/suites/test_direct_admin.sh
# Purpose: Verifies direct host management ports and internal administrative
#          API endpoints bypass reverse proxy layer as emergency fallbacks.
# ==============================================================================
set -euo pipefail

test_direct_dockge_host_port() {
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:8010" 2>/dev/null || true)"
  [[ -z "${code}" ]] && code="000"

  if [[ "${code}" =~ ^(200|301|302)$ ]]; then
    printf "HTTP %s" "${code}"
    return 0
  fi

  printf "Received HTTP %s (expected 200, 301, or 302)" "${code}"
  return 1
}

test_direct_npm_admin_api() {
  if ! is_stack_enabled "ingress" && ! is_stack_enabled "nginx"; then
    printf "Stack 'ingress' omitted or disabled"
    return 77
  fi

  local probe_c=""
  local c
  for c in radarr sonarr homepage jellyfin seerr nginx; do
    if docker inspect -f '{{.State.Status}}' "${c}" 2>/dev/null | grep -q "running"; then
      probe_c="${c}"
      break
    fi
  done

  if [[ -z "${probe_c}" ]]; then
    printf "No active probe container found on 'homelab' bridge network"
    return 77
  fi

  local code
  code="$(docker exec "${probe_c}" curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "http://nginx:81/api/" 2>/dev/null || true)"
  [[ -z "${code}" ]] && code="000"

  if [[ "${code}" == "200" ]]; then
    printf "HTTP %s" "${code}"
    return 0
  fi

  printf "Received HTTP %s (expected 200)" "${code}"
  return 1
}

suite_direct_admin() {
  init_suite "2. Direct Admin Interfaces & Fallback Ports"

  run_test test_direct_dockge_host_port "Verify Dockge emergency host port (127.0.0.1:8010)"
  run_test test_direct_npm_admin_api "Verify NPM Admin UI API over bridge (http://nginx:81/api/)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  suite_direct_admin
  print_summary
fi
