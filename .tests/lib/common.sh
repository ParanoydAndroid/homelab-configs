#!/usr/bin/env bash
# ==============================================================================
# Script: .tests/lib/common.sh
# Purpose: Shared test harness core, assertion library, and result aggregator
#          for the homelab smoke and regression test suite.
# Usage:   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh" (or relative)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Test Counter Globals
# ------------------------------------------------------------------------------
TEST_COUNT_TOTAL=0
TEST_COUNT_PASS=0
TEST_COUNT_FAIL=0
TEST_COUNT_SKIP=0
SUITE_START_TIME=0

# Formatting and Colors (disabled if not a TTY or NO_COLOR is set)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CLR_RESET="\033[0m"
  CLR_BOLD="\033[1m"
  CLR_GREEN="\033[32m"
  CLR_RED="\033[31m"
  CLR_YELLOW="\033[33m"
  CLR_CYAN="\033[36m"
  CLR_GRAY="\033[90m"
else
  CLR_RESET=""
  CLR_BOLD=""
  CLR_GREEN=""
  CLR_RED=""
  CLR_YELLOW=""
  CLR_CYAN=""
  CLR_GRAY=""
fi

# ------------------------------------------------------------------------------
# Function: init_suite
# Description:
#   Initializes test execution timer and prints the suite title header.
# Arguments:
#   $1 (suite_title) - Display name for the test suite.
# ------------------------------------------------------------------------------
init_suite() {
  local suite_title="$1"
  SUITE_START_TIME="$(date +%s)"
  printf "\n%b=== Suite: %s ===%b\n" "${CLR_BOLD}${CLR_CYAN}" "${suite_title}" "${CLR_RESET}"
}

# ------------------------------------------------------------------------------
# Function: record_pass
# Description:
#   Records a successful test assertion and increments pass counter.
# Arguments:
#   $1 (test_name) - Symbolic test identifier (e.g. test_docker_up_seerr).
#   $2 (message)   - Explanatory success message.
#   $3 (duration)  - Optional duration string (e.g. "0.45s").
# ------------------------------------------------------------------------------
record_pass() {
  local test_name="$1"
  local message="$2"
  local duration="${3:-}"
  ((TEST_COUNT_TOTAL++)) || true
  ((TEST_COUNT_PASS++)) || true

  if [[ -n "${duration}" ]]; then
    printf "  %b[PASS]%b %s: %s %b(%s)%b\n" \
      "${CLR_BOLD}${CLR_GREEN}" "${CLR_RESET}" \
      "${test_name}" "${message}" \
      "${CLR_GRAY}" "${duration}" "${CLR_RESET}"
  else
    printf "  %b[PASS]%b %s: %s\n" \
      "${CLR_BOLD}${CLR_GREEN}" "${CLR_RESET}" \
      "${test_name}" "${message}"
  fi
}

# ------------------------------------------------------------------------------
# Function: record_fail
# Description:
#   Records a failed test assertion and increments fail counter.
# Arguments:
#   $1 (test_name) - Symbolic test identifier.
#   $2 (message)   - Explanatory failure reason.
#   $3 (duration)  - Optional duration string.
# ------------------------------------------------------------------------------
record_fail() {
  local test_name="$1"
  local message="$2"
  local duration="${3:-}"
  ((TEST_COUNT_TOTAL++)) || true
  ((TEST_COUNT_FAIL++)) || true

  if [[ -n "${duration}" ]]; then
    printf "  %b[FAIL]%b %s: %s %b(%s)%b\n" \
      "${CLR_BOLD}${CLR_RED}" "${CLR_RESET}" \
      "${test_name}" "${message}" \
      "${CLR_GRAY}" "${duration}" "${CLR_RESET}" >&2
  else
    printf "  %b[FAIL]%b %s: %s\n" \
      "${CLR_BOLD}${CLR_RED}" "${CLR_RESET}" \
      "${test_name}" "${message}" >&2
  fi
}

# ------------------------------------------------------------------------------
# Function: record_skip
# Description:
#   Records a skipped test assertion and increments skip counter.
# Arguments:
#   $1 (test_name) - Symbolic test identifier.
#   $2 (reason)    - Explanatory skip reason.
# ------------------------------------------------------------------------------
record_skip() {
  local test_name="$1"
  local reason="$2"
  ((TEST_COUNT_TOTAL++)) || true
  ((TEST_COUNT_SKIP++)) || true

  printf "  %b[SKIP]%b %s: %s\n" \
    "${CLR_BOLD}${CLR_YELLOW}" "${CLR_RESET}" \
    "${test_name}" "${reason}"
}

