# Homelab Services Standardization and Automation Plan

## 1. Project Overview and Goal

This document defines the requirements and high-level implementation plan for standardizing and automating the homelab services repository.

The goal is to make the repository self-contained and repeatable so that it can be checked out on the host (`/opt/brandon/dockge/stacks`, symlinked at `/home/brandon/services`), initialize `.env` files from `.env.example` templates, create required Docker networks, bidirectionally sync configuration files (including Nginx Proxy Manager and Homepage configurations) between the repository and `/volume1/docker` with conflict prompts, and start all service stacks while preserving compatibility with Dockge.

---

## 2. Current State Assessment

An audit of the repository and host filesystem (`/opt/brandon/dockge` and `/volume1/docker`) identified the following state and inconsistencies:

### 2.1 Service Stacks and Compose Files
The repository at `/opt/brandon/dockge/stacks` currently contains eight stack directories, plus Dockge running from its parent directory `/opt/brandon/dockge/compose.yaml`:
- [homepage/compose.yml](file:///home/brandon/services/homepage/compose.yml) (with tracked [homepage/.env](file:///home/brandon/services/homepage/.env))
- [jellyfin/compose.yml](file:///home/brandon/services/jellyfin/compose.yml) (with tracked [jellyfin/.env](file:///home/brandon/services/jellyfin/.env))
- [nginx/compose.yml](file:///home/brandon/services/nginx/compose.yml)
- [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml) (deprecated; to be removed and replaced by Dockge)
- [postgres/compose.yml](file:///home/brandon/services/postgres/compose.yml)
- [qbitorrentvpn/compose.yml](file:///home/brandon/services/qbitorrentvpn/compose.yml)
- [sonarr-radarr/compose.yml](file:///home/brandon/services/sonarr-radarr/compose.yml)
- [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml)
- `/opt/brandon/dockge/compose.yaml` (active Dockge instance currently outside the git repository)

### 2.2 Dockge Inspection Findings (`/opt/brandon/dockge/compose.yaml`)
- `/home/brandon/services` is a symlink to `/opt/brandon/dockge/stacks`.
- Dockge runs `louislam/dockge:1` on `homelab` with port `8010:5001` and volumes `/var/run/docker.sock:/var/run/docker.sock`, `./data:/app/data` (`/opt/brandon/dockge/data`), and `/opt/brandon/dockge/stacks:/opt/brandon/dockge/stacks`.
- Architectural issues identified:
  1. **Self-Management Hazard**: If `dockge/compose.yml` is placed inside `/opt/brandon/dockge/stacks/dockge/`, Dockge lists itself in its UI and cannot cleanly restart/update itself from the web UI without killing its own container mid-operation. Storing Dockge's compose file in the repo and deploying it to `/opt/brandon/dockge/compose.yml` via the setup script avoids this.
  2. **Relative Data Volume**: `./data:/app/data` depends on the working directory and should be standardized to an absolute path (`/volume1/docker/dockge/data:/app/data` or `/opt/brandon/dockge/data:/app/data`).
  3. **Ineffective `PUID`/`PGID` Variables**: `louislam/dockge` does not use LinuxServer `PUID`/`PGID` variables.
  4. **Missing Homepage Labels & Emoji Comments**: Lacks `homepage.*` labels and includes emoji characters in comments.

### 2.3 Host Volume (`/volume1/docker`) and NPM Inspection Findings
Inspecting `/volume1/docker` on the UGREEN NAS revealed:
1. **Non-existent `/docker` Path in Backup Script**: [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash) sets `BACKUP_DIR="/docker/backup/homelab"`, but `/docker` does not exist on the host; all Docker data resides under `/volume1/docker`.
2. **Inconsistent Volume Path Structure Across Services**:
   - `nginx`: Mounts `/volume1/docker/nginx/data/data:/data` (redundant double `data/data` directory nesting) and `/volume1/docker/nginx/data/letsencrypt:/etc/letsencrypt`.
   - `sonarr-radarr`: Mounts `radarr`, `sonarr`, and `prowlarr` under `/volume1/docker/radarr/data/{radarr_config,sonarr_config,prowlerr_config}` (nesting three separate services under `radarr/data` and misspelling `prowlerr_config`).
   - **Legacy `/volume1/Public` vs `/volume1/media` Mismatch**: `sonarr-radarr` and `qbitorrentvpn` still mount `/volume1/Public:/media` (which is empty), whereas the actual media directories (`downloads`, `movies`, `music`, `shows`) live in `/volume1/media` (mounted by `jellyfin`).
   - `jellyfin` & `qbitorrentvpn`: Mount `/volume1/docker/<service>/data/config:/config`.
   - `homepage` & `postgresql`: Mount `/volume1/docker/<service>/data` directly to the container data target.
   - `tandoor`: Mounts `/volume1/docker/tandoor/data/staticfiles:/opt/recipes/staticfiles` and `/volume1/docker/media:/opt/recipes/mediafiles` (while an unused `/volume1/docker/tandoor/data/mediafiles` directory also exists on disk).
   - Legacy directories `/volume1/docker/portainer` and `/volume1/docker/qbittorrent` remain on disk.
3. **NPM Configuration, Database Architecture, and Local Certificate Script**:
   - `/volume1/docker/nginx/data/data/nginx/` currently contains:
     - `proxy_host/2.conf` (`recipes.kamaka.tech` -> `tandoor:8050`)
     - `proxy_host/3.conf` (`jellyfin.kamaka.tech` -> `jellyfin:8096`)
     - `proxy_host/4.conf` (`jellyfin.grace.home, jellyfin.turing.home` -> `jellyfin:8096`)
     - `dead_host/1.conf` (`www.grace.home`), `dead_host/2.conf` (`grace.home`)
     - `default_host/site.conf`, `default_www/index.html`
   - **Host Identity, Combined Local Certificate, and Obsolete `grace.home` Cleanup**:
     - The UGREEN NAS host itself is `nas.home` (`192.168.0.3`), while the NPM container exposed on the LAN via `external_npm` macvlan (`192.168.0.4`) is `turing.home`.
     - All `grace.home` references (in NPM proxy/dead hosts, custom certs, and `/home/brandon/generate-local-cert.sh`) are from a deprecated experiment and must be removed.
     - `/home/brandon/generate-local-cert.sh` will be moved into the repository and updated to generate a single combined multi-SAN self-signed certificate covering both `turing.home` (`*.turing.home`) and `nas.home` (`*.nas.home`) by setting `DOMAINS=("turing.home" "nas.home")`. This single certificate can be uploaded to both the UGREEN NAS control panel and NPM.
   - **NPM Export/Import Strategy (Simplicity & Maintainability First)**:
     - Rather than attempting a fragile full-state binary database sync (which entangles user auth hashes, JWT secrets, and Let's Encrypt ACME account state), the repository will track:
       1. A clean, human-readable export of NPM host definitions (`proxy_host`, `dead_host`, `redirection_host`, and `setting` tables exported via `sqlite3 -json` or SQL/API payload, cleaned of `grace.home` entries) and the generated `.conf` / `default_www` files for reference and import.
       2. The updated `generate-local-cert.sh` script for generating the combined `turing.home` + `nas.home` wildcard certificate.
       3. Concise, precise documentation in `README.md` covering one-time manual setup steps (initial admin login, Let's Encrypt Cloudflare DNS resolver certificate setup for `*.kamaka.tech`, running `generate-local-cert.sh` and uploading `turing.crt`/`turing.key` to NPM and UGREEN NAS, and linking certs to hosts).

### 2.4 Host User (`PUID`/`PGID`) and File Permission Findings
- Inspecting `/etc/passwd` and `/etc/group` confirmed the system is a UGREEN NAS where user `brandon` has `uid=1000`, primary group `gid=10` (`admin`), and supplementary group `gid=100` (`users`).
- `PUID=1027` in `sonarr-radarr` and `qbitorrentvpn` is a leftover from an older Synology DSM environment.
- `GUID` in `homepage` and `jellyfin` is a typo for `PGID`. Additionally, the official `jellyfin/jellyfin` image ignores `PUID`/`PGID` environment variables and requires Compose `user: "1000:100"` (meaning Jellyfin has actually been running as `root` `0:0`).
- **On-Disk Permission Hazards Identified**:
  - Existing files in `/volume1/docker/*/data` are currently owned by `0:0 (root:root)` (with mode `777` and POSIX ACLs `+` from migration), and `/volume1/docker/qbittorrentvpn/data/config/perms.txt` caches the previous `PUID`/`PGID` for the `binhex` container.
  - Switching containers (especially `jellyfin` via `user: "1000:100"`, `sonarr`, `radarr`, `prowlarr`, and `qbittorrentvpn`) to UID `1000` / GID `100` can cause permission denied errors if root-owned files with `644`/`755` permissions exist in their config folders or if `perms.txt` prevents `binhex` from re-applying ownership.
  - Conversely, `postgresql` uses internal Alpine UID `70` and `nginx`/`homepage` run as `root`, so a blind `chown` across all of `/volume1/docker` would break PostgreSQL. Permission remediation must be targeted per service.

### 2.5 Other Compose Inconsistencies
1. **Compose Schema Version**: `qbitorrentvpn/compose.yml` still uses `version: "3.5"`. Under the modern Compose Specification (v2+), top-level `version` is obsolete and ignored.
2. **Service Naming (`name`, `container_name`, `hostname`)**:
   - `/opt/brandon/dockge/compose.yaml` defines top-level `name: dockge`; all other stacks omit top-level `name:`.
   - `homepage` and `jellyfin` define both `container_name` and `hostname`, while `nginx`, `postgresql`, `qbittorrentvpn`, `sonarr-radarr`, `tandoor`, and `dockge` only define `container_name`.
3. **Environment Syntax and Secrets**:
   - Mixed list (`- KEY=VAL`) and map (`KEY: VAL`) syntax across stacks.
   - `homepage/.env` and `jellyfin/.env` are tracked in git despite `.gitignore` listing `.env`.
   - `VPN_USER` and `VPN_PASS` are hardcoded in `qbitorrentvpn/compose.yml`.
4. **Network Definitions**:
   - `tandoor/compose.yml` references an undocumented external `internal` network not used by `postgres/compose.yml`.

---

## 3. Requirements

### 3.1 Architecture and Structure Constraints
- Remove `portainer/` and integrate `dockge` configuration from `/opt/brandon/dockge/compose.yaml`.
- Preserve the Dockge-compatible directory layout: one folder per stack at the repository root containing `compose.yml` and an optional `.env` / `.env.example` file.
- Store project planning and design artifacts in `.agents/artifacts/` so they are versioned in git without cluttering the repository root or interfering with Dockge stack scanning.
- All scripts and automation functions must be idempotent so they can be re-run safely on existing setups or after repository updates.
- Plain Markdown formatting without icons or advanced extensions must be used across documentation and code comments.

### 3.2 Compose Standardization and `.env.example` Management
- Standardize all stack files to be named `compose.yml`.
- **Version Best Practice**: Omit the deprecated top-level `version` property and top-level `name` property across all `compose.yml` files.
- **Name and Hostname Standardization**: Maintain explicit `container_name` on all services and set matching `hostname` values across all containers for consistent network and shell identity.
- **`PUID` and `PGID` Standardization and Host Permission Remediation**:
  - Standardize on `PUID=1000` and `PGID=100` (matching host user `brandon` and group `users` on the UGREEN NAS), fix `GUID` typos to `PGID`, and add `user: "1000:100"` for non-LinuxServer containers such as Jellyfin (while keeping `PUID=0`/`PGID=0` only where root access to `/var/run/docker.sock` is required, such as Homepage).
  - Include an idempotent permission-remediation step in the setup script that sets `1000:100` ownership on the persistent config directories of non-root services (`jellyfin`, `radarr`, `sonarr`, `prowlarr`, `qbittorrentvpn`, `tandoor`) and clears `/volume1/docker/qbittorrentvpn/data/config/perms.txt` when transitioning `PUID`/`PGID`, while explicitly excluding `postgresql` (which uses Alpine `postgres` UID `70`) and root-run infrastructure (`nginx`, `homepage`).
- **Consistent Key Ordering and Formatting**:
  - Order service keys consistently: `image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`.
  - Standardize `environment` block formatting across all files.
- **`.env` and `.env.example` Strategy**:
  - Inline sensible defaults directly into `compose.yml`.
  - Track `<stack>/.env.example` in git and keep `<stack>/.env` in `.gitignore` (untracking `homepage/.env` and `jellyfin/.env` from git index).
  - Restrict `.env.example` / `.env` variables to two categories, left blank (`KEY=`) in `.env.example` as self-documenting required configuration:
    1. True secrets (such as external VPN credentials or sensitive external keys).
    2. Mandatory environment-specific variables that have no sensible universal default and must be set by a user in a new environment.
  - Setup automation copies `<stack>/.env.example` to `<stack>/.env` if missing and checks for unpopulated variables.
  - Keep internal service-to-service credentials (such as PostgreSQL `postgres:password`) and LAN-only service exposure accounts hardcoded directly in `compose.yml`.

### 3.3 Volume Path Standardization and Bidirectional Configuration Sync (NPM & Services)
- **Standardize Host Volume Layout under `/volume1/docker`**:
  - Establish a consistent volume convention under `/volume1/docker/<service>/...` across stacks (and evaluate migrating inconsistent paths such as `/volume1/docker/nginx/data/data` and `/volume1/docker/radarr/data/prowlerr_config`).
- **Retrieve, Version, and Bidirectionally Sync Service Configurations**:
  - Store portable service configurations in the git repository (in per-stack subdirectories such as `<stack>/config/` or a hidden root folder like `.configs/` so Dockge does not mistake them for stacks):
    - **Nginx Proxy Manager (NPM)**:
      - Exported host definitions in an importable, human-readable format (JSON/SQL extracted via `sqlite3` from `db.sqlite` covering `proxy_host`, `dead_host`, `redirection_host`, and `setting`) plus the generated `.conf` and `default_www/index.html` files.
      - Concise one-time setup instructions in `README.md` for non-automated steps (Cloudflare DNS challenge certificate creation and SSL assignment).
    - **Homepage**: Configuration YAML files (`bookmarks.yaml`, `docker.yaml`, `kubernetes.yaml`, `services.yaml`, `settings.yaml`, `widgets.yaml`, `custom.css`, `custom.js`) from `/volume1/docker/homepage/data/`.
    - **qBittorrentVPN**: Helper script `/volume1/docker/qbittorrentvpn/data/getvpnport.sh`.
  - Provide bidirectional automation commands:
    - **Pull / Backup to Repo**: Retrieve current live configurations from `/volume1/docker/...` (including exporting NPM host definitions and copying Homepage/script files) into the repository so changes made via UI can be reviewed with `git diff` and committed.
    - **Push / Deploy from Repo**: Copy tracked repository configurations (and import NPM host definitions if desired) to their target locations in `/volume1/docker/...` during setup or update, detecting if target files were modified since the last update and prompting whether to overwrite or preserve them.

### 3.4 Container Port Forwarding Removal
- Remove unnecessary host port mappings from service containers that are proxied through NPM over the `homelab` network.
- Retain in-file comments in each `compose.yml` documenting the internal container port and historical external host port mapping.
- Retain and update the port mappings reference table in [README.md](file:///home/brandon/services/README.md) (replacing Portainer with Dockge `8010:5001` and adding `qbittorrentvpn`) for historical reference.

### 3.5 Setup, Update, and Backup Automation Scripts
- Provide an idempotent setup/update script and updated backup script that perform:
  1. **Docker Network Creation**: Checks for and creates `homelab` (`192.168.255.0/24`, gateway `192.168.255.1`, bridge) and `external_npm` (`192.168.0.0/24`, gateway `192.168.0.1`, macvlan on `eth0`) if they do not exist.
  2. **`.env` Initialization**: Copies `<stack>/.env.example` to `<stack>/.env` if missing and warns if required variables are blank.
  3. **Configuration Deployment (Repo -> Host)**: Deploys tracked config files to `/volume1/docker/...` with change detection and interactive overwrite/preserve prompts.
  4. **Configuration Retrieval (Host -> Repo)**: Pulls updated NPM/Homepage/service config files from `/volume1/docker/...` back into the git repository for versioning.
  5. **Service Startup**: Starts or updates Dockge and the Docker Compose stacks in dependency order (`postgres` before `tandoor`, `nginx`, etc.).
  6. **Archive Backup**: Fixes [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash) to write archives to a valid `/volume1/docker/backup/homelab` path and remove bash errors.

### 3.6 Documentation, Certificate Script, and External Jellyfin Hardening
- **Combined Local Certificate (`generate-local-cert.sh`)**:
  - Track `generate-local-cert.sh` inside the repository and update `DOMAINS` to `("turing.home" "nas.home")` (removing obsolete `grace.home` entries) so a single combined multi-SAN certificate covers `turing.home`, `*.turing.home`, `nas.home`, and `*.nas.home` for both the UGREEN NAS and NPM.
- **External Jellyfin Exposure and Security Hardening (`jellyfin.kamaka.tech` / `kamaka.tech`)**:
  - **Container Hardening ([jellyfin/compose.yml](file:///home/brandon/services/jellyfin/compose.yml))**:
    - Run as non-root via `user: "1000:100"` (fixing the ignored `PUID` issue), retain `security_opt: [no-new-privileges:true]`, drop unnecessary Linux capabilities (`cap_drop: [ALL]`), remove direct host HTTP/HTTPS port mappings (`8020`, `8021`), and mount the media library read-only (`/volume1/media:/data/media:ro`) unless in-folder metadata writing/deletion from Jellyfin is explicitly required.
  - **NPM Proxy Host Hardening (`jellyfin.kamaka.tech`)**:
    - Configure the external Jellyfin host with the Let's Encrypt certificate (`*.kamaka.tech` / `kamaka.tech`), Force SSL, HTTP/2, HSTS, Block Exploits, and **WebSockets Support enabled** (`allow_websocket_upgrade=1`, fixing the current `0` setting in `db.sqlite`).
    - Add custom Nginx proxy hardening directives: `proxy_buffering off;` (for streaming performance), security headers (`X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer-when-downgrade`, `X-Robots-Tag: noindex, nofollow`), real client IP forwarding headers (`X-Real-IP`, `X-Forwarded-For`, `CF-Connecting-IP`), and blocking external access to `/swagger`, `/api-docs`, and `/metrics`.
  - **Application & Cloudflare/Firewall Hardening Documentation ([README.md](file:///home/brandon/services/README.md))**:
    - Document Jellyfin networking and user security settings: setting `Known Proxies` in Jellyfin to NPM's `homelab` address so Jellyfin logs and rate-limits real external client IPs rather than NPM's internal IP; disabling remote (non-LAN) login for the Jellyfin administrator account; configuring login attempt lockout thresholds; and hiding users from the remote login screen.
- **README Updates ([README.md](file:///home/brandon/services/README.md))**:
  - Convert the networks section into a structured table listing all networks, subnets, gateways, drivers, parent interfaces, key static IP and DNS assignments (`nas.home` at `192.168.0.3` for the UGREEN NAS, `turing.home` at `192.168.0.4` for the NPM macvlan host, Pi-hole at `192.168.0.2` with CNAMEs pointing service subdomains to `turing.home`), and purpose.
  - Update the Port Mappings and Service Addresses documentation to replace Portainer with Dockge (`8010:5001`), add `qbittorrentvpn`, list each service's `*.turing.home` and external `*.kamaka.tech` addresses, and distinguish historical host ports from internal container ports.
  - Add sections documenting the setup/update script, local self-signed certificate generation (`generate-local-cert.sh`), NPM one-time SSL and Jellyfin hardening setup, bidirectional config sync, `.env.example` workflow, and backup script.

---

## 4. High-Level Implementation Plan

### Phase 1: Portainer Removal, Dockge Integration, and Compose Standardization
1. Delete [portainer/portainer.yml](file:///home/brandon/services/portainer/portainer.yml) and the `portainer/` directory.
2. Integrate Dockge configuration from `/opt/brandon/dockge/compose.yaml` (using an absolute data path, stripping emoji comments, and adding Homepage labels).
3. Normalize all `compose.yml` files:
   - Omit top-level `version` and `name`.
   - Set explicit `container_name` and matching `hostname` on every service.
   - Standardize `PUID=1000` and `PGID=100` (fixing `GUID` typos and adding `user: "1000:100"` where required).
   - Unify key ordering and `environment` syntax.
4. Comment out unnecessary `ports:` mappings in proxied services while preserving standardized comments recording internal and historical host ports.
5. Resolve the `internal` network reference in [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml).

### Phase 2: `.env.example` Templates and Secrets Extraction
1. Create `<stack>/.env.example` files with blank defaults (`KEY=`) for secrets (`VPN_USER`, `VPN_PASS`, etc.) and mandatory environment-specific settings.
2. Inline non-secret port variables from [homepage/.env](file:///home/brandon/services/homepage/.env) and [jellyfin/.env](file:///home/brandon/services/jellyfin/.env), and untrack live `.env` files from git (`git rm --cached`) so `.gitignore` protects live `.env` files while keeping them on disk.

### Phase 3: Volume Standardization and Bidirectional Config Sync (NPM, Homepage, Scripts)
1. Standardize `/volume1/docker` volume paths across `compose.yml` files (and migrate existing directories on disk if volume paths are renamed).
2. Retrieve existing live configuration files from `/volume1/docker/nginx/data/data/...`, `/volume1/docker/homepage/data/*.yaml`, and `/volume1/docker/qbittorrentvpn/data/getvpnport.sh` into the repository and commit them.
3. Implement bidirectional sync and setup automation:
   - `setup` / `deploy`: Creates Docker networks, initializes `.env` from `.env.example`, deploys repo configs to `/volume1/docker` with modification detection and overwrite/preserve prompts, and runs `docker compose up -d`.
   - `pull` / `sync-from-host`: Copies updated NPM, Homepage, and script configs from `/volume1/docker` back into the repo for git review and commit.
4. Fix [backup-homelab.bash](file:///home/brandon/services/backup-homelab.bash) (`BACKUP_DIR="/volume1/docker/backup/homelab"`, remove top-level `local`, remove redundant `mv`).

### Phase 4: Certificate Script and README Revision
1. Move `/home/brandon/generate-local-cert.sh` into the repository, remove `grace.home` from `DOMAINS`, and clean up obsolete `grace.home` entries from exported NPM configurations.
2. Update [README.md](file:///home/brandon/services/README.md) with:
   - The network configuration table and updated DNS/IP topology (`nas.home` = `192.168.0.3`, `turing.home` = `192.168.0.4` NPM macvlan, Pi-hole `192.168.0.2`).
   - Updated Port Mappings and Service Addresses table (`*.turing.home`).
   - Self-signed certificate generation (`generate-local-cert.sh`) and NPM one-time SSL/Cloudflare setup instructions.
   - Documentation for `.env.example` initialization, setup/deploy, config pull, and backup scripts.

---

## 5. Open Questions and Ambiguities to Clarify

Before executing or finalizing detailed specifications, the following questions remain for refinement:

1. **Volume Path Migration and `/volume1/Public` vs. `/volume1/media`**:
   - Currently, `nginx` uses `/volume1/docker/nginx/data/data` (double `data`), `sonarr-radarr` stores all three apps inside `/volume1/docker/radarr/data/{radarr_config,sonarr_config,prowlerr_config}`, `postgres` uses `/volume1/docker/postgresql/data`, and `dockge` uses `/opt/brandon/dockge/data`. Do you want to physically move/rename those directories on `/volume1/docker` so every service follows `/volume1/docker/<service>/data`, or keep the existing on-disk paths?
   - Additionally, `sonarr-radarr` and `qbitorrentvpn` still mount `/volume1/Public:/media` (which is empty), while `movies`, `shows`, `music`, and `downloads` are in `/volume1/media` (mounted by `jellyfin`). Should `sonarr`, `radarr`, and `qbitorrentvpn` be updated to mount `/volume1/media:/media`, and should `jellyfin` mount `/volume1/media:/data/media:ro` (read-only) for external security hardening?

2. **Dockge Placement**:
   - Do you want `dockge/compose.yml` placed directly inside `/opt/brandon/dockge/stacks/dockge/` as a stack folder, or stored in a repo config directory and deployed to `/opt/brandon/dockge/compose.yml` (one level above `stacks/`) so Dockge does not list itself as a self-managed stack in its own UI?

3. **Mandatory `.env.example` Variables vs. Inline Defaults**:
   - Which specific variables across the stacks should be extracted into `.env.example` (with blank defaults) vs. hardcoded in `compose.yml`? Candidates:
     - PIA credentials (`VPN_USER`, `VPN_PASS` in `qbitorrentvpn`)
     - Homepage widget API keys (`homepage.widget.key` in `jellyfin`, `sonarr-radarr`)
     - Tandoor `SECRET_KEY`
     - Local domain / hostnames (`turing.home`, `HOMEPAGE_ALLOWED_HOSTS`) or network IP (`192.168.0.4`)

4. **Scope of Port Removal**:
   - Should `dockge` keep `8010:5001` exposed on the host as a fallback if NPM goes down?
   - Should `nginx` keep `80:80`, `443:443`, `81:81` in `compose.yml` alongside its `external_npm` macvlan IP (`192.168.0.4`)?
   - Should `jellyfin` keep `8022:7359/udp` (autodiscovery) and `qbitorrentvpn` keep `58946:58946` TCP/UDP?

5. **Change Detection Mechanism for Target Files**:
   - When deploying configs from the repo to `/volume1/docker/...`, should the script prompt to overwrite whenever a target file's content differs from the repo file (`cmp` / `sha256sum`), or track a last-deployed checksum manifest so it only prompts if the target file was modified on the host *after* the last deploy?

6. **Tandoor `internal` Network**:
   - Should the unused `internal` network in [tandoor/compose.yml](file:///home/brandon/services/tandoor/compose.yml) be removed since [postgres/compose.yml](file:///home/brandon/services/postgres/compose.yml) communicates over `homelab`?
