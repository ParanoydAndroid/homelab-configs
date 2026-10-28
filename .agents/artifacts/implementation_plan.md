# Homelab Services Standardization and Automation Plan

## 1. Project Overview and Goal

This document defines the requirements and high-level implementation plan for standardizing and automating the homelab services repository.

The goal is to make the repository self-contained and repeatable so that it can be checked out on the host, create required Docker networks, deploy configuration files to their target paths with conflict prompts, and start all service stacks while preserving compatibility with Dockge.

---

## 2. Current State Assessment

An audit of the repository identified the following state and inconsistencies:

### 2.1 Service Stacks and Compose Files
The repository contains eight stack directories:
- [homepage/compose.yml](file:///home/brandon/services/homepage/compose.yml) (with tracked [homepage/.env](file:///home/brandon/services/homepage/.env))
- [jellyfin/compose.yml](file:///home/brandon/services/jellyfin/compose.yml) (with tracked [jellyfin/.env](file:///home/brandon/services/jellyfin/.env))
- [nginx/compose.yml](file:///home/brandon/services/nginx/compose.yml)
- [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml)
- [postgres/compose.yml](file:///home/brandon/services/postgres/compose.yml)
- [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml)
- [sonarr-radarr/compose.yml](file:///home/brandon/services/sonarr-radarr/compose.yml)
- [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml)

### 2.2 Identified Inconsistencies
1. **Compose File Naming**: [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml) uses a non-standard filename instead of `compose.yml` required by Dockge.
2. **Compose Schema Version**: [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml) and [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml) include the deprecated top-level `version: "3.5"` field; the other six stacks omit it.
3. **Environment Variable Syntax and Naming**:
   - List syntax (`- KEY=VAL`) is used in `sonarr-radarr`, `portainer`, and `nginx`, whereas map syntax (`KEY: VAL`) is used in `homepage`, `jellyfin`, `tandoor`, `postgres`, and `qbitorrentvpn`.
   - Group ID variable is written as `GUID` in `homepage` and `jellyfin`, instead of `PGID` used in `sonarr-radarr`, `portainer`, and `qbitorrentvpn`.
   - `UMASK` is formatted as `22` in `homepage` and `jellyfin`, and `022` in `portainer`.
4. **Secrets and Environment File Usage**:
   - [.gitignore](file:///home/brandon/services/.gitignore) specifies `.env`, but [homepage/.env](file:///home/brandon/services/homepage/.env) and [jellyfin/.env](file:///home/brandon/services/jellyfin/.env) are currently tracked in git.
   - Non-secret port variables (`HTTP_EXTERNAL_PORT`, `PORT_EXTERNAL_HTTP`, `PORT_EXTERNAL_HTTPS`) are stored in `.env` files.
   - External VPN credentials (`VPN_USER`, `VPN_PASS`) are hardcoded directly in [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml).
   - Application keys (`SECRET_KEY` in `tandoor`, `homepage.widget.key` in `sonarr-radarr` and `portainer`) are hardcoded in `compose.yml`, while `WIDGET_KEY` in `jellyfin` is in `jellyfin/.env`.
5. **Network Definitions**:
   - [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml) attaches to an external network named `internal` in addition to `homelab`, whereas [postgres/compose.yml](file:///home/brandon/services/postgres/compose.yml) only attaches to `homelab`, and `internal` is not documented in [README.md](file:///home/brandon/services/README.md).
6. **Existing Scripts**:
   - [tools.sh](file:///home/brandon/services/tools.sh) and [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash) exist for backing up configurations from `/volume1/docker`, but there is no setup, deployment, or network initialization script.

---

## 3. Requirements

### 3.1 Architecture and Structure Constraints
- Preserve the Dockge-compatible directory layout: one folder per stack at the repository root containing `compose.yml` and an optional `.env` file.
- Store project planning and design artifacts in `.agents/artifacts/` so they are versioned in git without cluttering the repository root or interfering with Dockge stack scanning.
- All scripts and automation functions must be idempotent so they can be re-run safely on existing setups or after repository updates.
- Plain Markdown formatting without icons or advanced extensions must be used across documentation.

### 3.2 Compose Standardization and Secrets Management
- Standardize all stack files to be named `compose.yml`.
- Standardize YAML structure across all `compose.yml` files:
  - Remove deprecated `version` declarations.
  - Use a consistent key ordering within service definitions (`image`, `container_name`, `hostname`, `restart`, `privileged`, `cap_add`, `security_opt`, `sysctls`, `devices`, `group_add`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`).
  - Standardize `environment` block formatting (either map or list syntax across all files).
  - Fix environment variable naming (`PGID`, `UMASK`).
- Standardize secrets vs. non-secret configuration:
  - Extract true secrets into stack-specific `.env` files.
  - Inline non-secret `.env` variables directly into `compose.yml` (such as port numbers and default Flaresolverr flags).
  - Keep internal service-to-service credentials (such as the PostgreSQL `postgres:password` account used by Tandoor) and LAN-only service exposure accounts hardcoded directly in `compose.yml`.

### 3.3 Container Port Forwarding Removal
- Remove unnecessary host port mappings from service containers that are proxied through Nginx Proxy Manager (NPM) over the `homelab` network.
- Retain in-file comments in each `compose.yml` documenting the internal container port and historical external host port mapping.
- Retain and update the port mappings reference table in [README.md](file:///home/brandon/services/README.md) for historical reference and troubleshooting.

### 3.4 Setup and Update Automation Script
- Provide an idempotent setup and update script that performs:
  1. **Docker Network Creation**: Checks for and creates required Docker networks (`homelab` bridge network at `192.168.255.0/24` with gateway `192.168.255.1`, and `external_npm` macvlan network at `192.168.0.0/24` with gateway `192.168.0.1` on `parent=eth0`) if they do not already exist.
  2. **Configuration File Deployment**: Copies tracked configuration files from the repository to their target host paths (such as NPM host configs, Homepage configuration YAML files, or container helper scripts).
  3. **Conflict Detection and Prompting**: Detects when a target configuration file already exists and has been modified since the last update, and prompts the user whether to overwrite or preserve the target file.
  4. **Service Startup**: Starts or updates the Docker Compose stacks in the appropriate order.

### 3.5 Documentation Updates ([README.md](file:///home/brandon/services/README.md))
- Convert the networks section into a structured table listing all networks, subnets, gateways, drivers, parent interfaces, key static IP assignments, and purpose.
- Document the historical port mappings vs. active internal ports.
- Add sections documenting the setup/update script, backup script, file deployment behavior, and secrets initialization workflow.

---

## 4. High-Level Implementation Plan

### Phase 1: Compose File Standardization and Port Cleanup
1. Rename [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml) to `portainer/compose.yml`.
2. Normalize all `compose.yml` files to remove `version`, unify key order, and standardize `environment` syntax.
3. Inline non-secret variables from [homepage/.env](file:///home/brandon/services/homepage/.env) and [jellyfin/.env](file:///home/brandon/services/jellyfin/.env), and remove `homepage/.env` if no secrets remain in that stack.
4. Comment out unnecessary `ports:` mappings in proxied services while adding standardized comments above or inside the `ports` section recording the internal and historical host ports.
5. Resolve the `internal` network reference in [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml).

### Phase 2: Secrets Extraction and Handling
1. Move secret values (such as PIA VPN credentials in [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml) and any designated secret keys) into per-stack `.env` files.
2. Untrack `.env` files from git history/index where appropriate so `.gitignore` rules apply consistently, and provide `.env.example` templates or secret initialization prompts as decided during refinement.

### Phase 3: Configuration File Tracking and Setup/Update Script
1. Organize static configuration files that must be deployed to host volumes into a dedicated structure within the repository.
2. Implement the idempotent setup/update script (building upon or alongside [tools.sh](file:///home/brandon/services/tools.sh)):
   - Network verification and creation (`docker network inspect` before `docker network create`).
   - Configuration file synchronization with change detection and interactive overwrite/preserve prompt.
   - Stack startup via `docker compose`.
3. Fix existing shell issues in [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash) (such as invalid top-level `local` keyword on line 38 and redundant self-move on line 47) and align it with the new setup flow.

### Phase 4: README Revision
1. Replace the freeform network notes in [README.md](file:///home/brandon/services/README.md) with a comprehensive network configuration table:

| Network Name | Type / Driver | Subnet | Gateway | Parent / Host | Notes |
|---|---|---|---|---|---|
| LAN | Physical | 192.168.0.0/24 | 192.168.0.1 | eth0 | Pi-hole at 192.168.0.2, NAS at 192.168.0.3, NPM at 192.168.0.4 |
| WireGuard VPN | VPN | 192.168.1.128/25 | 192.168.1.128 | Gateway | Exposed by gateway |
| homelab | Docker bridge | 192.168.255.0/24 | 192.168.255.1 | NAS Docker | User-created internal service network |
| external_npm | Docker macvlan | 192.168.0.0/24 | 192.168.0.1 | eth0 | Allows NPM container to bind 80/443 on LAN |

2. Update the Port Mappings table to include missing services (`qbittorrentvpn`) and clearly distinguish historical host ports from internal container ports.
3. Add documentation for running the setup/update and backup scripts.

---

## 5. Open Questions and Ambiguities to Clarify

Before executing or finalizing detailed specifications, the following ambiguities in the repository need clarification:

1. **Classification of Specific Keys and Passwords**:
   - **Homepage Widget Keys (`homepage.widget.key`)**: Currently in `.env` for Jellyfin, but hardcoded in `compose.yml` for Sonarr, Radarr, Prowlarr, and Portainer. Since these only allow Homepage to query container stats over the `homelab` network, should all widget keys be hardcoded inline in `compose.yml`, or moved to `.env`?
   - **Tandoor `SECRET_KEY`**: Should Django's `SECRET_KEY` in [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml) be extracted to `tandoor/.env` or remain inline?
   - **qBittorrent WebUI Password (`homepage.widget.password`)**: In [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml), `homepage.widget.password` currently uses the same string as `VPN_PASS`. Should `VPN_USER`/`VPN_PASS` be moved to `.env` while changing or keeping the WebUI widget password inline, or should both reference `.env`?
   - **Secret Distribution on Fresh Checkout**: Since `.env` is in [.gitignore](file:///home/brandon/services/.gitignore), how should secrets be populated on a fresh checkout (e.g., `.env.example` templates with interactive prompts in the setup script, or copying from a secure backup path)?

2. **Scope of Port Removal**:
   - Should `nginx` ([nginx/compose.yml](file:///home/brandon/services/nginx/compose.yml)) keep its `ports` (`80:80`, `443:443`, `81:81`), or are those unnecessary because it uses `macvlan` (`192.168.0.4`)?
   - Should `jellyfin` keep `8022:7359/udp` (LAN autodiscovery) and `qbitorrentvpn` keep `58946:58946` TCP/UDP (BitTorrent peer traffic, or does that route exclusively through the container's VPN tunnel)?
   - Should Portainer or NPM admin port (`81`) retain a host port mapping as a fallback if NPM goes down?

3. **Files to Move During Setup/Update**:
   - Which specific configuration files should be stored in the repo and moved to target locations by the setup script (for example: NPM proxy host `.conf` files, Homepage `.yaml` files currently referenced in [tools.sh](file:///home/brandon/services/tools.sh), `/volume1/docker/qbittorrentvpn/data/getvpnport.sh`, or others)?
   - Where is this git repository checked out on the NAS relative to Dockge's stacks directory (e.g., is the repo checked out directly as `/opt/stacks` or `/volume1/docker`, or does the setup script also need to sync stack folders to Dockge's stacks path)?

4. **Change Detection Mechanism for Target Files**:
   - When the script checks if target files "have been changed since the last update", should it compare the target file against a stored checksum manifest from the last deployment, compare file modification timestamps, or compare anytime the target file differs from the repository source file?

5. **Tandoor `internal` Network**:
   - [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml) lists `internal` as an external network, but [postgres/compose.yml](file:///home/brandon/services/postgres/compose.yml) only uses `homelab`. Should `internal` be removed from Tandoor, or should `internal` be created by the setup script and added to Postgres?

6. **Automatable Elements from README**:
   - Beyond Docker network creation, file movement, and `docker compose up -d`, are any DNS/Pi-hole records (such as CNAMEs to `turing.home` or local hosts files) managed via local files that the script should automate, or are Pi-hole/router settings strictly external?