# ------------------------------------------------------------------------------
# Function: run_test
# Description:
#   Executes a single test function, measures elapsed time, and traps failures.
# Arguments:
#   $1 (fn_name)     - Name of the shell function implementing the test case.
#   $2 (description) - Human-readable description of what is being verified.
# ------------------------------------------------------------------------------
run_test() {
  local fn_name="$1"
  local description="$2"
  local start_ts end_ts elapsed duration

  start_ts="$(date +%s%N 2>/dev/null || date +%s)"

  # Run the test function; capture stdout and stderr for diagnostic reporting on failure
  local output rc=0
  if output="$("${fn_name}" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi

  end_ts="$(date +%s%N 2>/dev/null || date +%s)"

  # Calculate duration if nanoseconds supported, fallback to seconds
  if [[ ${#start_ts} -gt 10 && ${#end_ts} -gt 10 ]]; then
    local diff_ns=$((end_ts - start_ts))
    local diff_ms=$((diff_ns / 1000000))
    duration="$(awk -v ms="${diff_ms}" 'BEGIN { printf "%.2fs", ms / 1000 }')"
  else
    local diff_s=$((end_ts - start_ts))
    duration="${diff_s}s"
  fi

  if [[ "${rc}" -eq 0 ]]; then
    # If the function printed specific pass output, use it; otherwise use description
    local msg="${description}"
    if [[ -n "${output}" ]]; then
      msg="${description} -> ${output}"
    fi
    record_pass "${fn_name}" "${msg}" "${duration}"
  elif [[ "${rc}" -eq 77 ]]; then
    local skip_msg="${output:-skipped}"
    record_skip "${fn_name}" "${description} (${skip_msg})"
  else
    local err_msg="${output:-exit code ${rc}}"
    record_fail "${fn_name}" "${description} (Failed: ${err_msg})" "${duration}"
  fi
}

# ------------------------------------------------------------------------------
# Function: get_npm_bridge_ip
# Description:
#   Retrieves and caches the internal IP address of the 'nginx' (NPM) container
#   on the 'homelab' bridge network.
# ------------------------------------------------------------------------------
NPM_CACHED_BRIDGE_IP=""
get_npm_bridge_ip() {
  if [[ -z "${NPM_CACHED_BRIDGE_IP}" ]]; then
    NPM_CACHED_BRIDGE_IP="$(docker inspect -f '{{with index .NetworkSettings.Networks "homelab"}}{{.IPAddress}}{{end}}' nginx 2>/dev/null || true)"
    if [[ -z "${NPM_CACHED_BRIDGE_IP}" ]]; then
      NPM_CACHED_BRIDGE_IP="192.168.255.4"
    fi
  fi
  printf "%s" "${NPM_CACHED_BRIDGE_IP}"
}

# ------------------------------------------------------------------------------
# Function: print_summary
# Description:
#   Prints final execution summary across all executed test suites.
# Returns:
#   0 if zero failures, 1 if any failure occurred.
# ------------------------------------------------------------------------------
print_summary() {
  local end_time
  end_time="$(date +%s)"
  local total_elapsed=$((end_time - SUITE_START_TIME))

  printf "\n%b=======================================================%b\n" "${CLR_BOLD}" "${CLR_RESET}"
  printf "%bTest Suite Summary:%b %d Total | %b%d Passed%b | %b%d Failed%b | %b%d Skipped%b (%ds elapsed)\n" \
    "${CLR_BOLD}" "${CLR_RESET}" \
    "${TEST_COUNT_TOTAL}" \
    "${CLR_GREEN}" "${TEST_COUNT_PASS}" "${CLR_RESET}" \
    "${CLR_RED}" "${TEST_COUNT_FAIL}" "${CLR_RESET}" \
    "${CLR_YELLOW}" "${TEST_COUNT_SKIP}" "${CLR_RESET}" \
    "${total_elapsed}"
  printf "%b=======================================================%b\n" "${CLR_BOLD}" "${CLR_RESET}"

  [[ "${TEST_COUNT_FAIL}" -eq 0 ]]
}
