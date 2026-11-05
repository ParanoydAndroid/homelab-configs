# Project Organization and Architecture

This document details the filesystem layout, container orchestrator design, storage tiering, and declarative configuration management model for the homelab repository.

---

## 1. Repository Directory Structure

The repository root is deployed at `${DOCKGE_STACKS_DIR}` (typically `/opt/${USER}/dockge/stacks`, symlinked to `~/services`). To maintain compatibility with Dockge, directory names at the root follow strict conventions:

```text
~/services/
├── compose stack directories/     # Each non-hidden directory represents a single Dockge stack
│   ├── books/                     # Calibre-Web, Bindery, and Royal Road sync
│   ├── dashboard/                 # Homepage dashboard
│   ├── ingress/                   # Caddy Docker Proxy + Cloudflare Tunnel
│   ├── media/                     # Jellyfin, Seerr, Sonarr, Radarr, Prowlarr, FlareSolverr
│   ├── mesh/                      # Tailscale Subnet Router + PIA WireGuard Exit Node
│   ├── productivity/              # Mealie Recipes
│   └── torrent/                   # WireGuard PIA, qBittorrent, and Cleanuparr
├── .configs/                      # Bootstrapping assets and systemd service templates
│   ├── caddy/                     # Base Caddyfile configuration template
│   ├── dockge/                    # Dockge's own compose.yml and .env.example
│   ├── qbittorrent/               # Port-sync callback script (set-qbt-port.sh)
│   └── systemd/                   # Host systemd unit and timer files
├── .scripts/                      # Modular automation library for homelab.sh
│   ├── common.sh                  # Logging, user resolution, and atomic dotenv utilities
│   ├── env-tools.sh               # Two-tier .env initialization and propagation
│   ├── system.sh                  # Host OS bug fixes and Docker network creation
│   └── backup.sh                  # Restic volume backup, retention pruning, and restore automation
├── .tests/                        # Modular smoke and regression test suite
│   ├── run.sh                     # Master test runner
│   ├── lib/common.sh              # Shared test assertions, timers, and counters
│   └── suites/                    # Test modules (containers, direct, routing, interconnect, security)
├── .docs/                         # Deep architectural and operational documentation
│   ├── project-organization.md    # This document
│   ├── service-catalog.md         # Uniform service entries, ports, and storage volumes
│   ├── performance-optimization.md# Post-setup optimization, ergonomics & maintenance guide
│   ├── env-reference.md           # Complete environment variable dictionary & cheat sheet
│   ├── networking.md              # Dual-ingress architecture, routing, and TLS certificates
│   └── operations.md              # CLI runbooks, systemd services, and storage operations
├── .agents/                       # Agent personas, instructions, rules, and architecture specs
│   ├── rules/                     # Project conventions (project-conventions.md)
│   ├── skills/                    # Operational runbooks (start-homelab, stack-lifecycle, etc.)
│   └── artifacts/                 # Versioned design plans and architecture specifications
├── .skills -> .agents/skills      # Convenience symlink for agent workflow skills
├── AGENTS.md -> .agents/rules/project-conventions.md # Canonical agent instructions symlink
├── homelab.sh                     # Primary CLI orchestration entrypoint
├── CHANGELOG.md                   # Semantic & CalVer release history
├── BACKLOG.md                     # Project technical debt and improvement backlog
├── README.md                      # Primary landing page and quickstart guide
└── .env.example                   # Global host path, network, and user defaults
```

---

## 2. Dockge Compatibility Rules

