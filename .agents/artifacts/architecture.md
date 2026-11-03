# Homelab Architecture, Scope, and Design Philosophy

## 1. Project Purpose and Scope

This repository is the single source of truth for the declarative configuration, container orchestration, and lifecycle automation of the UGREEN NAS homelab environment (`nas.home` / `*.kamaka.tech`).

The project encompasses:
- **Containerized Service Stacks**: Declarative Docker Compose v2+ definitions across 6 domain-aligned stacks: edge routing and tunnels (`ingress`), mesh networking and privacy bridge (`mesh`), media streaming and acquisition (`media`), torrenting and download client (`torrent`), recipe management and database storage (`productivity`), and central dashboard (`dashboard`), with web-based stack orchestration via `dockge`.
- **Tracked Application Configurations (`.configs/`)**: Bootstrapping assets and templates—including Dockge orchestrator compose definitions, local certificate scripts, qBittorrent port-forwarding scripts, and systemd units/timers.
- **Lifecycle, Testing, and Backup Automation (`homelab.sh`)**: Idempotent CLI tooling for host OS workaround convergence, two-tier `.env` initialization and secret propagation, Docker network provisioning, non-disruptive Restic-based volume backups with online database staging, fast end-to-end smoke testing, and disaster recovery restoration.

---

## 2. Core Architectural Philosophy

### 2.1 Coalesced Git-Centric Configuration with Dockge Compatibility
- **Unified Repository and Orchestrator Directory**: The repository is checked out directly at `/opt/${USER}/dockge/stacks` (and symlinked to `${HOME}/services`). Every non-hidden directory at the repository root is a self-contained Docker Compose stack (`<stack>/compose.yml` + `<stack>/.env`) that can be managed either via the `homelab.sh` CLI or interactively through the Dockge Web UI.
- **Strict Root Directory Hygiene**: Non-stack directories are kept hidden (`.configs/`, `.agents/`) so Dockge never misidentifies documentation, agent metadata, or raw config files as runnable Compose stacks.
- **Externalized Orchestrator Stack**: Dockge's own `compose.yml` is tracked in `.configs/dockge/compose.yml` and deployed one level above the stacks directory (`${DOCKGE_DIR}/compose.yml`) so Dockge does not list or restart itself as a child stack.

### 2.2 Declarative Convergence and Idempotency
- Every operation in `homelab.sh` (`setup`, `startup`, `backup`, `snapshots`, `restore`) is idempotent and safe to run repeatedly on both brand-new host installations and routine updates after `git pull`.
- Host-level appliance workarounds (such as remediating the UGREEN NAS `GODEBUG=tlskyber=0` bug across `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`) are codified directly into `homelab.sh setup`.
- Persistent volume state and databases on `${DOCKER_DATA_DIR}` (`/volume2/docker`) are protected via automated Restic snapshots streamed to `${BACKUP_RESTIC_REPO}` with zero container downtime and 30-day retention pruning. Full or per-service disaster recovery is performed via `homelab.sh restore`.

### 2.3 Network Isolation and Reverse Proxy Boundary
- **Dedicated Reverse Proxy LAN IP (`external_npm` macvlan)**: Caddy binds to a dedicated LAN IP (`192.168.0.4`) via a Docker `macvlan` network on `eth0`, cleanly separating reverse-proxied service traffic (`80`, `443`) from the UGREEN NAS host OS web interface (`192.168.0.3` / `nas.home`).
- **Internal Service Bridge (`homelab`)**: All backend containers communicate over the isolated `homelab` Docker bridge network (`192.168.255.0/24`) using deterministic container hostnames and internal service ports.
- **Minimal Host Port Exposure**: Host ports on the NAS (`192.168.0.3`) are exposed only where strictly required for non-HTTP broadcast protocols (`jellyfin` UDP discovery on `8022:7359/udp`) or emergency fallback orchestration (`dockge` on `8010:5001/tcp`). All HTTP/HTTPS web UIs are accessed exclusively through Nginx Proxy Manager.
- **Defense-in-Depth for Externally Routable Services (`*.kamaka.tech`)**: Services exposed to the public internet through Cloudflare/gateway port forwarding (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`) enforce strict container and proxy hardening: non-root execution, dropped Linux capabilities (`cap_drop: [ALL]`), `no-new-privileges:true`, read-only media mounts (`:ro`), and reverse-proxy blocks on diagnostic/API-doc endpoints (`/swagger`, `/api-docs`, `/metrics`).

### 2.4 Two-Tier Environment and Secret Separation
- Zero credentials, API tokens, or cryptographic keys are committed to git.
- Because Dockge executes `docker compose` with the working directory set to each individual `<stack>/` folder, environment variables follow a two-tier `.env.example` -> `.env` model:
  1. **Root `.env.example`**: Defines global infrastructure defaults (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`). `homelab.sh` resolves dynamic user paths and propagates these global variables into every `<stack>/.env` and `${DOCKGE_DIR}/.env`.
  2. **Per-Stack `<stack>/.env.example`**: Declares stack-specific secrets and API keys (`VPN_USER`, `VPN_PASS`, `SECRET_KEY`, `*_API_KEY`, `QBITTORRENT_PASSWORD`, `HOMEPAGE_VAR_PIHOLE_KEY`) with blank defaults (`KEY=`). `homelab.sh` audits these keys on setup and warns if any required secret is unpopulated.

