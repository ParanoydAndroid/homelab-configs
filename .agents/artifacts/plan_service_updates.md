# Architectural Implementation Plan: Homelab Service Updates (Mealie & Caddy Ingress)

## 1. Overview & Objective

This plan unifies all confirmed service updates into a single coordinated architectural transition:
1. **Deploy Mealie** (`ghcr.io/mealie-recipes/mealie:latest`) in the `productivity` stack alongside Tandoor, configured with an independent SQLite database engine.
2. **Migrate Existing Tandoor Recipes** (9 recipes) into Mealie.
3. **Overhaul Ingress (NPM $\rightarrow$ Caddy)**: Replace the imperative, UI-configured Nginx Proxy Manager (`jc21/nginx-proxy-manager`) with declarative, label-driven Caddy (`lucaslorentz/caddy-docker-proxy` compiled with `caddy-dns/cloudflare`).
4. **Preserve Explicit Invariants**:
   - `postgresql` remains on `postgres:16-alpine` (no modifications).
   - `jellyfin` remains upstream `jellyfin/jellyfin:latest`.
   - `*arr` applications remain on `lscr.io/linuxserver/*`.
   - VPN and torrent stacks remain on `thrnz/docker-wireguard-pia:latest`.

---

## 2. Component Design & Touchpoints

### 2.1 Scope A: Mealie Service Deployment
- **Stack**: `productivity/compose.yml`
- **Service Configuration**:
  - Image: `ghcr.io/mealie-recipes/mealie:latest`
  - Container name: `mealie`
  - Hostname: `mealie`
  - Network: `homelab`
  - Internal Port: `9000`
  - User permissions: `PUID: ${PUID}`, `PGID: ${PGID}`
  - Storage: `${DOCKER_DATA_DIR}/mealie/data:/app/data` (Btrfs NVMe under `/volume2/docker/mealie/data`)
  - Database: Native embedded SQLite (`/app/data/mealie.sqlite`). Zero coupling to the `postgresql` container.
  - Environment:
    - `ALLOW_SIGNUP: "true"`
    - `BASE_URL: https://mealie.turing.home`
    - `MAX_WORKERS: 1`
    - `WEB_CONCURRENCY: 1`
- **Dashboard & Exposure**:
  - Proxy endpoints: `https://mealie.turing.home` (internal) and optionally `https://mealie.kamaka.tech` (external).
  - Homepage widget: Added under `Productivity` in `dashboard/compose.yml` / Homepage configuration.

### 2.2 Scope B: Tandoor Recipe Migration
- **Current Data**: 9 recipes in Tandoor database (`cookbook_recipe`):
  1. *Chocolate Crinkle Cookies*
  2. *Caramel icing*
  3. *The Best Barbecue Beans*
  4. *Pavlovas*
  5. *All-American Beef Stew*
  6. *Rough Puff Pastry*
  7. *Classic Lemonade*
  8. *Choux Pastry*
  9. *Tarte Tatin*
- **Migration Mechanism**:
  - Export full recipe models and assets from Tandoor using Django management commands / python script.
  - Stage the exported JSON / ZIP bundle in `/tmp/tandoor_export.zip`.
  - Import into Mealie via Mealie's native migration API (`/api/admin/migrations/tandoor`) or UI importer.
  - Verify all 9 recipes appear in Mealie with ingredients, steps, and photos.

### 2.3 Scope C: Ingress Migration (NPM $\rightarrow$ Caddy Docker Proxy)
- **Problem**: NPM relies on a mutable SQLite database (`db.sqlite`) configured via web UI, causing declarative drift.
- **Solution**: Caddy with `caddy-docker-proxy` reads proxy rules directly from Docker labels on each service stack.
- **Image & Build**:
  - Author `.configs/caddy/Dockerfile` using multi-stage `caddy:2-builder`:
    ```dockerfile
    FROM caddy:2-builder AS builder
    RUN xcaddy build \
        --with github.com/caddy-dns/cloudflare \
        --with github.com/lucaslorentz/caddy-docker-proxy/v2
    FROM caddy:2-alpine
    COPY --from=builder /usr/bin/caddy /usr/bin/caddy
    CMD ["caddy", "docker-proxy"]
    ```
  - In `ingress/compose.yml`: build context `.configs/caddy` (or pre-built tagged image).
- **Network & IP Preservation**:
  - Caddy attaches to `external_npm` (macvlan) with static IP `${NPM_IPV4_ADDRESS}` (`192.168.0.4`).
  - Zero changes needed for LAN DNS records (`*.turing.home` continues resolving to `192.168.0.4`).
  - Caddy attaches to `homelab` (`192.168.255.0/24`) to reach container upstream ports.
- **SSL / TLS Certificate Management**:
  - **Internal (`*.turing.home`)**: Mount existing tracked wildcard certificate `.configs/nginx/turing.crt` and `.configs/nginx/turing.key` into `/etc/caddy/certs/`. Configure Caddy base Caddyfile snippet to serve these certificates for all `*.turing.home` hosts. Existing trusted client devices experience zero certificate errors or trust-store churn.
  - **External (`*.kamaka.tech`)**: Automated Cloudflare DNS-01 challenge using `CLOUDFLARE_API_TOKEN` via `caddy-dns/cloudflare`.
- **Declarative Labels on Services**:
  - Add Caddy labels across all stacks (`jellyfin`, `seerr`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr`, `qbittorrentvpn`, `dockge`, `homepage`, `tandoor`, `mealie`, `nas`).
- **Decommission NPM**:
  - Remove `nginx-proxy-manager` container.
  - Archive `/volume2/docker/nginx/data/db.sqlite`.
  - Preserve `cloudflared` in `ingress/compose.yml`.

---

## 3. Automated Testing & Verification Plan

1. **Service Tests (`test_containers.sh`)**:
   - Assert `mealie` container running and healthy.
   - Assert `caddy` container running and listening on `192.168.0.4:80` and `:443`.
2. **Routing Tests (`test_routing.sh`)**:
   - Verify client-impersonated HTTPS curl tests against `192.168.0.4` for all 15 virtual hosts:
     - `https://mealie.turing.home` returns HTTP 200.
     - `https://recipes.turing.home` returns HTTP 200.
     - `https://jellyfin.turing.home` returns HTTP 200.
     - All other existing vhosts return HTTP 200/302.
     - Validate TLS handshake using existing `turing.crt`.
3. **Recipe Verification**:
   - Verify Mealie SQLite DB has 9 imported recipes.

---

## 4. Potential Hazards & Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Caddy build time on host** | `xcaddy build` takes ~1-2 minutes on first run | Multi-stage Docker build caches Go modules; subsequent runs are instantaneous. |
| **Client TLS untrusted errors** | Changing CA would force reinstalling root certificates on all phones/laptops | Reuse existing `.configs/nginx/turing.crt` and `turing.key` in Caddy for all `*.turing.home` domains. |
| **Docker Socket Security** | Caddy needs Docker socket to read labels | Mount `/var/run/docker.sock:ro` strictly read-only. |
| **Mealie Port Conflict** | Port 9000 used elsewhere | Port 9000 is internal to `homelab` bridge network; no host port mapping. |
