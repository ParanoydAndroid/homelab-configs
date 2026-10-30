# Plan: Refactoring and Modularizing `homelab.sh`

## Executive Summary
`homelab.sh` currently stands at **1,092 lines of Bash**. While well-documented, the single file mixes low-level string manipulation, dotenv parsing, host OS system configuration, Docker network provisioning, bidirectional file diffing, backup archiving, systemd boot orchestration, and CLI dispatching.

This plan details a structural refactoring to:
1. **Split `homelab.sh` into focused, cohesive modules** located under a dot-prefixed `.scripts/` directory (preserving 100% Dockge compatibility).
2. **Reduce actual lines of code** by consolidating duplicated traversal logic and repetitive variable synchronization into concise, idiomatic helpers (without resorting to dense or unreadable one-liners).
3. **Reduce `homelab.sh` to a thin orchestration entrypoint** (~120–150 lines) focused exclusively on CLI dispatch, high-level lifecycle workflows (`setup`, `startup`, `test`), and module coordination.
4. **Respect host workload**: Adhere to the new rule to avoid running test suites or heavy disk operations during the active RAID 5 rebuild.

---

## 1. Directory & Module Architecture

To ensure Dockge never misidentifies the helper modules as Compose stacks, all extracted scripts will reside in `.scripts/`:

```text
.
├── homelab.sh               # Thin CLI dispatcher & top-level lifecycle coordinator (~120-150 lines)
├── .scripts/
│   ├── common.sh           # Core runtime: logging (log_info, log_warn, log_error), user resolution, dotenv helpers (upsert_env_var, get_env_var)
│   ├── env-tools.sh        # Two-tier .env initialization, global propagation, and secret validation
│   ├── system.sh           # Host OS fixes (remediate_godebug) and Docker network provisioning (ensure_networks)
│   ├── configs.sh          # Bidirectional config synchronization (sync_file, npm_conf_certs_exist, deploy_configs, pull_configs)
│   └── backup.sh           # Configuration git commit, CalVer/PEP 440 tagging, and .env secret archiving
└── .tests/                 # Modular test suite (completed in Phase 1)
```

---

## 2. Module Breakdown & Refactoring Targets

### 2.1 `.scripts/common.sh` (~80 lines)
* **Responsibilities**:
  - Global constant definitions (`REPO_DIR`, `TARGET_USER`, `TARGET_GROUP`, `STACKS`).
  - Standard logging functions: `log_info`, `log_warn`, `log_error`.
  - Robust dotenv parsing and atomic updating: `get_env_var`, `upsert_env_var`.
* **Code Reductions**:
  - Consolidate path and user resolution logic.
  - Keep the reliable `awk` key-value upsert logic, which safely handles base64 strings and special characters without regex delimiter collisions.

### 2.2 `.scripts/env-tools.sh` (~90 lines, down from ~115 lines)
* **Responsibilities**:
  - Two-tier environment synchronization: `init_and_sync_env`.
  - Automatically derives default host values (`PUID`, `PGID`, LAN gateway via `ip route`, `DOCKER_DATA_DIR`).
  - Propagates global variables to all stack `.env` files and `${DOCKGE_DIR}/.env`.
  - Validates required per-stack secrets and emits clear warnings when blank.
* **Code Reductions**:
  - Replace repetitive per-stack `upsert_env_var` calls with a clean iteration over a defined `GLOBAL_ENV_VARS` array:
    ```bash
    GLOBAL_ENV_VARS=(
      "DOCKER_DATA_DIR" "MEDIA_DIR" "DOCKGE_DIR" "DOCKGE_STACKS_DIR"
      "PUID" "PGID" "TZ" "EXTERNAL_NPM_SUBNET" "EXTERNAL_NPM_GATEWAY"
      "EXTERNAL_NPM_PARENT" "NPM_IPV4_ADDRESS" "TAILSCALE_IPV4_ADDRESS"
    )
    ```
  - Consolidate the loop that syncs these globals across `${STACKS[@]}` and `${DOCKGE_DIR}/.env`.

