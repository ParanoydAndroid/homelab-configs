# Architectural Plan: Service-First Discovery, Derived Stack Enablement & Comprehensive Script Audit

## 1. Overview & Dual-Scope Architecture

This plan executes two distinct, coordinated initiatives:

* **Scope A (Service-First Discovery & Stack Enablement Refactor)**: Clean up and refactor all transitional code resulting from consolidating 11 stacks into 6 domain-aligned stacks. Standardize service enablement as the primary atomic unit (parsed from `compose.yml`), make stack enablement purely derivative (active if and only if it contains $\ge 1$ active services), eliminate stack-level `.disabled` markers, and purge all compound Boolean stack/service fallback logic across the test suites.
* **Scope B (Comprehensive Script Audit & Code Elimination)**: Systematically audit every shell script in the repository (`homelab.sh`, `.scripts/*.sh`, `.tests/lib/*.sh`, `.tests/suites/*.sh`, `.configs/**/*.sh`) against recent architectural milestones (NVMe Volume 2 migration, Restic zero-downtime backups, macvlan/reverse-proxy boundaries, two-tier env management, and anti-thrashing API preferences) to identify, simplify, or eliminate dead, redundant, or overly complex code.

---

## 2. Scope A: Service-First Discovery & Stack Enablement Refactor

### 2.1 Service & Stack Discovery Engine (`.scripts/common.sh`)
* **Atomic Unit of Enablement**: The individual service defined in `compose.yml`. A service is enabled if and only if it is defined and uncommented under `services:`.
* **Sub-Millisecond YAML Parsing (`discover_services`)**:
  - Uses a single, fast `awk` parser over all non-hidden `*/compose.yml` files at script load.
  - Extracts both top-level service identifiers (e.g., `jellyfin`, `seerr`, `qbittorrent`, `vpn`) and explicit container names (`container_name: <name>`) (e.g., `qbittorrentvpn`, `wireguard-pia`, `vpn-bridge-pia`, `vpn-bridge-tailscale`).
  - Populates the global list `ENABLED_SERVICES`.
* **Service Lookup Helper (`is_service_enabled <name>`)**:
  - Provides a direct `O(1)`/fast lookup: returns `0` if active, `1` if omitted, commented out, or disabled.
* **Derivative Stack Enablement (`discover_stacks` & `is_stack_enabled`)**:
  - Stacks cannot be manually disabled via `.disabled` files. Delete all `.disabled` file checks on stack directories.
  - A stack is enabled if and only if its directory exists and contains at least one enabled service.
  - Populates `STACKS[@]` in canonical dependency order:
    `priority_order=("productivity" "ingress" "mesh" "dashboard" "media" "torrent")`
  - Purge all lingering legacy stack identifiers (`postgres`, `nginx`, `tailscale`, `vpn-bridge`).
  - `is_stack_enabled <stack>`: derived helper returning `0` if `<stack>` is present in `STACKS[@]`.

### 2.2 Test Suite Modernization (`.tests/suites/`)
* **`test_containers.sh`**:
  - Replace repetitive 10-line boilerplate functions with a unified assertion helper:
    `assert_service_running <service> <container> [expected_health]`
  - If `! is_service_enabled "<service>"`, prints skip message and returns `77`.
  - Collapses ~100 lines of repetitive boilerplate across 17 test cases.
* **`test_routing.sh`**:
  - Eliminate the 20-line `case "${stack}" in` mapping block that cross-referenced old stack names.
  - Accept target `service` directly: checks `is_service_enabled "nginx"` and `is_service_enabled "${service}"`.
* **`test_interconnect.sh` & `test_negative_security.sh`**:
  - Eliminate all compound Boolean stack/service fallback logic (e.g., `(! is_stack_enabled "media" && ! is_stack_enabled "sonarr-radarr") || (! is_stack_enabled "torrent" && ! is_stack_enabled "qbittorrentvpn")`).
  - Replace with clear, declarative service requirements:
    `if ! is_service_enabled "radarr" || ! is_service_enabled "qbittorrentvpn"; then return 77; fi`.

---

## 3. Scope B: Comprehensive Code Review & Architectural Audit Across All Scripts

Every shell script in the repository will be reviewed against recent architectural changes to simplify or eliminate code:

| Script File | Audit Area / Architectural Context | Target Simplifications & Eliminations |
| :--- | :--- | :--- |
| **`homelab.sh`** | **Lifecycle & Probes**: Standardized container naming and multi-service stacks. | 1. Remove legacy `postgres` container fallback probe (`docker exec postgres pg_isready`), standardizing exclusively on `postgresql`.<br>2. Gate qBittorrent preference script deployment and scratch incomplete directory permissions on `is_service_enabled "qbittorrent"` or `wireguard-pia`.<br>3. Remove redundant stack existence checks before `docker compose up -d` since `STACKS[@]` is already guaranteed to contain only valid active stacks. |
| **`.scripts/common.sh`** | **Environment & Globals**: Repository cleanliness and Dockge root conventions. | 1. Remove obsolete `.disabled` file parsing logic.<br>2. Purge legacy stack names from `priority_order`.<br>3. Optimize `upsert_env_var` and `get_env_var` to ensure no subshell overhead or regex corruption on special characters. |
| **`.scripts/env-tools.sh`** | **Two-Tier `.env` Management**: Dynamic user resolution and secret whitelisting. | 1. Add `EXIT_NODE_TS_AUTHKEY` alongside `TS_AUTHKEY` to the optional pre-auth whitelist to prevent false-positive warnings on startup.<br>2. Audit the variable propagation loop from root `.env` to `<stack>/.env` to eliminate redundant regex scanning. |
| **`.scripts/backup.sh`** | **Zero-Downtime DB Staging & NVMe Paths**: `/volume2/docker` storage standardization. | 1. Ensure SQLite staging database array directly aligns with active services (`nginx`, `jellyfin`, `sonarr`, `radarr`, `prowlarr`), skipping disabled services cleanly.<br>2. Verify PostgreSQL cluster dump staging cleanly checks `is_service_enabled "postgresql"`.<br>3. Audit post-restore permission fixups (`chown -R 70:70` on `${DOCKER_DATA_DIR}/postgres/data`) and ensure non-root volume permissions are restored without redundant iterations. |
| **`.scripts/system.sh`** | **Host Appliance OS Fixes & Networks**: `external_npm` macvlan and `homelab` bridge. | 1. Ensure `ensure_networks` uses clean, idempotent network inspection without redundant subshells.<br>2. Verify `remediate_godebug` is purely idempotent and avoids unnecessary systemd daemon re-execution when configs are already clean. |
| **`.tests/lib/common.sh`** | **Test Harness Core & Impersonation**: Virtual host routing and timing. | 1. Streamline `get_npm_bridge_ip` caching.<br>2. Ensure dynamic probe container selection (`radarr sonarr homepage jellyfin seerr nginx`) checks `is_service_enabled` so it never attempts to probe through an inactive container.<br>3. Verify precision timer fallback logic. |
| **`.configs/qbittorrentvpn/set-qbt-port.sh`** | **API Preferences & Anti-Thrashing**: WireGuard port synchronization. | 1. Verify JSON payload matches current qBittorrent v5.x API requirements.<br>2. Ensure retry loops and error logging are lean and fail-safe. |
| **`.configs/nginx/generate-local-cert.sh`** | **Local TLS Provisioning**: Wildcard SAN generation. | 1. Verify OpenSSL config generation and SAN array cleanliness. |

---

## 4. Execution Workflow & Gates

### Step 1: Implementation of Scope A (Service Discovery & Stack Enablement)
* Implement `discover_services()` and `is_service_enabled()` in `.scripts/common.sh`.
* Refactor `discover_stacks()` and `is_stack_enabled()` to be purely derived from active services.
* Refactor all 5 test suites in `.tests/suites/` to use service-first assertions.

### Step 2: Implementation of Scope B (Script Audit Simplifications)
* Apply simplifications to `homelab.sh`, `.scripts/env-tools.sh`, `.scripts/backup.sh`, `.scripts/system.sh`, and `.tests/lib/common.sh`.

### Step 3: Comprehensive Verification
* Run `./homelab.sh test all` to verify all 57 tests pass (100% green).
* Conduct dynamic service-disablement verification: Comment out a test service (e.g. `seerr`) and confirm its associated container, routing, and interconnect tests return `[SKIP]` (`exit 77`) while all other tests pass.

### Step 4: Intermediate Feature Commit & MANDATORY USER REVIEW GATE
* Commit implementation changes to `feature/service-discovery-refactor`.
* **HALT**: Present a clear, concise summary of all audited code changes, line reductions, and runtime verification results to the user.
* **WAIT**: Explicitly ask for user review and approval before initiating feature completion.
