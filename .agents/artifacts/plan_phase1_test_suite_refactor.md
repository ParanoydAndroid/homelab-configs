# Phase 1: Test Suite Modularization and Hardening Plan

## Executive Summary
This plan details **Phase 1** of the infrastructure refactoring: decoupling the monolithic test logic embedded in `homelab.sh` into a structured, modular test suite under `.tests/`. 

All work will be executed on a dedicated feature branch (`refactor/modular-test-suite`). The changes will have **zero functional impact** on running service stacks and zero downtime.

---

## 1. Architectural Design

### 1.1 Directory Structure
The test suite will be housed in `.tests/`. Because it is prefixed with a dot, Dockge will completely ignore it and never confuse it with a Compose stack directory.

```text
.tests/
├── run.sh                          # Master test runner (invoked directly or via homelab.sh test)
├── lib/
│   └── common.sh                   # Shared test harness (assertions, colorized outputs, pass/fail counters)
└── suites/
    ├── test_containers.sh          # Docker runtime and healthcheck tests
    ├── test_direct_admin.sh        # Host fallback ports & internal admin API listeners
    ├── test_routing.sh             # NPM virtual host routing (client-impersonated TLS & status codes)
    ├── test_interconnect.sh        # Service-to-service DNS, TCP sockets, and VPN port sync
    └── test_negative_security.sh   # Isolation checks, auth enforcement, and security blocks
```

### 1.2 Runner & Delegation Model
* `homelab.sh test`: Replaces the 170+ line inline `test_homelab` function with a thin delegation to `"${SCRIPT_DIR}/.tests/run.sh" "$@"`.
* Command-line flexibility:
  * `./homelab.sh test`: Runs all test suites.
  * `./homelab.sh test containers`: Runs only container health tests.
  * `./homelab.sh test security`: Runs only negative isolation & auth tests.
  * Direct execution: `./.tests/run.sh [suite] [test_name]` allows targeting a single test or suite for fast feedback.

### 1.3 Test Function Naming Standardization
Every test will be encapsulated in an explicit Bash function starting with `test_`:
* **Containers**: `test_docker_up_dockge`, `test_docker_up_postgresql`, `test_docker_up_nginx`, `test_docker_up_seerr`, etc.
* **Direct Admin**: `test_direct_dockge_host_port`, `test_direct_npm_admin_api`.
* **Routing**: `test_vhost_homepage_internal`, `test_vhost_jellyfin_internal`, `test_vhost_jellyfin_external`, etc.
* **Interconnections**: `test_interconnect_jellyfin_to_seerr`, `test_interconnect_tandoor_to_postgres`, `test_interconnect_pia_to_qbittorrent_port_sync`, etc.
* **Negative & Security**: `test_security_jellyfin_metrics_blocked`, `test_security_qbittorrent_auth_enforced`, `test_security_postgres_port_isolated`, etc.

---

## 2. Test Suites Specification

### Suite 1: `test_containers.sh`
* Standardizes container checks into individual functions (`test_docker_up_<container>`) for all 15 services:
  * `dockge`, `postgresql`, `nginx`, `tailscale`, `homepage`, `jellyfin`, `wireguard-pia`, `qbittorrentvpn`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr`, `seerr`, `tandoor`, `cloudflared`.
* Asserts state is `running` and health status is not `unhealthy`.

### Suite 2: `test_direct_admin.sh`
* `test_direct_dockge_host_port`: Asserts `http://127.0.0.1:8010` returns HTTP 200 (direct orchestrator access).
* `test_direct_npm_admin_api`: Asserts `http://nginx:81/api/` over the `homelab` bridge returns HTTP 200.