---

## 3. Standardized Repository and Volume Architecture

### 3.1 Repository Structure (`/opt/${USER}/dockge/stacks` / `${HOME}/services`)
```text
.
├── .agents/
│   ├── artifacts/
│   │   └── architecture.md
│   └── rules/
│       └── project-conventions.md
├── .configs/
│   ├── dockge/
│   │   ├── .env.example
│   │   └── compose.yml
│   ├── nginx/
│   │   └── generate-local-cert.sh
│   ├── qbittorrentvpn/
│   │   └── set-qbt-port.sh
│   └── systemd/
│       ├── antigravity-remote-control.service
│       ├── homelab-backup.service
│       ├── homelab-backup.timer
│       └── homelab-startup.service
├── .env.example
├── .gitignore
├── .skills -> .agents/skills
├── AGENTS.md -> .agents/rules/project-conventions.md
├── CHANGELOG.md
├── BACKLOG.md
├── README.md
├── homelab.sh
├── dashboard/
│   ├── .env.example
│   └── compose.yml
├── ingress/
│   ├── .env.example
│   └── compose.yml
├── media/
│   ├── .env.example
│   └── compose.yml
├── mesh/
│   ├── .env.example
│   └── compose.yml
├── productivity/
│   ├── .env.example
│   └── compose.yml
└── torrent/
    ├── .env.example
    └── compose.yml
```

### 3.2 Host Volume Layout (`/volume2/docker` and `/volume1/media`)
- `/volume2/docker/dockge/data` -> `/app/data` (`dockge`)
- `/volume2/docker/homepage/data` -> `/app/config` (`homepage`)
- `/volume2/docker/jellyfin/data/config` -> `/config` (`jellyfin`)
- `/volume2/docker/nginx/data` -> `/data` (`nginx`)
- `/volume2/docker/nginx/data/letsencrypt` -> `/etc/letsencrypt` (`nginx`)
- `/volume2/docker/postgres/data` -> `/var/lib/postgresql/data` (`postgresql`)
- `/volume2/docker/qbittorrentvpn/data/pia` -> `/pia` (`wireguard-pia`)
- `/volume2/docker/qbittorrentvpn/data/pia-shared` -> `/pia-shared` (`wireguard-pia`)
- `/volume2/docker/qbittorrentvpn/data/set-qbt-port.sh` -> `/set-qbt-port.sh:ro` (`wireguard-pia`)
- `/volume2/docker/qbittorrentvpn/data/config` -> `/config` (`qbittorrentvpn`)
- `/volume2/docker/qbittorrentvpn/data/incomplete` -> `/incomplete` (`qbittorrentvpn`)
- `/volume2/docker/radarr/data` -> `/config` (`radarr`)
- `/volume2/docker/sonarr/data` -> `/config` (`sonarr`)
- `/volume2/docker/prowlarr/data` -> `/config` (`prowlarr`)
- `/volume2/docker/seerr/data` -> `/app/config` (`seerr`)
- `/volume2/docker/tailscale/data` -> `/var/lib/tailscale` (`tailscale`)
- `/volume2/docker/vpn-bridge/data/pia` -> `/pia` (`vpn-bridge-pia`)
- `/volume2/docker/vpn-bridge/data/tailscale` -> `/var/lib/tailscale` (`vpn-bridge-tailscale`)
- `/volume2/docker/tandoor/data/staticfiles` -> `/opt/recipes/staticfiles` (`tandoor`)
- `/volume2/docker/tandoor/data/mediafiles` -> `/opt/recipes/mediafiles` (`tandoor`) and `/media:ro` (`nginx`)
- `/volume2/docker/backup/homelab` -> Archive output directory for untracked `.env` secret tarballs (`homelab.sh backup`)
- `/volume1/media` -> `/media` (`radarr`, `sonarr`, `qbittorrentvpn`) and `/data/media:ro` (`jellyfin`)
- `/var/run/docker.sock` -> `/var/run/docker.sock` (`dockge`, `homepage`)
- `/opt/${USER}/dockge/stacks` -> `${DOCKGE_STACKS_DIR}` (`dockge`)
- `/dev/net/tun` -> `/dev/net/tun` (`tailscale`, `vpn-bridge-tailscale`)
- `/dev/dri/renderD128` -> `/dev/dri/renderD128` (`jellyfin`)

