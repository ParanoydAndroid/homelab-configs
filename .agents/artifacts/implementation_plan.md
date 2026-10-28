# Homelab Services Standardization and Automation Implementation Plan

## 1. Project Overview and Target State

This document is the authoritative, step-by-step implementation specification for an executing agent (working with human approval checkpoints) to standardize, migrate, automate, and document the homelab services repository.

Upon completion of this plan:
1. All legacy host volume paths under `/volume1/docker`, legacy UID/GID ownership (`1027` and `0:0`), and inline secrets will be migrated to the standardized target layout via a temporary one-time script (`migrate-once.sh`) that is deleted before final commit.
2. All Docker Compose stacks (`homepage`, `jellyfin`, `nginx`, `postgres`, `qbittorrentvpn`, `sonarr-radarr`, `tandoor`) and the external Dockge orchestrator (`.configs/dockge/compose.yml` deployed to `${DOCKGE_DIR}/compose.yml`) will follow a uniform Compose Specification v2+ schema and a two-tier `.env.example` / `.env` configuration model.
3. Tracked service configurations (`.configs/dockge`, `.configs/nginx`, `.configs/homepage`, `.configs/qbittorrentvpn`) will be versioned in git and bidirectionally synced via `homelab.sh` (`setup`, `deploy-configs`, `pull-configs`, `backup`).
4. [README.md](file:///home/brandon/services/README.md) will provide complete documentation covering network topology, service and port mappings, quickstart setup, one-time SSL/security procedures, and operational use-case guides.
5. All services will be running healthy on the host and all tracked files will be committed cleanly to git.

---

## 2. Verified Architecture and Command Assumptions

The following technical findings were verified against the live UGREEN NAS environment and container images and must be respected during execution:

### 2.1 Container UID/GID (`user:` vs. `PUID`/`PGID`) Matrix
Setting Compose `user: "1000:100"` blindly on all containers will break images whose entrypoints require `root` at startup to configure `s6-overlay`, `iptables`, `openvpn`, or `/var/run/docker.sock`. Apply UID/GID settings strictly per image architecture:

| Service / Container | Image | UID/GID Mechanism | Target Ownership on `/volume1/docker/<service>/data` |
| :--- | :--- | :--- | :--- |
| `jellyfin` | `jellyfin/jellyfin:latest` | Compose `user: "${PUID:-1000}:${PGID:-100}"` + `group_add: ["105"]` (official image ignores `PUID`/`PGID` env vars) | `1000:100` |
| `radarr`, `sonarr`, `prowlarr` | `lscr.io/linuxserver/*:latest` | Env `PUID: ${PUID:-1000}`, `PGID: ${PGID:-100}` (do NOT set Compose `user:`; s6 init starts as root then drops to `PUID:PGID`) | `1000:100` |
| `wireguard-pia` | `thrnz/docker-wireguard-pia:latest` | Runs with `cap_add: [NET_ADMIN]` to manage kernel `wg0`, `iptables` kill switch, and PIA port forwarding (`PORT_SCRIPT: /set-qbt-port.sh`) | `1000:100` |
| `qbittorrentvpn` | `lscr.io/linuxserver/qbittorrent:latest` | Env `PUID: ${PUID:-1000}`, `PGID: ${PGID:-100}` with `network_mode: "service:vpn"` (do NOT set Compose `user:`; s6 init starts as root then drops to `PUID:PGID`) | `1000:100` |
| `tandoor` | `vabene1111/recipes` | Env `PUID: ${PUID:-1000}`, `PGID: ${PGID:-100}` (do NOT set Compose `user:`; `boot.sh` runs as root then drops to `PUID:PGID`) | `1000:100` |
| `postgresql` | `postgres:16-alpine` | Internal Alpine `postgres` user (`70:70`); do NOT set `PUID`/`PGID` or `user:`, and NEVER `chown` `/volume1/docker/postgres/data` to `1000:100` | `70:70` (untouched) |
| `homepage` | `ghcr.io/gethomepage/homepage:latest` | Env `PUID: 0`, `PGID: 0` (fixes `GUID: 0` typo; requires root for `/var/run/docker.sock`) | `0:0` (untouched) |
| `nginx` | `jc21/nginx-proxy-manager:latest` | Runs as `root` internally; do NOT set `user:` | `0:0` (untouched) |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr:latest` | Stateless; uses internal non-root user; no persistent volume | N/A |
| `dockge` | `louislam/dockge:1` | Runs as `root` for `/var/run/docker.sock` (ignores `PUID`/`PGID` env vars; omit them) | `0:0` (untouched) |

### 2.2 Tandoor Media Serving via Nginx Proxy Manager (`/media:ro`)
- Inspecting `/volume1/docker/nginx/data/data/nginx/proxy_host/2.conf` (`recipes.kamaka.tech` -> `tandoor:8050`) confirmed that NPM uses a custom rule:
  ```nginx
  location /media/ {
      root /;
  }
  ```
- Because Tandoor's Gunicorn server does not serve `/media/` directly in production, NPM serves uploaded recipe images from `/media/...` inside the `nginx` container.
- Therefore, when `/volume1/docker/media` is migrated to `${DOCKER_DATA_DIR:-/volume1/docker}/tandoor/data/mediafiles`, [nginx/compose.yml](file:///home/brandon/services/nginx/compose.yml) **must retain this read-only volume mount updated to**:
  `- ${DOCKER_DATA_DIR:-/volume1/docker}/tandoor/data/mediafiles:/media:ro`

### 2.3 NPM Configuration Sync and Fresh-Install Certificate Guard
- NPM stores its configuration state in `/data/db.sqlite` and generates Nginx config files under `/data/nginx/{proxy_host,dead_host,redirection_host,default_host,default_www,custom}`.
- On a brand-new host where Let's Encrypt (`npm-3`, `npm-5`) or custom (`npm-7`) SSL certificates have not yet been created in NPM, copying `proxy_host/*.conf` files that reference missing `/etc/letsencrypt/live/npm-*/fullchain.pem` or `/data/custom_ssl/npm-*/fullchain.pem` paths will cause `nginx -t` to fail and crash-loop the `nginx` container before the user can access the NPM Admin UI (`http://192.168.0.4:81`).
- Therefore, `homelab.sh deploy-configs` must check whether every `ssl_certificate` path referenced in an NPM `.conf` file exists on disk under `${DOCKER_DATA_DIR}/nginx/data/` before copying that `.conf` file. If a referenced certificate file is missing, `homelab.sh` skips deploying that `.conf` file and prints a warning directing the user to complete the one-time SSL setup in `README.md` and re-run `./homelab.sh deploy-configs`.

### 2.4 Stack Directory Naming Alignment (`qbitorrentvpn` -> `qbittorrentvpn`)
- The stack directory currently has a single-`t` typo (`qbitorrentvpn/`), while the container name, hostname, and host data volume use `qbittorrentvpn`.
- During the one-time migration, rename `qbitorrentvpn/` to `qbittorrentvpn/` (`git mv qbitorrentvpn qbittorrentvpn`) so stack folder, service name, `container_name`, `hostname`, `.configs/qbittorrentvpn/`, and `/volume1/docker/qbittorrentvpn/data` match 1:1.

### 2.5 Executing Agent Sandbox Boundaries
- Standard workspace file tools (`write_file`, `edit_file`) can create and modify files inside `/home/brandon/services`.
- However, in the Antigravity command sandbox (`BypassSandbox: false`), `.git/` is mounted read-only and `/volume1/docker`, `/volume1/media`, `/opt/${USER}/dockge/compose.yaml`, `/var/run/docker.sock`, `/etc/profile.d`, and `/etc/systemd` are outside the sandbox.
- Any `run_command` step that runs `git`, `docker`, `sqlite3`, or accesses `/volume1/`, `/opt/`, or `/etc/` **must be invoked with `BypassSandbox: true`** (which prompts the user for approval).

---

## 3. Target Directory and Configuration Architecture

### 3.1 Repository Layout (`/opt/${USER}/dockge/stacks` / `/home/${USER}/services`)
```text
.
├── .agents/
│   ├── artifacts/
│   │   └── implementation_plan.md
│   └── rules/
│       └── project-conventions.md
├── .configs/
│   ├── dockge/
│   │   ├── .env.example
│   │   └── compose.yml
│   ├── homepage/
│   │   └── *.yaml
│   ├── nginx/
│   │   ├── generate-local-cert.sh
│   │   ├── npm_hosts.sql
│   │   └── nginx/
│   │       ├── dead_host/
│   │       ├── default_host/
│   │       ├── default_www/
│   │       └── proxy_host/
│   └── qbittorrentvpn/
│       └── set-qbt-port.sh
├── .env.example
├── .gitignore
├── README.md
├── homelab.sh
├── homepage/
│   └── compose.yml
├── jellyfin/
│   ├── .env.example
│   └── compose.yml
├── nginx/
│   └── compose.yml
├── postgres/
│   └── compose.yml
├── qbittorrentvpn/
│   ├── .env.example
│   └── compose.yml
├── sonarr-radarr/
│   ├── .env.example
│   └── compose.yml
└── tandoor/
    ├── .env.example
    └── compose.yml
```

### 3.2 Standardized Host Volume Layout (`/volume1/docker` and `/volume1/media`)
- `/volume1/docker/dockge/data` -> `/app/data` (`dockge`)
- `/volume1/docker/homepage/data` -> `/app/config` (`homepage`)
- `/volume1/docker/jellyfin/data/config` -> `/config` (`jellyfin`)
- `/volume1/docker/nginx/data` -> `/data` (`nginx`)
- `/volume1/docker/nginx/data/letsencrypt` -> `/etc/letsencrypt` (`nginx`)
- `/volume1/docker/postgres/data` -> `/var/lib/postgresql/data` (`postgresql`)
- `/volume1/docker/qbittorrentvpn/data/pia` -> `/pia` (`wireguard-pia`)
- `/volume1/docker/qbittorrentvpn/data/pia-shared` -> `/pia-shared` (`wireguard-pia`)
- `/volume1/docker/qbittorrentvpn/data/set-qbt-port.sh` -> `/set-qbt-port.sh:ro` (`wireguard-pia`)
- `/volume1/docker/qbittorrentvpn/data/config` -> `/config` (`qbittorrentvpn`)
- `/volume1/docker/radarr/data` -> `/config` (`radarr`)
- `/volume1/docker/sonarr/data` -> `/config` (`sonarr`)
- `/volume1/docker/prowlarr/data` -> `/config` (`prowlarr`)
- `/volume1/docker/tandoor/data/staticfiles` -> `/opt/recipes/staticfiles` (`tandoor`)
- `/volume1/docker/tandoor/data/mediafiles` -> `/opt/recipes/mediafiles` (`tandoor`) and `/media:ro` (`nginx`)
- `/volume1/docker/backup/homelab` -> Archive output directory for untracked `.env` secret tarballs (`homelab.sh backup`)
- `/volume1/media` -> `/media` (`radarr`, `sonarr`, `qbittorrentvpn`) and `/data/media:ro` (`jellyfin`)

### 3.3 Two-Tier `.env.example` Specification

1. **Root `.env.example`** (and `.configs/dockge/.env.example`):
   ```dotenv
   DOCKER_DATA_DIR=/volume1/docker
   MEDIA_DIR=/volume1/media
   DOCKGE_DIR=/opt/${USER}/dockge
   DOCKGE_STACKS_DIR=/opt/${USER}/dockge/stacks
   PUID=1000
   PGID=100
   TZ=America/New_York
   EXTERNAL_NPM_SUBNET=192.168.0.0/24
   EXTERNAL_NPM_GATEWAY=192.168.0.1
   EXTERNAL_NPM_PARENT=eth0
   NPM_IPV4_ADDRESS=192.168.0.4
   ```
   When `homelab.sh` initializes `.env` from `.env.example`, it resolves `${SUDO_USER:-${USER}}` to a literal username (e.g., `/opt/brandon/dockge`) and syncs all root `.env` variables into each `<stack>/.env` and `${DOCKGE_DIR}/.env`.

2. **Per-Stack `<stack>/.env.example` Templates**:
   - `jellyfin/.env.example`:
     ```dotenv
     JELLYFIN_WIDGET_KEY=
     ```
   - `qbittorrentvpn/.env.example`:
     ```dotenv
     VPN_USER=
     VPN_PASS=
     QBITTORRENT_WIDGET_PASSWORD=
     ```
   - `sonarr-radarr/.env.example`:
     ```dotenv
     RADARR_WIDGET_KEY=
     SONARR_WIDGET_KEY=
     PROWLARR_WIDGET_KEY=
     ```
   - `tandoor/.env.example`:
     ```dotenv
     SECRET_KEY=
     ```

---

## 4. Step-by-Step Execution Plan

### Step 1: Author `.env.example` Templates, Standardized `compose.yml` Files, and `homelab.sh`
*(Execution Mode: Workspace file tools — no sandbox bypass required)*

1. **Create `.env.example` Templates**:
   - Create root `.env.example`, `.configs/dockge/.env.example`, `jellyfin/.env.example`, `qbitorrentvpn/.env.example` (prior to folder rename), `sonarr-radarr/.env.example`, and `tandoor/.env.example` as specified in Section 3.3.
2. **Create `.configs/dockge/compose.yml`**:
   - Standardize from `/opt/${USER}/dockge/compose.yaml`: omit top-level `name:`, set `container_name: dockge` and `hostname: dockge`, remove unused `PUID`/`PGID` env vars, strip emoji comments, use `${DOCKER_DATA_DIR:-/volume1/docker}/dockge/data:/app/data` and `${DOCKGE_STACKS_DIR}:${DOCKGE_STACKS_DIR}`, retain `ports: ["8010:5001"]`, and add `homepage.*` labels (`Administration`, `Dockge`, `http://dockge.turing.home`).
3. **Create `.configs/nginx/generate-local-cert.sh`**:
   - Copy from `/home/${USER}/generate-local-cert.sh`, set `DOMAINS=("turing.home" "nas.home")` (removing `grace.home`), and make executable.
4. **Standardize All Stack `compose.yml` Files**:
   - Follow the key order in [project-conventions.md](file:///home/brandon/services/.agents/rules/project-conventions.md): `image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `cap_drop`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`.
   - Use map syntax (`KEY: value`) for `environment:` across all stacks.
   - Apply stack-specific updates:
     - `homepage/compose.yml`: Fix `GUID: 0` -> `PGID: 0`, set `HOMEPAGE_ALLOWED_HOSTS: ${HOMEPAGE_ALLOWED_HOSTS:-homepage.turing.home,www.turing.home,turing.home,192.168.0.4}`, comment out `ports:` (`# - 8030:3000/tcp`), use `${DOCKER_DATA_DIR:-/volume1/docker}/homepage/data:/app/config`.
     - `jellyfin/compose.yml`: Add `user: "${PUID:-1000}:${PGID:-100}"`, `cap_drop: [ALL]`, fix `GUID` -> `PGID`, mount `${MEDIA_DIR:-/volume1/media}:/data/media:ro`, comment out HTTP/HTTPS ports (`8020:8096/tcp`, `8021:8920/tcp`), keep `8022:7359/udp`, update widget label to `${JELLYFIN_WIDGET_KEY}`.
     - `nginx/compose.yml`: Add `hostname: nginx`, comment out `ports:` (`80:80`, `443:443`, `81:81`), update volumes to `${DOCKER_DATA_DIR:-/volume1/docker}/nginx/data:/data`, `${DOCKER_DATA_DIR:-/volume1/docker}/nginx/data/letsencrypt:/etc/letsencrypt`, and `${DOCKER_DATA_DIR:-/volume1/docker}/tandoor/data/mediafiles:/media:ro`, parameterize `ipv4_address: ${NPM_IPV4_ADDRESS:-192.168.0.4}`.
     - `postgres/compose.yml`: Add `hostname: postgresql`, comment out port `# - 5432:5432/tcp`, update volume to `${DOCKER_DATA_DIR:-/volume1/docker}/postgres/data:/var/lib/postgresql/data`.
     - `qbitorrentvpn/compose.yml`: Remove `version: "3.5"`, add `hostname: qbittorrentvpn`, set `PUID: ${PUID:-1000}` and `PGID: ${PGID:-100}`, extract `VPN_USER: ${VPN_USER}`, `VPN_PASS: ${VPN_PASS}`, and `homepage.widget.password=${QBITTORRENT_WIDGET_PASSWORD}`, update media volume to `${MEDIA_DIR:-/volume1/media}:/media`, comment out `8081:8081` while keeping `58946:58946` TCP/UDP.
     - `sonarr-radarr/compose.yml`: Add `hostname:` (`radarr`, `sonarr`, `prowlarr`, `flaresolverr`), set `PUID: ${PUID:-1000}` and `PGID: ${PGID:-100}`, update config volumes to `${DOCKER_DATA_DIR:-/volume1/docker}/{radarr,sonarr,prowlarr}/data:/config` and media volumes to `${MEDIA_DIR:-/volume1/media}:/media`, comment out host ports (`8040`, `8041`, `8042`, `8043`), extract `${RADARR_WIDGET_KEY}`, `${SONARR_WIDGET_KEY}`, `${PROWLARR_WIDGET_KEY}`.
     - `tandoor/compose.yml`: Add `hostname: tandoor`, add `PUID: ${PUID:-1000}` and `PGID: ${PGID:-100}`, extract `SECRET_KEY: ${SECRET_KEY}`, update mediafiles volume to `${DOCKER_DATA_DIR:-/volume1/docker}/tandoor/data/mediafiles:/opt/recipes/mediafiles`, comment out `8050:8050`, remove `internal` network.
5. **Create `homelab.sh` and Update `backup-homelab.bash`**:
   - Implement `homelab.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`, supporting subcommands:
     - `setup`:
       1. Remediates UGREEN NAS `GODEBUG=tlskyber=0` in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf` (using `sudo` if needed) and unsets `GODEBUG` from systemd manager environments.
       2. Initializes root `.env` from `.env.example` (resolving `${SUDO_USER:-${USER}}` into literal paths), initializes missing `<stack>/.env` files from `<stack>/.env.example`, syncs root `.env` global variables into every `<stack>/.env` and `${DOCKGE_DIR}/.env`, and warns if any required per-stack secret variables are empty.
       3. Creates Docker networks `homelab` (`192.168.255.0/24`, gateway `192.168.255.1`, bridge) and `external_npm` (`${EXTERNAL_NPM_SUBNET}`, gateway `${EXTERNAL_NPM_GATEWAY}`, macvlan on `${EXTERNAL_NPM_PARENT}`) idempotently if missing.
       4. Invokes `deploy-configs` to sync `.configs/` to `${DOCKER_DATA_DIR}` and `${DOCKGE_DIR}/compose.yml`.
       5. Starts Dockge (`docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d`) and all stacks in dependency order (`postgres`, `nginx`, `homepage`, `jellyfin`, `qbittorrentvpn`, `sonarr-radarr`, `tandoor`).
     - `deploy-configs`:
       - Compares tracked files in `.configs/homepage/`, `.configs/qbittorrentvpn/`, `.configs/nginx/nginx/`, and `.configs/dockge/compose.yml` against their host targets using `cmp -s`.
       - For NPM `.conf` files in `.configs/nginx/nginx/{proxy_host,dead_host}/`, verifies that any `ssl_certificate` file referenced in the `.conf` exists under `${DOCKER_DATA_DIR}/nginx/data/` (or `${DOCKER_DATA_DIR}/nginx/data/letsencrypt/`) before deploying; if missing, skips and warns the user.
       - When target files exist and differ, displays `diff -u` and prompts `[o]verwrite / [k]eep / [O]verwrite all / [K]eep all`.
       - Reloads Nginx (`docker exec nginx nginx -s reload`) if any NPM config was updated and `nginx` is running.
     - `pull-configs`:
       - Copies `/volume1/docker/homepage/data/*.{yaml,yml,css,js}` to `.configs/homepage/`.
       - Copies `/volume1/docker/qbittorrentvpn/data/getvpnport.sh` to `.configs/qbittorrentvpn/getvpnport.sh`.
       - Exports NPM tables (`proxy_host`, `dead_host`, `redirection_host`, `setting`) from `/volume1/docker/nginx/data/db.sqlite` via `sqlite3` into `.configs/nginx/npm_hosts.sql` and copies `/volume1/docker/nginx/data/nginx/{proxy_host,dead_host,redirection_host,default_host,default_www}` into `.configs/nginx/nginx/`.
     - `backup`:
       - Creates `${DOCKER_DATA_DIR}/backup/homelab/$(date +%Y%m%d)_homelab_config.tar.gz` archiving `README.md`, `homelab.sh`, `.configs/`, all `.env.example` and live `.env` files, stack `compose.yml` files, and live Homepage/NPM/qBittorrentVPN portable config files.
   - Replace `backup-homelab.bash` contents with a clean wrapper calling `exec "$(dirname "$0")/homelab.sh" backup "$@"`.

### Step 2: Create and Execute `migrate-once.sh` (Human Approval Checkpoint 1)
*(Execution Mode: Write `migrate-once.sh` with workspace tool, then execute with `BypassSandbox: true`)*

1. **Create `migrate-once.sh`** to perform the one-time brownfield migration idempotently:
   - **Pre-flight & Secret Preservation**:
     - Write active credentials extracted from the pre-migration files into root `.env`, `${DOCKGE_DIR}/.env`, `jellyfin/.env`, `qbitorrentvpn/.env`, `sonarr-radarr/.env`, and `tandoor/.env`.
     - Rename `qbitorrentvpn/` -> `qbittorrentvpn/` (`git mv qbitorrentvpn qbittorrentvpn`), untrack `homepage/.env` and `jellyfin/.env` (`git rm --cached homepage/.env jellyfin/.env`), and remove `portainer/` and `tools.sh` (`git rm -rf portainer tools.sh`).
   - **Stop Running Containers**:
     - Stop all running compose stacks and Dockge (`docker stop tandoor sonarr radarr prowlarr flaresolverr qbittorrentvpn jellyfin homepage nginx postgresql dockge 2>/dev/null || true`).
   - **Migrate Host Volume Paths on `/volume1/docker`**:
     - `nginx`: If `/volume1/docker/nginx/data/data` exists, move its contents into `/volume1/docker/nginx/data/` (`shopt -s dotglob; mv /volume1/docker/nginx/data/data/* /volume1/docker/nginx/data/ && rmdir /volume1/docker/nginx/data/data`).
     - `sonarr-radarr`: Move `/volume1/docker/radarr/data/sonarr_config` -> `/volume1/docker/sonarr/data`, `/volume1/docker/radarr/data/prowlerr_config` -> `/volume1/docker/prowlarr/data`, and `/volume1/docker/radarr/data/radarr_config/*` -> `/volume1/docker/radarr/data/` (removing `radarr_config`).
     - `postgres`: Move `/volume1/docker/postgresql/data` -> `/volume1/docker/postgres/data` (and `rmdir /volume1/docker/postgresql`).
     - `tandoor`: Move `/volume1/docker/media/*` into `/volume1/docker/tandoor/data/mediafiles/` and remove `/volume1/docker/media`.
     - `dockge`: Move `/opt/brandon/dockge/data` -> `/volume1/docker/dockge/data` and remove `/opt/brandon/dockge/compose.yaml` (replaced by `compose.yml`).
     - Delete obsolete `/volume1/docker/portainer`, `/volume1/docker/qbittorrent`, `/volume1/docker/port_mappings.yaml`, and `/home/brandon/generate-local-cert.sh` / `/home/brandon/cert.conf`.
   - **Clean Obsolete `grace.home` Entries and Harden `jellyfin.kamaka.tech` in NPM `db.sqlite`**:
     - Back up `/volume1/docker/nginx/data/db.sqlite` to `/volume1/docker/nginx/data/db.sqlite.bak`.
     - Using `sqlite3 /volume1/docker/nginx/data/db.sqlite`:
       - Delete `dead_host` rows for `grace.home` and `www.grace.home` and delete `/volume1/docker/nginx/data/nginx/dead_host/{1,2}.conf`.
       - Update `proxy_host` id `4` (`jellyfin.turing.home`) `domain_names` to `["jellyfin.turing.home"]` (removing `jellyfin.grace.home`) and update `/volume1/docker/nginx/data/nginx/proxy_host/4.conf` `server_name` accordingly.
       - Update `proxy_host` id `3` (`jellyfin.kamaka.tech`) to set `allow_websocket_upgrade = 1` and `advanced_config` with the Jellyfin streaming/security/IP headers and `/swagger`, `/api-docs`, `/metrics` blocks, and update `/volume1/docker/nginx/data/nginx/proxy_host/3.conf` to match.
   - **One-Time Permission Remediation**:
     - `chown -R 1000:100` on `/volume1/docker/{jellyfin,radarr,sonarr,prowlarr,qbittorrentvpn,tandoor}/data`.
     - Delete `/volume1/docker/qbittorrentvpn/data/config/perms.txt` so `binhex` re-applies UID `1000` / GID `100` cleanly.
2. **Human Checkpoint 1**:
   - Prompt the user to approve running `sudo ./migrate-once.sh` via `run_command` (`BypassSandbox: true`).
   - Verify directory structure under `/volume1/docker`, then delete `migrate-once.sh`.

### Step 3: Pull Tracked Configurations and Run `./homelab.sh setup` (Human Approval Checkpoint 2)
*(Execution Mode: `BypassSandbox: true`)*

1. Run `./homelab.sh pull-configs` to populate `.configs/homepage/`, `.configs/nginx/`, and `.configs/qbittorrentvpn/getvpnport.sh` from the migrated `/volume1/docker` directories.
2. Run `sudo ./homelab.sh setup` to:
   - Apply the UGREEN NAS `GODEBUG=tlskyber=0` fix.
   - Verify/create the `homelab` and `external_npm` Docker networks.
   - Sync `.env` files across all stacks and `${DOCKGE_DIR}/.env`.
   - Deploy `.configs/dockge/compose.yml` to `${DOCKGE_DIR}/compose.yml`.
   - Start Dockge and all seven service stacks (`postgres`, `nginx`, `homepage`, `jellyfin`, `qbittorrentvpn`, `sonarr-radarr`, `tandoor`).
3. Run `./homelab.sh backup` to verify that backup archive creation succeeds into `/volume1/docker/backup/homelab/`.

### Step 4: Verify Service Health and Finalize Git Commit (Human Approval Checkpoint 3)
*(Execution Mode: `BypassSandbox: true`)*

1. Verify all containers are running without restart loops or permission errors (`docker ps` and `docker logs` check on `postgresql`, `tandoor`, `nginx`, `jellyfin`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr`, `qbittorrentvpn`, `homepage`, `dockge`).
2. Verify `git status` and `git diff` to confirm:
   - Zero `.env` files or secrets are tracked in the git index.
   - `migrate-once.sh`, `portainer/`, and `tools.sh` are removed.
   - All `.configs/`, `.env.example`, `compose.yml`, `homelab.sh`, `backup-homelab.bash`, `README.md`, and `.agents/` files are clean and formatted without emojis/icons.
3. Stage all changes (`git add -A`) and commit to `main`.
