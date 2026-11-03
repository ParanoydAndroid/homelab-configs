# Architectural Plan: Service-First Discovery, Derived Stack Enablement & Script Simplification Audit

## 1. Executive Summary & Goals

This plan refactors the service and stack enablement model across the homelab infrastructure:
1. **Service-First Enablement**: Disabling applies strictly at the service level. A service is enabled if and only if it is defined and uncommented under `services:` in a stack's `compose.yml`.
2. **Derived Stack Enablement**: Stacks cannot be directly or independently disabled with `.disabled` markers. A stack is active if and only if its directory exists and has at least one active constituent service.
3. **Comprehensive Script Audit & Code Elimination**: Purge all transitional dual-name compatibility logic, complex Boolean stack/service fallback trees, and legacy stack identifiers lingering from previous iterations.

---

## 2. Architectural Design

### 2.1 Service & Stack Discovery Engine (`.scripts/common.sh`)

Instead of parsing `.disabled` files or requiring external subshell calls:
* **`discover_services()`**:
  Parses each `compose.yml` across non-hidden root directories using lightweight, sub-millisecond `awk` stream parsing to extract:
  - Service keys under `services:` (e.g. `jellyfin`, `seerr`, `qbittorrent`, `vpn`).
  - Container name declarations (`container_name: <name>`) (e.g. `qbittorrentvpn`, `wireguard-pia`, `vpn-bridge-pia`, `vpn-bridge-tailscale`).
  Populates global array `ENABLED_SERVICES` and associative map `SERVICE_TO_STACK`.
* **`is_service_enabled <name>`**:
  Returns `0` if `<name>` exists in `ENABLED_SERVICES`, `1` otherwise.
* **`discover_stacks()`**:
  Populates `STACKS[@]` exclusively with stack directories that contain at least one enabled service. Orders stacks according to canonical boot dependency:
  `priority_order=("productivity" "ingress" "mesh" "dashboard" "media" "torrent")`
  (Purging all legacy names like `postgres`, `nginx`, `tailscale`, `vpn-bridge`).
* **`is_stack_enabled <stack>`**:
  Derived helper: returns `0` if `<stack>` is present in `STACKS[@]`, `1` otherwise.

### 2.2 Script Audit & Code Simplification

| Component | Current State / Defect | Remediation & Elimination |
| :--- | :--- | :--- |
| **`.scripts/common.sh`** | Checks `.disabled` on stack directories; maintains legacy names in `priority_order`. | Remove `.disabled` file checks; update `priority_order` to exact 6 stacks; add `discover_services()` and `is_service_enabled()`. |
| **`homelab.sh`** | Probes both `postgresql` and `postgres` containers; branches on `productivity` and legacy `postgres` stack names. | Standardize strictly on `postgresql` container and check `is_service_enabled "postgresql"`. Check `is_service_enabled "wireguard-pia"` before creating qBittorrent scratch paths. |
| **`.scripts/env-tools.sh`** | Hardcodes optional bypass for `TS_AUTHKEY` only. | Expand optional bypass to both `TS_AUTHKEY` and `EXIT_NODE_TS_AUTHKEY` so mesh exit node does not emit false-positive warnings. |
| **`.tests/suites/test_containers.sh`** | Every test has bespoke `if ! is_stack_enabled ... && ! is_stack_enabled ...`. | Standardize on helper `assert_service_running <service> <container> [expected_health]`, collapsing ~100 lines of repetitive boilerplate into one-liners. |
| **`.tests/suites/test_routing.sh`** | 20-line `case "${stack}" in` mapping stacks and legacy names. | Replace with direct target service check: `is_service_enabled "${service}"`. Skip immediately if `nginx` or target service is disabled. |
| **`.tests/suites/test_interconnect.sh`** | Complex Boolean expressions combining stack and legacy names. | Replace with clean service-level preconditions: `if ! is_service_enabled "serviceA" || ! is_service_enabled "serviceB"; then return 77; fi`. |
| **`.tests/suites/test_negative_security.sh`** | Complex Boolean expressions checking stack names. | Replace with `is_service_enabled "nginx"`, `is_service_enabled "jellyfin"`, `is_service_enabled "postgresql"`. |

---

## 3. Implementation Steps

1. **Update `.scripts/common.sh`**:
   - Implement `discover_services()` and `is_service_enabled()`.
   - Update `discover_stacks()` to populate `STACKS[@]` only for stacks with active services.
   - Clean up `priority_order` to exact 6 stacks.
2. **Refactor `homelab.sh` & `.scripts/env-tools.sh`**:
   - Clean up PostgreSQL readiness probe and service-dependent configuration staging.
   - Add `EXIT_NODE_TS_AUTHKEY` to optional secrets whitelist.
3. **Refactor `.tests/suites/`**:
   - Refactor `test_containers.sh`, `test_routing.sh`, `test_interconnect.sh`, `test_negative_security.sh`, and `test_direct_admin.sh`.
4. **Validation & Verification**:
   - Run `./homelab.sh test all` to verify all 57 tests pass with 0 regressions.
   - Verify that commenting out a service in `compose.yml` causes its container, routing, and interconnect tests to return `[SKIP]` (`exit 77`) cleanly without impacting other services in the stack.
5. **Intermediate Feature Commit & Mandatory Review Gate**:
   - Commit implementation changes to `feature/service-discovery-refactor`.
   - Halt and present summary of results to user for review and approval.