[Dockge](https://dockge.kuma.pet/) is a lightweight, visual Docker Compose stack manager. It imposes specific directory constraints that must be preserved:

1. **One Directory per Stack**:
   Each non-hidden folder at the repository root represents a self-contained Compose stack containing a `compose.yml` and an optional `.env` file.
2. **Dot-Prefixed Infrastructure Directories**:
   Dockge automatically scans every non-hidden directory in its stacks folder as a manageable Compose project. Non-stack assets (documentation, helper scripts, configuration templates, agent artifacts, and test suites) **must** reside in dot-prefixed directories (`.docs/`, `.scripts/`, `.configs/`, `.tests/`, `.agents/`). Dockge ignores hidden directories completely, preventing ghost or broken stacks from appearing in the UI.
3. **External Dockge Deployment**:
   Dockge cannot cleanly manage or restart its own container if its Compose file resides inside the stacks directory it watches. Dockge's own definition is tracked at [.configs/dockge/compose.yml](../.configs/dockge/compose.yml) and deployed to `${DOCKGE_DIR}/compose.yml` (`/opt/${USER}/dockge/compose.yml`, one level above `stacks/`).

---

## 3. Storage Tiering Architecture

The homelab hardware architecture separates storage into two distinct physical tiers to balance random I/O performance against large-capacity sequential storage:

| Storage Mount | Physical Hardware | Filesystem | Workload & Optimization |
| :--- | :--- | :--- | :--- |
| **`/volume1`** | 3x 10TB HDDs (RAID 5) | Btrfs | Bulk sequential storage for media libraries (`/volume1/media`) and compressed backup archives (`/volume1/backups`). Spinning mechanical disks excel at large continuous block reads/writes. |
| **`/volume2`** | 500GB NVMe SSD (M.2 Slot 1) | Btrfs | High-IOPS container configurations, databases, and image caches (`/volume2/docker`). Delivers 300,000+ random 4K IOPS with sub-millisecond seek latency. |

### Architectural Rationale
Applications like Jellyfin, Caddy Proxy, and Homepage perform continuous random read/write transactions against SQLite databases (`jellyfin.db`, `mealie.db`) and look up tens of thousands of image thumbnails and metadata files. On spinning disks, 10–15 ms mechanical head seeks cause poster pop-in, slow library browsing, and sluggish reverse proxy response times. 

Placing `${DOCKER_DATA_DIR}` on native PCIe NVMe eliminates seek latency entirely, reducing dashboard and streaming UI load times from 15+ seconds to under 1.5 seconds while keeping large video files safely on the fault-tolerant RAID 5 mechanical array.

*For post-setup tuning recommendations and interactive configurations across performance, ergonomics, and maintainability, see the [Post-Setup Optimization, Ergonomics & Maintenance Guide](./performance-optimization.md).*

---

## 4. Two-Tier Configuration & Dotenv Architecture

To satisfy Dockge's per-stack working directory model while eliminating configuration duplication, environment variables are managed through a two-tier structure:

1. **Root `.env.example` -> Root `.env`**:
   Defines global parameters shared across multiple stacks:
   * Host storage roots: `DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`
   * User & group IDs: `PUID`, `PGID`
   * Timezone: `TZ`
   * LAN network parameters: `EXTERNAL_NPM_PARENT`, `EXTERNAL_NPM_SUBNET`, `EXTERNAL_NPM_GATEWAY`, `NPM_IPV4_ADDRESS`, `TAILSCALE_IPV4_ADDRESS`
2. **Per-Stack `<stack>/.env.example` -> `<stack>/.env`**:
   Defines stack-specific secrets and service API keys (e.g., `VPN_USER`, `SECRET_KEY`, `JELLYFIN_API_KEY`).
3. **Automated Inheritance (`./homelab.sh setup`)**:
   `homelab.sh` reads the root `.env` and automatically synchronizes all referenced global variables into each `<stack>/.env` and `${DOCKGE_DIR}/.env`. This allows stacks to run seamlessly inside Dockge while remaining completely functional if launched standalone via `docker compose up -d`.
4. **Git Isolation**:
   All live `.env` files are ignored by git (`.gitignore`). Templates (`.env.example`) are tracked with placeholder values.

---

## 5. Persistent Volume Backup and Disaster Recovery Model

All container application state and persistent volumes under `${DOCKER_DATA_DIR}` (`/volume2/docker`) are protected via Restic snapshots and secret archiving:

* **Zero-Downtime Database Staging**:
  Prior to snapshotting, `homelab.sh backup` stages non-disruptive online database backups (SQLite `.backup` / WAL checkpoints for application databases) under `${DOCKER_DATA_DIR}/.backups`.
* **Untracked Secret Archiving**:
  All untracked live `.env` files are archived into a timestamped tarball in `${DOCKER_DATA_DIR}/backup/homelab/latest_env_secrets.tar.gz`.
* **Deduplicated & Compressed Snapshots (`./homelab.sh backup`)**:
  Streams deduplicated, compressed snapshots of `${DOCKER_DATA_DIR}` to `${BACKUP_RESTIC_REPO}` using native Restic (`--insecure-no-password`) with automatic cache and log exclusions, enforcing 30-day retention (`--keep-daily 30 --prune`).
* **Granular & Full Restoration (`./homelab.sh restore`)**:
  Restores either the full Docker volume or a single targeted service directory from any snapshot, with safety checks to ensure running containers are stopped before active files are modified.