### 2.3 `.scripts/system.sh` (~70 lines, down from ~105 lines)
* **Responsibilities**:
  - `remediate_godebug`: Codifies the UGREEN NAS Go 1.23+ `GODEBUG=tlskyber=0` workaround idempotently in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`.
  - `ensure_networks`: Checks and creates the `homelab` (bridge) and `external_npm` (macvlan) Docker networks.
* **Code Reductions**:
  - Streamline network creation checks into a clean helper rather than duplicate `docker network inspect` blocks.

### 2.4 `.scripts/configs.sh` (~140 lines, down from ~240 lines)
* **Responsibilities**:
  - `sync_file`: Target file comparison (`cmp -s`), diff display (`diff -u`), and interactive conflict resolution (`[o]verwrite / [k]eep / [O]verwrite all / [K]eep all`).
  - `npm_conf_certs_exist`: Parses SSL certificate paths from tracked NPM `.conf` files to prevent Nginx crash loops.
  - `deploy_configs`: Distributes tracked Homepage, qBittorrent, and NPM configs to host volumes.
  - `pull_configs`: Exports NPM SQLite tables (`npm_hosts.sql`), copies active Nginx proxy host `.conf` files, and pulls Homepage configurations.
* **Code Reductions**:
  - Parameterize NPM configuration directory syncing (`proxy_host`, `dead_host`, `redirection_host`, `default_host`, `default_www`, `custom`) instead of repeating duplicate directory checks and copy logic.
  - Streamline file ownership application.

### 2.5 `.scripts/backup.sh` (~70 lines, down from ~110 lines)
* **Responsibilities**:
  - `resolve_chronological_tag`: Generates unique PEP 440 / CalVer tags (`YYYY.M.D[.N]`).
  - `backup_homelab`: Pulls live configs, stages git changes, creates commits, applies tags, and creates timestamped tar archives of all `.env` secret files.
* **Code Reductions**:
  - Simplify `.env` collection and tar creation.

### 2.6 `homelab.sh` Orchestrator (~120 lines, down from 1,092 lines)
* **Responsibilities**:
  - Script entrypoint, strict mode, directory anchoring.
  - Sources all `.scripts/*.sh` modules.
  - Defines the high-level orchestration workflows:
    - `setup_homelab`: Calls `remediate_godebug` -> `init_and_sync_env` -> `ensure_networks` -> `deploy_configs` -> starts Dockge & stacks.
    - `startup_homelab`: Non-interactive systemd boot sequence (storage wait -> networks -> Dockge -> stacks in dependency order -> postgres readiness).
    - `test_homelab`: Delegates directly to `.tests/run.sh "$@"`.
  - CLI usage help and `main()` argument parser.

---

## 3. Implementation Plan & Steps

1. **Safety & Baseline**:
   - Ensure the working tree is clean on branch `refactor/modular-test-suite`.
   - Adhere strictly to the rule: do not invoke full test runs during the RAID 5 rebuild.
2. **Create Library Directory**:
   - Create `.scripts/`.
3. **Extract & Refactor Modules**:
   - Create `.scripts/common.sh`.
   - Create `.scripts/env-tools.sh` (consolidate global sync loop).
   - Create `.scripts/system.sh` (streamline network and godebug logic).
   - Create `.scripts/configs.sh` (streamline NPM config directory loops).
   - Create `.scripts/backup.sh`.
4. **Refactor `homelab.sh`**:
   - Replace the inline implementations in `homelab.sh` with module sourcing and clean top-level workflow functions.
5. **Syntax & Static Verification**:
   - Run `bash -n` on `homelab.sh` and every file in `.scripts/` to verify zero syntax errors.
   - Run `./homelab.sh --help` to verify CLI dispatching.
   - Run `./homelab.sh test --help` (or targeted dry check) without placing heavy load on the RAID array.
6. **Commit Changes**:
   - Stage and commit the refactoring to `refactor/modular-test-suite`.
