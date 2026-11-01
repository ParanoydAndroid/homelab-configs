#!/usr/bin/env bash
# ==============================================================================
# Script: .tests/run.sh
# Purpose: Master test runner for the homelab smoke and regression test suite.
# Usage:   ./.tests/run.sh [suite_name | test_function_name]
#
# Examples:
#   ./.tests/run.sh                 # Run all test suites
#   ./.tests/run.sh containers      # Run container healthchecks only
#   ./.tests/run.sh routing         # Run virtual host routing tests only
#   ./.tests/run.sh security        # Run negative security & auth tests only
#   ./.tests/run.sh test_docker_up_seerr # Run a single test case
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the test harness library
# shellcheck source=.tests/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Source all test suites
# shellcheck source=.tests/suites/test_containers.sh
source "${SCRIPT_DIR}/suites/test_containers.sh"
# shellcheck source=.tests/suites/test_direct_admin.sh
source "${SCRIPT_DIR}/suites/test_direct_admin.sh"
# shellcheck source=.tests/suites/test_routing.sh
source "${SCRIPT_DIR}/suites/test_routing.sh"
# shellcheck source=.tests/suites/test_interconnect.sh
source "${SCRIPT_DIR}/suites/test_interconnect.sh"
# shellcheck source=.tests/suites/test_negative_security.sh
source "${SCRIPT_DIR}/suites/test_negative_security.sh"
# shellcheck source=.tests/suites/test_backup.sh
source "${SCRIPT_DIR}/suites/test_backup.sh"

main() {
  local target="${1:-all}"
  SUITE_START_TIME="$(date +%s)"

  case "${target}" in
    all|"")
      suite_containers
      suite_direct_admin
      suite_routing
      suite_interconnect
      suite_negative_security
      suite_backup
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
