# Architectural Implementation Plan: Homelab Service Updates (Mealie & Caddy Ingress)

## 1. Executive Summary & Objective

This plan coordinates the deployment of **Mealie** and an overhaul of homelab **Ingress from Nginx Proxy Manager to Caddy Docker Proxy**, establishing a clean two-domain architecture with 100% automated public Let's Encrypt wildcard certificates via Cloudflare DNS-01:
* **Internal Homelab Domain (`*.kamaka.tech`)**: All private internal services (`jellyfin`, `mealie`, `recipes`, `radarr`, `sonarr`, `prowlarr`, `torrent`, `dockge`, `homepage`, `flaresolverr`, `nas`). Resolves strictly to `192.168.0.4` on LAN/Tailscale with zero public routing.
* **Public Ingress Domain (`*.kamakakai.com`)**: Strictly public-facing services (`jellyfin.kamakakai.com`, `recipes.kamakakai.com` / `mealie.kamakakai.com`) routed through Cloudflare Tunnel.
* **ACME Admin Email Alignment**: ACME account registration and alerts updated to use `admin@kamakakai.com` (under the public domain), forwarded to `bkamaka@gmail.com` via Cloudflare Email Routing.
* **Co-Located Docker Build Context**: Caddy multi-stage `Dockerfile` is placed directly alongside `compose.yml` at `ingress/Dockerfile` for idiomatic `build: .` ergonomics in both CLI and Dockge UI.
* **Automated Pi-hole v6 Orchestration**: Leverages verified passwordless SSH access to `brandon@192.168.0.2` to natively configure Pi-hole FTL v6 wildcard resolution and clean up stale `.turing.home` records with zero manual DNS editing.
* **Preserved Invariants**:
  - `postgresql` remains `postgres:16-alpine` (no modifications).
  - `jellyfin` remains upstream `jellyfin/jellyfin:latest`.
  - `*arr` applications remain `lscr.io/linuxserver/*`.
  - VPN & torrent clients remain `thrnz/docker-wireguard-pia:latest`.

---

## 2. Component Design & Touchpoints

