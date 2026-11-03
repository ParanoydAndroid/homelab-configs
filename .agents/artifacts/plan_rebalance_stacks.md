# Architectural Plan: Homelab Stack Rebalancing (11 to 6 Semantic Domains)

## 1. Problem Statement & Objectives

The homelab currently operates across 11 separate Docker Compose stacks at the repository root:
`cloudflared`, `homepage`, `jellyfin`, `nginx`, `postgres`, `qbittorrentvpn`, `seerr`, `sonarr-radarr`, `tailscale`, `tandoor`, and `vpn-bridge`.

### Identified Defects & Friction:
1. **Semantic Fragmentation**:
   - `sonarr-radarr/` contains four services (`sonarr`, `radarr`, `prowlarr`, `flaresolverr`), making its name an inaccurate subset.
   - `seerr/` is an isolated 1-service stack despite being tightly coupled with `sonarr`, `radarr`, and `jellyfin`.
   - `postgres/` is split into its own stack solely to back `tandoor/`, introducing boot race conditions and container naming skew (`postgresql` vs `postgres`).
   - `nginx/` (LAN proxy) and `cloudflared/` (WAN tunnel) are split into separate 1-service stacks despite both terminating ingress on the `homelab` bridge.
   - `tailscale/` (subnet router) and `vpn-bridge/` (Tailscale exit node via WireGuard PIA) are split, requiring redundant mesh management.
2. **Environment Variable & Secret Maintenance Overhead**:
   - 11 stacks require maintaining 11 `.env` files.
   - Global variables (`PUID`, `PGID`, `TZ`, `DOCKER_DATA_DIR`, `MEDIA_DIR`, etc.) are duplicated across 11 files.
3. **Dockge UI Clutter**:
   - 11 cards displayed in Dockge, with many cards representing isolated single containers.

### Core Objectives:
- Rebalance into **6 cohesive, domain-aligned stacks**: `ingress`, `mesh`, `media`, `torrent`, `productivity`, `dashboard`.
- Reduce `.env` files from 11 down to 6, grouping related application API keys together.
- Retain dedicated, per-stack VPN credentials in `torrent` and `mesh` to allow distinct VPN providers, regions, or accounts.
- Co-locate PostgreSQL with Tandoor using native Compose `depends_on: condition: service_healthy`.
- Preserve 100% of persistent volume paths under `${DOCKER_DATA_DIR}/<service>/data` and `${MEDIA_DIR}` (zero data migration, full Restic snapshot compatibility).
- Maintain 100% pass rate across the 57 automated smoke and regression tests.

---

## 2. Target Architecture (6 Semantic Stacks)

```
stacks/
├── ingress/
│   ├── compose.yml       # nginx + cloudflared
│   └── .env.example      # CLOUDFLARE_TUNNEL_TOKEN
├── mesh/
│   ├── compose.yml       # tailscale (subnet router) + vpn-bridge (PIA + Tailscale exit node)
│   └── .env.example      # VPN_USER, VPN_PASS, PIA_REGION, TS_AUTHKEY
├── media/
│   ├── compose.yml       # jellyfin, seerr, sonarr, radarr, prowlarr, flaresolverr
│   └── .env.example      # JELLYFIN_API_KEY, SEERR_API_KEY, SONARR_API_KEY, RADARR_API_KEY, PROWLARR_API_KEY
├── torrent/
│   ├── compose.yml       # wireguard-pia + qbittorrent (isolated network namespace)
│   └── .env.example      # VPN_USER, VPN_PASS, PIA_REGION, QBITTORRENT_PASSWORD
├── productivity/
│   ├── compose.yml       # postgresql + tandoor (native depends_on healthcheck)
│   └── .env.example      # SECRET_KEY
└── dashboard/
    ├── compose.yml       # homepage
    └── .env.example      # HOMEPAGE_VAR_PIHOLE_KEY
```

---

## 3. Detailed Stack Specifications

### 1. `ingress/`
- **Services**:
  - `nginx`: Ingress reverse proxy and SSL termination point. Dual-homed on `external_npm` (`${NPM_IPV4_ADDRESS}`) and `homelab`.
  - `cloudflared`: Zero Trust CGNAT outbound tunnel on `homelab`.
- **Environment**:
  - Stack secret: `CLOUDFLARE_TUNNEL_TOKEN`.
  - Synced globals: `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`, `TZ`, `DOCKER_DATA_DIR`.

