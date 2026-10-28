# Learning Proposal: Project Development and Agent Configuration Rules

## 1. Classification and Rationale

- **Target Customization**: Update existing rule [project-conventions.md](file:///home/brandon/services/.agents/rules/project-conventions.md) (`trigger: always_on`).
- **Classification**: **Rule Update** (with optional future Skill for `homelab.sh` runbooks once implemented).
- **Rationale**: Comparing the initial requirements ([implementation_plan.md](file:///home/brandon/services/.agents/artifacts/implementation_plan.md) at `7b938fb`) against the refinement round (`2cb0376` and current working tree) reveals several architectural shifts, brownfield migration guardrails, and parameterization rules that either contradict or are missing from the initial draft of [project-conventions.md](file:///home/brandon/services/.agents/rules/project-conventions.md).

---

## 2. Inferred Rules from Initial Requirements vs. Refinement Round

### 2.1 User and Path Parameterization (No Hardcoded Usernames or Host Paths)
- **What Changed in Refinement**: Initial requirements hardcoded `brandon`, `/opt/brandon/dockge`, `/volume1/docker`, and `/volume1/media`. Refinement mandated replacing hardcoded `brandon` references with dynamic user resolution (`${SUDO_USER:-${USER}}`, `id -u`, `id -g`) and parameterizing host paths (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`).
- **Inferred Rule**: Never hardcode usernames (such as `brandon`) or host-specific root paths in scripts, Compose files, or documentation. Parameterize host directories in Compose files using `${VAR:-default}` fallback syntax and resolve user identity dynamically in shell scripts (accounting for `sudo` via `${SUDO_USER:-${USER}}`).

### 2.2 Two-Tier `.env` Architecture and Dockge Working-Directory Constraint
- **What Changed in Refinement**: Initially, the rule stated that all non-secret values with sensible defaults must be inlined in `compose.yml` and `.env.example` should only contain blank variables. Refinement exposed that global host/network settings (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`) belong in a root `.env.example` with populated defaults, while per-stack `<stack>/.env.example` files hold blank secrets and per-install API/widget keys (`KEY=`). Because Dockge runs `docker compose` inside `<stack>/` (ignoring the repository root `.env`), automation must synchronize root `.env` globals into each `<stack>/.env`.
- **Inferred Rule**: Enforce the two-tier `.env` model (populated global defaults in root `.env.example` synced to `<stack>/.env` + `${VAR:-default}` fallbacks in `compose.yml`; blank secret/API key templates in `<stack>/.env.example`). Classify Homepage widget API keys (`*_WIDGET_KEY`) and application cryptographic keys (`SECRET_KEY`) as per-installation secrets in `<stack>/.env`, not inline Compose values.

### 2.3 Encapsulated One-Time Brownfield Migration vs. Clean Reusable Configuration
- **What Changed in Refinement**: Initial Phase 2 planned to replace inline secrets in `compose.yml` with `${VAR}` and initialize `.env` from blank `.env.example` files. Refinement caught that doing so on a live host would break running containers unless existing active values are extracted to git-ignored `<stack>/.env` files *prior* to scrubbing `compose.yml` and running `git rm --cached`, and that legacy host directory moves and UID `1027` -> `1000` permission remediation are one-time transition tasks.
- **Inferred Rule**: Encapsulate all initial brownfield migration complexity (extracting active credentials to `.env`, stopping containers, migrating legacy `/volume1/docker` directories, deleting obsolete folders, and remediating legacy UID `1027`/`0:0` file ownership and `perms.txt`) inside a standalone one-time migration script (`migrate-once.sh`) that is deleted once migration completes. Keep the permanent, reusable `homelab.sh` script and Compose files clean and focused strictly on the standardized target architecture.

### 2.4 Non-Stack Config Storage (`.configs/`) and Orchestrator Self-Management Avoidance
- **What Changed in Refinement**: Placing `dockge/compose.yml` or service config folders at the repository root causes Dockge to treat them as managed stacks (creating a self-management hazard where Dockge kills itself mid-update). Refinement standardized `.configs/` at the repository root for all non-stack tracked configs (`dockge`, `nginx`, `homepage`, `qbittorrentvpn`).
- **Inferred Rule**: Store all tracked service configurations and the orchestrator's own Compose definition inside `.configs/<service>/` at the repository root, and deploy `dockge/compose.yml` to `${DOCKGE_DIR}/compose.yml` (one level above `stacks/`).

### 2.5 Targeted Permission Remediation and Container Lifecycle Ordering
- **What Changed in Refinement**: Auditing `/volume1/docker` revealed that official images (`jellyfin/jellyfin`, `postgres:16-alpine`), LinuxServer images (`sonarr`, `radarr`, `prowlarr`), `binhex` images (`qbittorrentvpn` with cached `/config/perms.txt`), and root-bound services (`nginx`, `homepage`) handle UIDs differently.
- **Inferred Rule**: Never run a blanket recursive `chown` across `/volume1/docker`. Permission remediation must target only services running as `PUID:PGID` (`1000:100`), clear cached permission state files (`perms.txt`), and explicitly exclude containers with fixed internal UIDs (`postgres` UID `70`) or root requirements (`nginx`, `homepage`). Stop affected containers before moving host volume directories or mutating database file ownership.

### 2.6 Internet-Facing vs. LAN-Only Service Hardening Tiers
- **What Changed in Refinement**: Exposing `jellyfin.kamaka.tech` externally required stricter controls than LAN-only (`*.turing.home`) services: non-root execution (`user: "1000:100"`), `cap_drop: [ALL]`, `no-new-privileges:true`, read-only media mounts (`:ro`), NPM WebSockets + security/IP headers, and blocking `/swagger`, `/api-docs`, and `/metrics`.
- **Inferred Rule**: Apply defense-in-depth hardening automatically to any service exposed to the public internet (`*.kamaka.tech`), including least-privilege container execution, read-only data/media mounts where possible, and reverse-proxy endpoint restrictions.

### 2.7 Host Appliance OS Workaround Persistence
- **What Changed in Refinement**: UGREEN NAS OS injects `GODEBUG=tlskyber=0` in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`, crashing Go 1.23+ binaries (including the Antigravity remote agent server).
- **Inferred Rule**: Codify host OS/appliance quirks and environment fixes idempotently in `homelab.sh setup` and document them in `README.md` so system updates or reboots do not break agent or container tooling.

---

## 3. Additional Issues Exposed by the Refinement Round

Reviewing the repository and [implementation_plan.md](file:///home/brandon/services/.agents/artifacts/implementation_plan.md) against the refined decisions exposes seven concrete issues that should be addressed before or during implementation:

1. **Residual Hardcoded `brandon` References in `implementation_plan.md` and `project-conventions.md`**:
   - Decision 5 (line 250 of [implementation_plan.md](file:///home/brandon/services/.agents/artifacts/implementation_plan.md#L250)) requires replacing all hardcoded `brandon` references with `${USER}`, but earlier sections of [implementation_plan.md](file:///home/brandon/services/.agents/artifacts/implementation_plan.md#L185) (lines 7, 16, 25, 27-32, 185, 211, 220) and [project-conventions.md](file:///home/brandon/services/.agents/rules/project-conventions.md#L57) (line 57) still hardcode `/opt/brandon/dockge` and `brandon`.
2. **Docker Compose `.env` Variable Expansion Pitfall (`DOCKGE_DIR=/opt/${USER}/dockge`) + `sudo` Hazard**:
   - Standard Docker Compose `.env` files do not reliably interpolate unexported shell variables like `${USER}` when read by the Dockge daemon (where `USER` may be unset or `root`). Furthermore, if a user runs `sudo ./homelab.sh setup`, `${USER}` evaluates to `root` (`/opt/root/dockge`).
   - **Fix**: `homelab.sh` must resolve the target non-root user via `${SUDO_USER:-${USER}}` (and `id -u`/`id -g`) and write the resolved literal path (e.g., `/opt/brandon/dockge`) into the generated untracked `.env` files while keeping `/opt/${USER}/dockge` as the template placeholder in `.env.example`.
3. **Directory Move Collision in `nginx` Volume Migration (`/volume1/docker/nginx/data/data` -> `/volume1/docker/nginx/data`)**:
   - Currently, `/volume1/docker/nginx/data` contains two subdirectories: `data/` and `letsencrypt/`.
   - A naive `mv /volume1/docker/nginx/data/data /volume1/docker/nginx/data` will fail or leave `data/data` intact because the parent directory `/volume1/docker/nginx/data` already exists.
   - **Fix**: `homelab.sh` must stop `nginx`, move the *contents* of `/volume1/docker/nginx/data/data/` into `/volume1/docker/nginx/data/` (or move `letsencrypt` to `/volume1/docker/nginx/letsencrypt` first), and then remove the empty inner `data/` directory.
4. **Backup Script (`backup-homelab.bash`) Exclusion Filter Breaks After Volume Standardization**:
   - [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash#L33) currently collects files via:
     `find "$DOCKER_CONFIGS_DIR" -type f -not -path '*/data/*'`
   - Once Decision 2 standardizes every service onto `/volume1/docker/<service>/data/...`, *every* file under `/volume1/docker` will match `*/data/*`, causing that `find` command to back up zero files.
   - **Fix**: Replace that logic in `homelab.sh backup` so it backs up tracked `.configs/` (after running `pull-configs`), live `.env` files, and targeted portable configuration paths rather than relying on `-not -path '*/data/*'`.
5. **Stack Name vs. Service/Volume Name Mismatch in `qbitorrentvpn`**:
   - The stack directory is spelled [qbitorrentvpn](file:///home/brandon/services/qbitorrentvpn/compose.yml) (single `t`), whereas the container name, hostname, and host volume directory `/volume1/docker/qbittorrentvpn` use `qbittorrentvpn` (double `t`), alongside legacy `/volume1/docker/qbittorrent`.
   - **Fix**: Either rename the stack folder `qbitorrentvpn/` to `qbittorrentvpn/` for 1:1 consistency with `/volume1/docker/<service>/data`, or explicitly map `qbitorrentvpn` -> `qbittorrentvpn` in `homelab.sh`.
6. **`sonarr-radarr` Multi-Service Stack vs. Per-Service Volume Path Rule**:
   - The stack folder is `sonarr-radarr/`, which runs four containers (`radarr`, `sonarr`, `prowlarr`, `flaresolverr`), while Decision 2 maps their host volumes by *container/service* name (`/volume1/docker/radarr/data`, `/volume1/docker/sonarr/data`, `/volume1/docker/prowlarr/data`).
   - **Fix**: Clarify in `project-conventions.md` that `/volume1/docker/<service>/data` is keyed by **container/service name** (`container_name`), not necessarily the multi-container stack folder name.
7. **Tandoor Media Serving via Nginx (`nginx` `/media:ro` Volume)**:
   - [nginx/compose.yml](file:///home/brandon/services/nginx/compose.yml#L18) currently mounts `/volume1/docker/media:/media:ro`. When Decision 2 moves `/volume1/docker/media` to `/volume1/docker/tandoor/data/mediafiles`, `nginx` will recreate `/volume1/docker/media` as an empty root-owned directory on startup unless `/volume1/docker/media:/media:ro` is simultaneously removed from `nginx/compose.yml` (or updated to `${DOCKER_DATA_DIR:-/volume1/docker}/tandoor/data/mediafiles:/media:ro` if NPM serves Tandoor media directly).

---

## 4. Proposed Changes to `.agents/rules/project-conventions.md`

Below is the proposed diff to [project-conventions.md](file:///home/brandon/services/.agents/rules/project-conventions.md) incorporating these rules:

```diff
--- a/.agents/rules/project-conventions.md
+++ b/.agents/rules/project-conventions.md
@@ -30,24 +30,36 @@ When newly instantiated against this repository, orient yourself using the follo
 - **Dockge Compatibility**:
   - Strictly preserve the Dockge-compatible directory structure at the repository root: one directory per stack containing `compose.yml` and an optional `.env` file.
-  - Do not clutter the repository root with non-stack folders that would be misidentified by Dockge as stacks. Keep agent metadata and project artifacts inside `.agents/`.
+  - Do not clutter the repository root with non-stack folders that would be misidentified by Dockge as stacks. Keep agent metadata and project artifacts inside `.agents/` and tracked service/orchestrator configuration files inside `.configs/<service>/`.
+  - Store Dockge's own `compose.yml` in `.configs/dockge/compose.yml` and deploy it to `${DOCKGE_DIR}/compose.yml` (one level above `stacks/`) so Dockge does not list or restart itself as a self-managed stack.
 - **Declarative and Idempotent Automation**:
   - Favor declarative configuration over imperative state manipulation.
   - All setup, update, and backup scripts must be idempotent. Re-running a script after an update must safely converge on the desired state without duplicating Docker networks, failing on existing resources, or silently overwriting locally modified configuration files.
+  - Preserve live runtime state during brownfield migrations: always extract active credentials/keys into git-ignored `.env` files before scrubbing `compose.yml` or untracking `.env` files, and stop affected containers before migrating host volume directories or changing database file ownership.
+  - Codify host appliance OS workarounds (such as the UGREEN NAS `GODEBUG=tlskyber=0` remediation in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`) idempotently in setup automation and document them in `README.md`.
 - **Network and Port Exposure Model**:
   - Backend services run on the user-defined `homelab` Docker bridge network (`192.168.255.0/24`).
   - Nginx Proxy Manager (NPM) bridges the LAN (`external_npm` macvlan network on `192.168.0.0/24`) and the `homelab` network to expose HTTP/HTTPS services via subdomains.
-  - Do not expose unnecessary host ports on containers that are accessed exclusively via NPM. Preserve comments in `compose.yml` and documentation in `README.md` recording internal container ports and historical external host port mappings in case direct port forwarding is needed in the future.
+  - Expose host ports only where strictly required for non-HTTP/LAN protocols or emergency fallback (`dockge` `8010:5001`, `jellyfin` `8022:7359/udp`, `qbittorrentvpn` `58946:58946` TCP/UDP). Comment out all other host port mappings (including NPM `80`/`443`/`81` when using `external_npm` macvlan) while preserving inline comments in `compose.yml` and the reference table in `README.md`.
+  - Apply defense-in-depth hardening to any service exposed externally (e.g., `*.kamaka.tech`): run as non-root (`user: "${PUID:-1000}:${PGID:-100}"`), set `security_opt: [no-new-privileges:true]`, drop capabilities (`cap_drop: [ALL]`), mount media/data read-only (`:ro`) where possible, and restrict administrative/diagnostic endpoints at the reverse proxy.
 - **Secrets and Environment Variable Management**:
-  - Inline non-secret configuration values that have sensible defaults directly into `compose.yml`.
-  - Use stack-local `.env` files (ignored by git) paired with tracked `<stack>/.env.example` templates for two categories of values:
-    1. True secrets (such as external VPN credentials or sensitive external keys).
-    2. Non-secret values that have no sensible universal default and must be explicitly configured by a user in a new environment (left blank by default in `.env.example` as self-documenting required configuration).
-  - Setup automation copies `<stack>/.env.example` to `<stack>/.env` if missing and warns when required variables remain blank.
-  - Internal service accounts created solely to satisfy software requirements between containers on the `homelab` network (e.g., internal database credentials), as well as accounts created purely to expose services on the homelab/LAN network, are not treated as secret accounts and may use hardcoded credentials in `compose.yml`.
+  - Never hardcode usernames (such as `brandon`) in scripts, Compose files, or documentation. Resolve the active non-root user dynamically in scripts (`${SUDO_USER:-${USER}}`, `id -u`, `id -g`) and write resolved literals into generated untracked `.env` files.
+  - Use a two-tier `.env.example` architecture to satisfy Dockge's per-stack working directory model:
+    1. **Root `.env.example`**: Defines global host paths, user/group IDs, timezone, and LAN network parameters (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`) with populated defaults. Automation syncs these global values into each `<stack>/.env`, and `compose.yml` files use `${VAR:-default}` fallback syntax so stacks remain runnable standalone.
+    2. **Per-Stack `<stack>/.env.example`**: Defines true external secrets (`VPN_USER`, `VPN_PASS`), application cryptographic secrets (`SECRET_KEY`), and per-installation generated API/widget keys (`*_WIDGET_KEY`, `QBITTORRENT_WIDGET_PASSWORD`) with blank defaults (`KEY=`).
+  - Setup automation initializes missing `.env` files from `.env.example`, syncs root global variables into stack `.env` files, and warns when required per-stack variables remain blank.
+  - Internal container-to-container database credentials isolated to the `homelab` bridge network (such as `postgres:password`) may remain inline in `compose.yml`.
 - **Host Volume Standardization and Bidirectional Configuration Sync**:
-  - Standardize persistent service data and configuration paths under `/volume1/docker/<service>/data/...` (avoiding redundant nesting like `/data/data` or cross-service nesting where practical).
-  - Track portable service configurations (including Nginx Proxy Manager host configurations, Homepage YAML configurations, and container helper scripts) in the git repository and provide bidirectional tooling to pull/backup updated configurations from host volumes into the repo and deploy them from the repo to host volumes with conflict prompts.
+  - Standardize persistent service data and configuration paths by container/service name under `${DOCKER_DATA_DIR:-/volume1/docker}/<service>/data/...` and shared media under `${MEDIA_DIR:-/volume1/media}` (avoiding redundant `/data/data` nesting or cross-service nesting).
+  - Track portable service configurations in `.configs/<service>/` (including exported human-readable NPM host definitions and generated `.conf` files, Homepage YAML configurations, `generate-local-cert.sh`, and container helper scripts) and provide bidirectional commands in `homelab.sh` to pull live configs into the repo and deploy tracked configs to host volumes with diff inspection and conflict prompts (`[o]verwrite / [k]eep / [O]verwrite all / [K]eep all`).
+  - Apply targeted host permission remediation (`1000:100`) only to non-root service data directories (clearing cached permission files like `perms.txt`), explicitly excluding containers with fixed internal UIDs (`postgres` UID `70`) or root privileges (`nginx`, `homepage`).
 
 ## 4. Code Style and Documentation Standards
 
 - **Docker Compose Conventions**:
   - Name all stack files `compose.yml`.
-  - Omit the deprecated top-level `version` property (Docker Compose Specification v2+ best practice).
+  - Omit the deprecated top-level `version` property and top-level `name` property (Docker Compose Specification v2+ best practice).
   - Maintain explicit `container_name` definitions on all services and standardize `hostname` usage so service identity on the `homelab` network and inside containers is consistent.
-  - Standardize `PUID` and `PGID` across all services (aligned with the UGREEN NAS host user `brandon`, `uid=1000`, `gid=10`/`100`), using `user: "<uid>:<gid>"` for non-LinuxServer images that do not read `PUID`/`PGID` environment variables.
-  - Use consistent key ordering, indentation (2 spaces), environment variable syntax, and standard container environment names (`PUID`, `PGID`, `UMASK`, `TZ`) across all stacks.
+  - Standardize `PUID=${PUID:-1000}` and `PGID=${PGID:-100}` across non-root services, using `user: "${PUID:-1000}:${PGID:-100}"` for non-LinuxServer images that do not read `PUID`/`PGID` environment variables (fixing `GUID` typos to `PGID`).
+  - Order service keys consistently (`image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `cap_drop`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`) with 2-space indentation and uniform `environment` syntax.
```