### 3.3 Container Privilege and UID/GID Model

| Service / Container | Image | UID/GID Mechanism | Host Volume Ownership |
| :--- | :--- | :--- | :--- |
| `jellyfin` | `jellyfin/jellyfin:latest` | Compose `user: "${PUID}:${PGID}"` + `group_add: ["105"]` (official image ignores `PUID`/`PGID` env vars) | `1000:100` |
| `radarr`, `sonarr`, `prowlarr` | `lscr.io/linuxserver/*:latest` | Env `PUID: ${PUID}`, `PGID: ${PGID}` (s6 init starts as root then drops to `PUID:PGID`) | `1000:100` |
| `seerr` | `ghcr.io/seerr-team/seerr:latest` | Runs rootless as non-privileged UID `1000` (`node`) with `init: true`, `cap_drop: [ALL]`, and `no-new-privileges:true` | `1000:100` |
| `wireguard-pia` | `thrnz/docker-wireguard-pia:latest` | Runs with `cap_add: [NET_ADMIN]` to manage kernel `wg0`, `iptables` kill switch, and PIA port forwarding (`PORT_SCRIPT: /set-qbt-port.sh`) | `1000:100` |
| `qbittorrentvpn` | `lscr.io/linuxserver/qbittorrent:latest` | Env `PUID: ${PUID}`, `PGID: ${PGID}` with `network_mode: "service:vpn"` (s6 init starts as root then drops to `PUID:PGID`) | `1000:100` |
| `tandoor` | `vabene1111/recipes` | Env `PUID: ${PUID}`, `PGID: ${PGID}` (`boot.sh` starts as root then drops to `PUID:PGID`) | `1000:100` |
| `postgresql` | `postgres:16-alpine` | Internal Alpine `postgres` user (`70:70`); do not set `PUID`/`PGID` or `user:` | `70:70` |
| `homepage` | `ghcr.io/gethomepage/homepage:latest` | Env `PUID: 0`, `PGID: 0` (requires root for `/var/run/docker.sock`) | `0:0` |
| `nginx` | `jc21/nginx-proxy-manager:latest` | Runs as `root` internally; do not set `user:` | `0:0` |
| `tailscale` | `tailscale/tailscale:latest` | Runs as `root` with `cap_add: [NET_ADMIN, NET_RAW]` and `/dev/net/tun` to manage kernel WireGuard and `iptables` | `0:0` |
| `cloudflared` | `cloudflare/cloudflared:latest` | Stateless; runs rootless non-root internally; outbound egress tunnel authenticated via `CLOUDFLARE_TUNNEL_TOKEN` | N/A |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr:latest` | Stateless; uses internal non-root user; no persistent volume | N/A |
| `dockge` | `louislam/dockge:1` | Runs as `root` for `/var/run/docker.sock` | `0:0` |
| `vpn-bridge-pia` | `thrnz/docker-wireguard-pia:latest` | Runs with `cap_add: [NET_ADMIN]` to manage kernel `wg0`, `iptables` NAT forwarding (`FWD_IFACE: tailscale+`), and PIA kill switch | `1000:100` |
| `vpn-bridge-tailscale` | `tailscale/tailscale:latest` | Runs as `root` with `cap_add: [NET_ADMIN, NET_RAW]`, `/dev/net/tun`, and `network_mode: "service:vpn"` | `1000:100` |