### Suite 3: `test_routing.sh`
* Employs client impersonation using `docker exec radarr curl` with `--resolve <domain>:443:<npm_bridge_ip>` to test:
  * All 12 internal `*.turing.home` hosts (`homepage`, `proxy`, `dockge`, `jellyfin`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr`, `seerr`, `torrent`, `recipes`, `nas`).
  * External endpoints: `jellyfin.kamaka.tech`, `recipes.kamaka.tech`.

### Suite 4: `test_interconnect.sh`
* Service-to-service DNS resolution, API health, database sockets, and background daemons:
  * `test_interconnect_jellyfin_to_seerr`: REST API reachability.
  * `test_interconnect_radarr_to_qbittorrent`: qBittorrent WebUI API from Radarr.
  * `test_interconnect_radarr_to_prowlarr`: Prowlarr API ping from Radarr.
  * `test_interconnect_sonarr_to_qbittorrent`: qBittorrent WebUI API from Sonarr.
  * `test_interconnect_prowlarr_to_flaresolverr`: FlareSolverr health check.
  * `test_interconnect_tandoor_to_postgres`: Direct TCP socket connect to `postgresql:5432`.
  * `test_interconnect_pia_to_qbittorrent_port_sync`: Matches `wireguard-pia` forwarded port in `/pia-shared/port.dat` with `qbittorrentvpn` active listening port.
  * `test_interconnect_tailscale_backend_state`: Verifies Tailscale subnet router is in state `Running`.

### Suite 5: `test_negative_security.sh` (New Negative Tests)
* Confirms that endpoints, interfaces, and authentication boundaries intended to reject unauthorized access actually do so:
  1. `test_security_jellyfin_metrics_blocked`: Asserts `https://jellyfin.kamaka.tech/metrics` returns `HTTP 403 Forbidden`.
  2. `test_security_jellyfin_swagger_blocked`: Asserts `https://jellyfin.kamaka.tech/swagger` returns `HTTP 403 Forbidden`.
  3. `test_security_jellyfin_api_docs_blocked`: Asserts `https://jellyfin.kamaka.tech/api-docs` returns `HTTP 403 Forbidden`.
  4. `test_security_postgres_port_not_exposed_to_host`: Asserts `nc -z 127.0.0.1 5432` or `192.168.0.3:5432` is closed (isolated to `homelab` Docker bridge).
  5. `test_security_qbittorrent_bad_auth_rejected`: Asserts submitting invalid credentials to `http://qbittorrentvpn:8081/api/v2/auth/login` fails (returns `Fails.` or HTTP 403/400).
  6. `test_security_npm_unauthenticated_api_rejected`: Asserts querying `/api/users` without a valid JWT bearer token fails with HTTP 401.
  7. `test_security_turing_disallowed_origin`: Simulates a non-LAN client IP hitting `*.turing.home` (NPM access control block: `allow 192.168.0.0/16; deny all;`) to verify HTTP 403.

---

## 3. Step-by-Step Implementation Sequence

1. **Baseline Verification**:
   * Run existing `./homelab.sh test` to verify current green state (40/40 passed).
2. **Feature Branch Creation**:
   * Create and switch to `refactor/modular-test-suite`:
     ```bash
     git checkout -b refactor/modular-test-suite
     ```
3. **Core Test Framework Setup**:
   * Create `.tests/lib/common.sh` with standardized helper functions:
     * `assert_equals`, `assert_match`, `assert_http_code`, `record_pass`, `record_fail`, `print_suite_header`, `print_summary`.
   * Create `.tests/run.sh` entrypoint with suite discovery and summary aggregation.
4. **Extract and Standardize Modules**:
   * Create `.tests/suites/test_containers.sh`.
   * Create `.tests/suites/test_direct_admin.sh`.
   * Create `.tests/suites/test_routing.sh`.
   * Create `.tests/suites/test_interconnect.sh`.
   * Create `.tests/suites/test_negative_security.sh`.
5. **Update `homelab.sh`**:
   * Refactor `test_homelab` in `homelab.sh` to delegate to `.tests/run.sh`.
   * Update CLI documentation and help in `homelab.sh`.
6. **Execution & Regression Verification**:
   * Run `./homelab.sh test` (and individual sub-suites).
   * Confirm all existing tests pass and new negative tests accurately verify isolation/authentication blocks.
7. **Commit Changes on Feature Branch**:
   * Commit all modular test files and the `homelab.sh` update to `refactor/modular-test-suite`.
8. **Phase 2 Discussion**:
   * Transition to user discussion for Phase 2 (README refactor).

---

## 4. Backlog / Post-RAID Rebuild Tasks

* **Tailscale tmpfs Socket Optimization**:
  * Add `tmpfs: [/tmp]` to `tailscale/compose.yml` so that Tailscale's UNIX domain socket (`/tmp/tailscaled.sock`) is held in RAM rather than the container overlayfs.
  * Eliminates disk write contention and latency during heavy host disk I/O, preventing daemon startup timeouts and ensuring no stale socket artifacts persist across restarts.
  * Deferred until host RAID 5 rebuild is complete to avoid container recreation under high load.