### 2. `mesh/`
- **Services**:
  - `tailscale`: Primary subnet router advertising `192.168.0.0/24`. Dual-homed on `external_npm` (`${TAILSCALE_IPV4_ADDRESS}`) and `homelab`.
  - `vpn`: WireGuard PIA client with killswitch on `homelab`.
  - `tailscale` (exit node): Attached to `vpn` via `network_mode: "service:vpn"`, advertising `--advertise-exit-node`.
- **Environment**:
  - Stack secrets: `VPN_USER`, `VPN_PASS`, `PIA_REGION`, `TS_AUTHKEY`.
  - Synced globals: `TAILSCALE_IPV4_ADDRESS`, `DOCKER_DATA_DIR`.

### 3. `media/`
- **Services**:
  - `jellyfin`: Media streaming server with `/transcode` tmpfs.
  - `seerr`: Media discovery and requests.
  - `sonarr`: TV automation.
  - `radarr`: Movie automation.
  - `prowlarr`: Indexer manager.
  - `flaresolverr`: Cloudflare solver.
- **Environment**:
  - Stack secrets: `JELLYFIN_API_KEY`, `SEERR_API_KEY`, `SONARR_API_KEY`, `RADARR_API_KEY`, `PROWLARR_API_KEY`.
  - Synced globals: `MEDIA_DIR`, `DOCKER_DATA_DIR`, `PUID`, `PGID`, `TZ`.

### 4. `torrent/`
- **Services**:
  - `vpn`: Dedicated WireGuard PIA client with port forwarding enabled (`PORT_FORWARDING=1`).
  - `qbittorrent`: BitTorrent client attached via `network_mode: "service:vpn"`.
- **Environment**:
  - Stack secrets: `VPN_USER`, `VPN_PASS`, `PIA_REGION`, `QBITTORRENT_PASSWORD`.
  - Synced globals: `MEDIA_DIR`, `DOCKER_DATA_DIR`, `PUID`, `PGID`, `TZ`.

### 5. `productivity/`
- **Services**:
  - `postgresql`: Database server with healthcheck (`pg_isready -U postgres -d recipes`).
  - `tandoor`: Recipe manager with `depends_on: postgresql: condition: service_healthy`.
- **Environment**:
  - Stack secret: `SECRET_KEY`.
  - Synced globals: `DOCKER_DATA_DIR`, `PUID`, `PGID`, `TZ`.

### 6. `dashboard/`
- **Services**:
  - `homepage`: Homelab dashboard with Docker socket inspection and multi-volume storage metrics (`/volume1`, `/volume2`).
- **Environment**:
  - Stack secret: `HOMEPAGE_VAR_PIHOLE_KEY`.
  - Synced globals: `DOCKER_DATA_DIR`, `MEDIA_DIR`, `PUID`, `PGID`, `TZ`.

---

## 4. Integration Touchpoints & Adaptations

1. **`.scripts/common.sh`**:
   - Update `discover_stacks()` priority ordering to: `productivity`, `ingress`, `mesh`, `dashboard`, `media`, `torrent`.
2. **`homelab.sh`**:
   - Startup sequence naturally benefits from `productivity` starting first (bringing up `postgresql`).
   - `set-qbt-port.sh` target path remains `${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh` (or symlinked for backwards compatibility).
3. **Automated Test Suite (`.tests/suites/`)**:
   - Update `is_stack_enabled` references:
     - `test_containers.sh`: map container checks to `ingress`, `mesh`, `media`, `torrent`, `productivity`, `dashboard`.
     - `test_routing.sh`: update stack guards for virtual hosts.
     - `test_interconnect.sh`: update stack guards for inter-container tests.
     - `test_negative_security.sh`: update stack guards for security tests.
     - `test_direct_admin.sh`: update stack guards for direct admin tests.
4. **Documentation**:
   - Update `README.md`, `.docs/service-catalog.md`, `.docs/networking.md`, `.docs/env-reference.md`, and `.docs/project-organization.md`.
5. **Clean Migration**:
   - Existing live containers will be cleanly stopped and recreated under their new stack directories without data loss.
   - Old stack directories removed once verified.

---

## 5. Verification Plan
1. Validate Compose syntax across all 6 stacks: `docker compose config`.
2. Execute `homelab.sh setup` to generate new stack `.env` files and verify startup.
3. Run full smoke test suite: `./homelab.sh test all` (57/57 must pass).
4. Verify Dockge UI displays exactly 6 healthy, green stacks.
