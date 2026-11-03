---
name: start-homelab
description: >-
  Interactive onboarding and scaffolding runbook for developers instantiating a new
  homelab from this template repository. Guides project orientation, service needs
  assessment (keep, defer, prune), hardware/platform constraint adaptation, VPN/tunnel
  provider selection, adaptation planning, secrets provisioning, and verified deployment.
---

# Homelab Interactive Onboarding & Adaptation Runbook

This skill guides an agent and homelab developer through instantiating, customizing, and deploying a fresh homelab environment from this repository.

## When to Use This Skill
- Initial setup on a newly cloned repository or bare-metal host.
- Establishing project direction when orienting a new user.
- Re-architecting an existing deployment to fit different hardware, storage, or VPN provider constraints.

## Prerequisites
- Working directory is the repository root (`/opt/<user>/dockge/stacks` or local clone).
- Docker and Docker Compose v2+ installed on host.
- Reference supporting guides:
  - [Service Selection Matrix](./references/service-matrix.md)
  - [Hardware & Platform Adaptations](./references/hardware-platforms.md)
  - [VPN & Provider Adapters](./references/provider-adapters.md)

---

## Onboarding Procedure

### Step 1: Project & Architectural Briefing
Orient the developer to the core architectural invariants of this repository:
1. **Dockge Stack Layout**: Exactly one directory per stack at the repository root containing `compose.yml` and an optional `.env`. Orchestrator and service configurations live in `.configs/<service>/`.
2. **Network Model**:
   - Backend services run isolated on the `homelab` bridge network (`192.168.255.0/24`).
   - Caddy bridges the LAN (`external_npm` macvlan) and `homelab` network to terminate wildcard TLS and route subdomains (`*.kamaka.tech`).
   - Host ports are commented out by default, preserving emergency direct fallbacks (`dockge` `8010:5001`, `jellyfin` `8022:7359/udp`).
3. **Environment & Secrets Architecture**:
   - Single Source of Truth: All runtime defaults are declared once in root and stack `.env.example` templates.
   - Compose files enforce required assertions: `${VAR:?See env.example for default.}`.
   - `./homelab.sh setup` syncs global variables into child stacks and auto-generates cryptographic keys (`SECRET_KEY`).

---

### Step 2: Needs Assessment & Service Selection Matrix
Engage the user interactively (e.g. via `ask_question`) to establish what workloads they intend to run:

1. **Media & Streaming**:
   - *Jellyfin*: Local media server.
   - *Seerr*: User-friendly media request management.
   - *Radarr / Sonarr / Prowlarr / FlareSolverr*: Automated movie and TV indexing and downloading.
2. **Privacy, Torrents & Remote Egress**:
   - *qbittorrentvpn*: BitTorrent client routed through WireGuard killswitch.
   - *vpn-bridge*: Dedicated mobile phone / laptop travel exit node over Tailscale.
3. **Home Management & Productivity**:
   - *Tandoor Recipes & PostgreSQL*: Self-hosted recipe management and relational database.
4. **Infrastructure & Dashboards**:
   - *Homepage Dashboard*: Unified system status board.
   - *Tailscale*: Subnet router for secure remote LAN access.
   - *Cloudflare Tunnel (`cloudflared`)*: Secure zero-open-port external ingress.

Classify all services into:
- **Keep (Immediate)**: Included in the initial deployment.
- **Defer**: Retain configuration files, but tag directory with `.disabled` to omit from boot orchestration and smoke test assertions.
- **Remove**: Completely purge stack directory, remove associated Caddy proxy labels, and remove Homepage widgets.

---

### Step 3: Hardware, Platform & Provider Discovery

#### 1. Hardware & Storage Topology Discovery
Inspect host block devices, storage mounts, and memory:
```bash
lsblk
df -h
free -m
```
- **Single-Volume Topology (`/volume1`)**:
  Set `DOCKER_DATA_DIR=/volume1/docker` and `MEDIA_DIR=/volume1/media` in root `.env`. Enforce Btrfs No-CoW (`+C`) on database and incomplete download directories.
- **Dual-Tier Topology (`/volume2` SSD + `/volume1` HDD)**:
  Set `DOCKER_DATA_DIR=/volume2/docker` (high-IOPS random transactions) and `MEDIA_DIR=/volume1/media` (bulk sequential media).