### 2.1 Scope A: Mealie Service Deployment
- **Stack**: [productivity/compose.yml](file:///opt/brandon/dockge/stacks/productivity/compose.yml)
- **Container**: `ghcr.io/mealie-recipes/mealie:latest`
  - Container name: `mealie`
  - Hostname: `mealie`
  - Network: `homelab`
  - Internal Port: `9000`
  - Permissions: `PUID: ${PUID}`, `PGID: ${PGID}`
  - Storage: `${DOCKER_DATA_DIR}/mealie/data:/app/data` (Btrfs NVMe under `/volume2/docker/mealie/data`)
  - Database: Native embedded SQLite (`/app/data/mealie.sqlite`). Zero coupling to PostgreSQL.
  - Environment:
    - `ALLOW_SIGNUP: "true"` (temporary for admin registration)
    - `BASE_URL: https://mealie.kamaka.tech`
    - `MAX_WORKERS: 1`
    - `WEB_CONCURRENCY: 1`
- **Dashboard & Routing**:
  - Internal URL: `https://mealie.kamaka.tech`
  - Optional Public URL: `https://mealie.kamakakai.com`
  - Homepage widget added under `Productivity` in [dashboard/compose.yml](file:///opt/brandon/dockge/stacks/dashboard/compose.yml).

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
- **Execution Mechanism**:
  - Export full recipe models, steps, ingredients, and images from Tandoor using Django management serialization into `/tmp/tandoor_export.zip`.
  - Import the bundle into Mealie via its native Tandoor migration endpoint (**Settings $\rightarrow$ Data Management $\rightarrow$ Migrations**).
  - Verify all 9 recipes, ingredient lists, steps, and photos appear intact in Mealie.

### 2.3 Scope C: Ingress Migration (NPM $\rightarrow$ Caddy Docker Proxy)
- **Image & Build (`ingress/Dockerfile`)**:
  - Author `ingress/Dockerfile` using multi-stage `caddy:2-builder`:
    ```dockerfile
    FROM caddy:2-builder AS builder
    RUN xcaddy build \
        --with github.com/caddy-dns/cloudflare \
        --with github.com/lucaslorentz/caddy-docker-proxy/v2
    FROM caddy:2-alpine
    COPY --from=builder /usr/bin/caddy /usr/bin/caddy
    CMD ["caddy", "docker-proxy"]
    ```
  - In [ingress/compose.yml](file:///opt/brandon/dockge/stacks/ingress/compose.yml):
    ```yaml
    services:
      caddy:
        build: .
        image: homelab-caddy:latest
        container_name: caddy
        hostname: caddy
        restart: unless-stopped
        ...
    ```
- **Base Caddyfile (`.configs/caddy/Caddyfile` deployed to `${DOCKER_DATA_DIR}/caddy/Caddyfile`)**:
  Defines global settings with public admin email and external non-container host routes:
  ```caddy
  {
      email admin@kamakakai.com
  }

  (cloudflare_tls) {
      tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      }
  }

  # Physical NAS host portal (UGOS) running on host gateway:
  nas.kamaka.tech {
      import cloudflare_tls
      reverse_proxy https://192.168.255.1:9443 {
          transport http {
              tls_insecure_skip_verify
          }
      }
  }
  ```
- **Network & IP Preservation**:
  - Caddy attaches to `external_npm` (macvlan) with static IP `${NPM_IPV4_ADDRESS}` (`192.168.0.4`) and MAC `2E:50:8F:7A:C4:12`.
  - Caddy attaches to `homelab` (`192.168.255.0/24`) with alias `services`.
  - Mounts `/var/run/docker.sock:ro` to discover Compose service labels.
  - Persistent volumes:
    - `${DOCKER_DATA_DIR}/caddy/data:/data`
    - `${DOCKER_DATA_DIR}/caddy/config:/config`
    - `${DOCKER_DATA_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro`
- **Automated TLS Lifecycle via Cloudflare DNS-01**:
  - Uses `CLOUDFLARE_API_TOKEN` to automatically provision and renew genuine Let's Encrypt wildcard certificates for:
    1. `*.kamaka.tech` (internal homelab services)
    2. `*.kamakakai.com` (public services)
  - Eliminates the need to maintain or install any custom root Certificate Authority (`turing.crt`) on client phones, laptops, or browsers.
- **Service Stack Label Standardization**:
  - Update labels across Compose stacks:
    - `jellyfin`: `caddy: jellyfin.kamaka.tech, jellyfin.kamakakai.com`, `caddy.reverse_proxy: "{{upstreams 8096}}"`
    - `mealie`: `caddy: mealie.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 9000}}"`
    - `tandoor`: `caddy: recipes.kamaka.tech, recipes.kamakakai.com`, `caddy.reverse_proxy: "{{upstreams 8050}}"`
    - `radarr`: `caddy: radarr.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 7878}}"`
    - `sonarr`: `caddy: sonarr.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 8989}}"`
    - `prowlarr`: `caddy: prowlarr.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 9696}}"`
    - `flaresolverr`: `caddy: flaresolverr.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 8191}}"`
    - `torrent`: `caddy: torrent.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 8081}}"`
    - `dockge`: `caddy: dockge.kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 5001}}"`
    - `homepage`: `caddy: homepage.kamaka.tech, kamaka.tech`, `caddy.reverse_proxy: "{{upstreams 3000}}"`
- **Decommission NPM**:
  - Stop and remove container `nginx`.
  - Back up `/volume2/docker/nginx/data/db.sqlite`.
  - Preserve `cloudflared` in [ingress/compose.yml](file:///opt/brandon/dockge/stacks/ingress/compose.yml).

### 2.4 Scope D: Automated Pi-hole v6 DNS Orchestration (Over SSH)
- Target: `brandon@192.168.0.2` (Pi-hole FTL v6.8, passwordless sudo verified).
- **Wildcard Injection**:
  Execute via SSH:
  ```bash
  sudo pihole-FTL --config misc.dnsmasq_lines '["address=/kamaka.tech/192.168.0.4"]'
  ```
  This immediately enables native `*.kamaka.tech` wildcard resolution to `192.168.0.4` without breaking Pi-hole v6 defaults.
- **Verification**: Query `dig @192.168.0.2 mealie.kamaka.tech +short` $\rightarrow$ returns `192.168.0.4`.
- **Cleanup (Post-Migration)**:
  Once all services are verified under `kamaka.tech`, execute an automated script over SSH to remove the 16 legacy `*.turing.home` CNAME records from `cnameRecords` in `/etc/pihole/pihole.toml`.

---

## 3. Phased Manual Administrator Checklist

### Phase 1: Pre-Cutover External Preparation (Cloudflare & Tailscale)
1. **Cloudflare Dashboard (`kamaka.tech`)**:
   - Navigate to **DNS $\rightarrow$ Records**.
   - **Delete or disable the wildcard tunnel record**: If you have a CNAME `*.kamaka.tech` pointing to your tunnel (`<uuid>.cfargotunnel.com`), delete it. This guarantees internal-only services (`radarr`, `dockge`, etc.) cannot be reached from the public internet.
2. **Cloudflare Email Routing (`kamakakai.com`)**:
   - In Cloudflare Dashboard $\rightarrow$ `kamakakai.com` $\rightarrow$ **Email $\rightarrow$ Email Routing**:
   - Ensure destination address `bkamaka@gmail.com` is verified.
   - Configure custom routing rule: `admin@kamakakai.com` $\rightarrow$ forwards to `bkamaka@gmail.com`.
   - (Ensures all ACME certificate renewal alerts and service notifications reach your inbox).
3. **Cloudflare Zero Trust Dashboard (`kamakakai.com`)**:
   - Under **Access $\rightarrow$ Tunnels $\rightarrow$ Your Tunnel $\rightarrow$ Public Hostnames**:
   - Ensure the specific public services you want exposed are declared:
     - `jellyfin.kamakakai.com` $\rightarrow$ `https://192.168.0.4:443` (or `http://jellyfin:8096`)
     - `recipes.kamakakai.com` $\rightarrow$ `https://192.168.0.4:443` (or `http://tandoor:8050`)
     - Optional: `mealie.kamakakai.com` $\rightarrow$ `https://192.168.0.4:443`
4. **Tailscale Admin Console**:
   - Navigate to **DNS $\rightarrow$ Nameservers**.
   - Verify `192.168.0.2` (Pi-hole) is configured as the **Global Nameserver**.
   - Check **Override local DNS** (ensures all mobile queries flow to Pi-hole, eliminating DNS leaks when using your VPN exit node).
   - Ensure **Restrict to search domain** is disabled/empty so all domains resolve through Pi-hole.

### Phase 2: Post-Deployment Verification & Admin First Login
1. **Mealie First Login**:
   - Open browser to `https://mealie.kamaka.tech`.
   - Complete initial administrator registration.
2. **Recipe Migration**:
   - In Mealie: Navigate to **Settings $\rightarrow$ Data Management $\rightarrow$ Migrations $\rightarrow$ Tandoor**.
   - Upload the staged `/tmp/tandoor_export.zip` file.
   - Confirm all 9 recipes appear in Mealie.
3. **Certificate Trust Verification**:
   - Test `https://jellyfin.kamaka.tech` and `https://mealie.kamaka.tech` from mobile phone and desktop.
   - Confirm valid Let's Encrypt certificate with zero warnings and without any custom root certificate installed.

---

## 4. Automated Testing & Verification Plan

1. **Static Analysis**: `bash -n` on all modified scripts.
2. **DNS Resolution Check**: Verify `dig @192.168.0.2 mealie.kamaka.tech +short` returns `192.168.0.4`.
3. **Container Runtime (`test_containers.sh`)**:
   - Assert `mealie` container running and healthy.
   - Assert `caddy` container running and healthy on `192.168.0.4`.
4. **Routing Suite (`test_routing.sh`)**:
   - Update assertions for `*.kamaka.tech` virtual hosts:
     - `https://mealie.kamaka.tech` $\rightarrow$ HTTP 200.
     - `https://recipes.kamaka.tech` $\rightarrow$ HTTP 200.
     - `https://jellyfin.kamaka.tech` $\rightarrow$ HTTP 200.
     - `https://radarr.kamaka.tech` $\rightarrow$ HTTP 200.
     - `https://nas.kamaka.tech` $\rightarrow$ HTTP 200/302.
     - All other internal services return HTTP 200/302.
   - Verify public vhost `https://jellyfin.kamakakai.com` routing.
   - Validate SSL certificate issuer is Let's Encrypt.
