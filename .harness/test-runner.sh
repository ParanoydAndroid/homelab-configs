#!/usr/bin/env bash
# ==============================================================================
# Script: .harness/test-runner.sh
# Purpose: Master test runner for the homelab smoke and regression test suite.
# Usage:   ./.harness/test-runner.sh [suite_name | test_function_name]
#
# Examples:
#   ./.harness/test-runner.sh                 # Run all test suites
#   ./.harness/test-runner.sh conventions     # Run harness conventions only
#   ./.harness/test-runner.sh containers      # Run container healthchecks only
#   ./.harness/test-runner.sh routing         # Run virtual host routing tests only
#   ./.harness/test-runner.sh security        # Run negative security & auth tests only
#   ./.harness/test-runner.sh test_docker_up_seerr # Run a single test case
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source the test harness library
# shellcheck source=.harness/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Source all test suites
# shellcheck source=.harness/suites/test_conventions.sh
source "${SCRIPT_DIR}/suites/test_conventions.sh"
# shellcheck source=.harness/suites/test_containers.sh
source "${SCRIPT_DIR}/suites/test_containers.sh"
# shellcheck source=.harness/suites/test_direct_admin.sh
source "${SCRIPT_DIR}/suites/test_direct_admin.sh"
# shellcheck source=.harness/suites/test_routing.sh
source "${SCRIPT_DIR}/suites/test_routing.sh"
# shellcheck source=.harness/suites/test_interconnect.sh
source "${SCRIPT_DIR}/suites/test_interconnect.sh"
# shellcheck source=.harness/suites/test_negative_security.sh
source "${SCRIPT_DIR}/suites/test_negative_security.sh"
# shellcheck source=.harness/suites/test_backup.sh
source "${SCRIPT_DIR}/suites/test_backup.sh"

main() {
  local target="${1:-all}"
  SUITE_START_TIME="$(date +%s)"

  case "${target}" in
    all|"")
      suite_conventions
      suite_containers
      suite_direct_admin
      suite_routing
      suite_interconnect
      suite_negative_security
      suite_backup
      ;;
    conventions|harness)
      suite_conventions
      ;;
    containers|docker)
      suite_containers
      ;;
    direct|admin)
      suite_direct_admin
      ;;
    routing|vhost|vhosts)
      suite_routing
      ;;
    interconnect|dns|network)
      suite_interconnect
      ;;
    security|negative)
      suite_negative_security
      ;;
    backup|restic)
      suite_backup
      ;;
    test_*)
      init_suite "Single Test Execution"
      if declare -f "${target}" >/dev/null 2>&1; then
        run_test "${target}" "Targeted verification: ${target}"
      else
        printf "%bError:%b Test function '%s' not found in any loaded suite.\n" "${CLR_RED}" "${CLR_RESET}" "${target}" >&2
        exit 1
      fi
      ;;
    -h|--help|help)
      cat <<EOF
Usage: $(basename "$0") [target]

Targets:
  all             Run all test suites (default)
  conventions     Run agentic harness and repository conventions checks
  containers      Run container runtime and health checks
  direct          Run direct host management port checks
  routing         Run reverse proxy virtual host routing checks
  interconnect    Run inter-container DNS, socket, and VPN sync checks
  security        Run negative isolation, hardening, and auth checks
  backup          Run restic backup and automation checks
  test_<name>     Run a single test function directly
EOF
      exit 0
      ;;
    *)
      printf "%bError:%b Unknown test target '%s'. Run with --help for options.\n" "${CLR_RED}" "${CLR_RESET}" "${target}" >&2
      exit 1
      ;;
  esac

  print_summary
}

main "$@"