- **RAM Sizing**:
  - >= 16GB RAM: Configure 4GB transcode `tmpfs` in `jellyfin/compose.yml`.
  - 8GB RAM: Configure 2GB transcode `tmpfs`.
  - < 8GB RAM: Omit `tmpfs` and use physical disk transcode cache.

#### 2. Platform & Host Appliance OS Adaptation
Detect host environment:
- **UGREEN NAS (UGOS)**:
  - Check `/etc/profile.d/go.sh` and `/etc/systemd/system.conf` for `GODEBUG=tlskyber=0`. Ensure it is commented out.
  - Check download directories for proprietary `system.ugacl_self` extended attributes and strip them.
  - Enforce `chmod 775` on `/volume2/docker/qbittorrentvpn/data/incomplete`.
- **Synology DSM**:
  - Verify `/dev/net/tun` permissions for Tailscale.
  - Verify no collisions on port 5000/5001.
- **Generic Linux / UnRAID**:
  - Check render group GID (`stat -c '%g' /dev/dri/renderD128`) and align `group_add` in `jellyfin/compose.yml`.

#### 3. VPN Provider & Ingress Provider Selection
- **VPN Selection**:
  - *PIA*: Use native `thrnz/docker-wireguard-pia` with NextGen dynamic port forwarding callback (`set-qbt-port.sh`).
  - *ProtonVPN / Mullvad / AirVPN*: Switch VPN client image to `ghcr.io/qdm12/gluetun` and adapt port forward hooks (see [VPN Adapters](./references/provider-adapters.md)).
- **Ingress Selection**:
  - *Cloudflare Zero Trust Tunnel*: Standard outbound tunnel with token.
  - *Tailscale Only*: Disable `cloudflared` stack, rely on private tailnet access.
  - *Direct Port Forwarding*: Expose Caddy ports 80/443 on host router.

---

### Step 4: Author the Adaptation Plan Artifact
Before executing destructive file deletions or provisioning secrets, document the agreed-upon design in `.agents/artifacts/plan_<instance-name>.md`:
1. Chosen service selection (Keep, Defer, Remove).
2. Hardware storage paths (`DOCKER_DATA_DIR`, `MEDIA_DIR`).
3. Appliance workarounds and GPU render node mappings.
4. Provider credentials required.
5. Review the plan with the user and obtain confirmation before modifying state.

---

### Step 5: Execution & Stack Scaffolding
1. **Prune Unwanted Stacks**:
   ```bash
   rm -rf <pruned-stack>/
   ```
2. **Disable Deferred Stacks**:
   ```bash
   touch <deferred-stack>/.disabled
   ```
3. **Configure Root `.env`**:
   Copy `.env.example` to `.env` and populate:
   - `DOCKER_DATA_DIR`
   - `MEDIA_DIR`
   - `PUID` and `PGID`
   - `TZ`
   - `EXTERNAL_NPM_*` (LAN subnet, gateway, parent interface)
   - `NPM_IPV4_ADDRESS`
   - `TAILSCALE_IPV4_ADDRESS`
4. **Provision Stack Secrets**:
   Guide developer to populate required external secrets in `<stack>/.env.example` or `<stack>/.env`:
   - VPN credentials (`VPN_USER`, `VPN_PASS`).
   - Cloudflare Tunnel token (`CLOUDFLARE_TUNNEL_TOKEN`).
   - Leave `SECRET_KEY` blank to auto-generate.
5. **Run Setup Automation**:
   ```bash
   ./homelab.sh setup
   ```
   * Automation propagates global variables, auto-generates keys, applies host OS fixes, and creates external Docker networks.

---

### Step 6: Verified Deployment & Adaptive Test Loop
1. **Start Services in Dependency Order**:
   ```bash
   ./homelab.sh startup
   ```
2. **Execute Full Automated Test Suite**:
   ```bash
   ./homelab.sh test all
   ```
   * Dynamic stack discovery automatically marks omitted or disabled stacks as `[SKIP]` (`exit 77`).
   * Assert 100% PASS across all active services.
3. **Post-Deployment Verification**:
   - Access Homepage dashboard at `https://homepage.<domain>`.
   - Access services over HTTPS at `https://<service>.<domain>`.
   - Confirm active torrent connections and WireGuard IP egress.
