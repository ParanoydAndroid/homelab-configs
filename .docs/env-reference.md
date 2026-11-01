# Environment Variable Reference & Cheat Sheet

This document serves as the central dictionary and reference guide for every environment variable used across the homelab infrastructure.

Configuration follows a two-tier model with explicit runtime assertions:
1. **Global Root Variables ([`.env.example`](file:///home/brandon/services/.env.example))**: Define host paths, network interfaces, runtime IDs, and timezone. Automatically propagated into child stack `.env` files by `./homelab.sh setup`.
2. **Per-Stack Variables & Secrets ([`<stack>/.env.example`](file:///home/brandon/services/))**: Define application secrets, credentials, and API keys.

### Single Source of Truth & Required Variable Enforcement
- **Default Value Single Source of Truth**: All runtime variable defaults are defined strictly in `.env.example` templates.
- **Compose Assertion Syntax**: Docker Compose files (`compose.yml`) treat runtime variables as required using `${VAR:?VAR is required (see .env.example for defaults)}`. This guarantees that missing variables are caught immediately at deploy time without duplicating default values across multiple Compose files.
- **Fixed Invariants**: Variables representing immutable architectural decisions (such as `HOMEPAGE_ALLOWED_HOSTS`, `LOG_LEVEL`, `TS_EXTRA_ARGS`, and `CAPTCHA_SOLVER`) are inlined directly as literal values in `compose.yml` and omitted from `.env.example`.
- **Automatic Secret Generation**: Cryptographic secrets like Django `SECRET_KEY` are automatically generated from `/dev/urandom` during `./homelab.sh setup` if left blank.

---

## 1. Global Settings (Root `.env`)

These variables are defined in the repository root `.env` and synced automatically across all stack `.env` files and `${DOCKGE_DIR}/.env`:

### `DOCKER_DATA_DIR`
* **Default**: `/volume2/docker`
* **Type**: Filesystem Path
* **Description**: Root host directory on high-speed NVMe storage for persistent container data, application configurations, SQLite databases, and caches.
* **Reference**: [Storage Tiering](file:///home/brandon/services/.docs/project-organization.md#3-storage-tiering-architecture)

### `MEDIA_DIR`
* **Default**: `/volume1/media`
* **Type**: Filesystem Path
* **Description**: Root host directory on mechanical RAID 5 storage for bulk media libraries (`movies`, `tv`, `downloads`, `music`).

### `DOCKGE_DIR`
* **Default**: `/opt/${USER}/dockge`
* **Type**: Filesystem Path
* **Description**: Host directory where Dockge's own `compose.yml` and `.env` reside (one level above stacks).
* **Reference**: [Dockge Service Entry](file:///home/brandon/services/.docs/service-catalog.md#dockge)

### `DOCKGE_STACKS_DIR`
* **Default**: `/opt/${USER}/dockge/stacks`
* **Type**: Filesystem Path
* **Description**: Host directory where version-controlled Compose stack subdirectories reside (symlinked to `~/services`).

### `PUID`
* **Default**: `1000`
* **Type**: Linux User ID
* **Description**: Non-root user ID assigned to application containers (`brandon` on UGREEN NAS). Prevents container processes from running as root on the host.

### `PGID`
* **Default**: `100`
* **Type**: Linux Group ID
* **Description**: Non-root primary group ID assigned to application containers (`users` / `admin` on UGREEN NAS).

### `TZ`
* **Default**: `America/New_York`
* **Type**: Olson Timezone String
* **Description**: Standard timezone passed to all containers for synchronized timestamps, logs, and scheduled tasks.

### `EXTERNAL_NPM_PARENT`
* **Default**: `eth0`
* **Type**: Network Interface Name
* **Description**: Physical host network interface on the NAS used as the parent binding for the `external_npm` macvlan network.

### `EXTERNAL_NPM_SUBNET`
* **Default**: `192.168.0.0/24`
* **Type**: IPv4 CIDR Block
* **Description**: Physical LAN subnet CIDR block.

### `EXTERNAL_NPM_GATEWAY`
* **Default**: `192.168.0.1`
* **Type**: IPv4 Address
* **Description**: Physical LAN default gateway router IPv4 address.

### `NPM_IPV4_ADDRESS`
* **Default**: `192.168.0.4`
* **Type**: Static IPv4 Address
* **Description**: Dedicated static LAN IP assigned to Nginx Proxy Manager on the `external_npm` macvlan network (`turing.home`).

### `TAILSCALE_IPV4_ADDRESS`
* **Default**: `192.168.0.5`
* **Type**: Static IPv4 Address
* **Description**: Dedicated static LAN IP assigned to the Tailscale Subnet Router on the `external_npm` macvlan network (`homelab`).

---

## 2. Per-Service Variables & Secrets

These variables are defined in each `<stack>/.env.example` template and populated in untracked `<stack>/.env` files.

### `cloudflared` Stack
*See [Cloudflare Tunnel Service Entry](file:///home/brandon/services/.docs/service-catalog.md#cloudflare-tunnel-cloudflared).*

* **`CLOUDFLARE_TUNNEL_TOKEN`**  
  *Default*: None (Required Secret)  
  *Description*: Base64 authentication token generated in Cloudflare Zero Trust Dashboard (**Networks -> Tunnels -> homelab-media**).

---

### `tailscale` Stack
*See [Tailscale Router Service Entry](file:///home/brandon/services/.docs/service-catalog.md#tailscale-router).*

* **`TS_AUTHKEY`**  
  *Default*: None (Required Secret)  
  *Description*: Reusable pre-authentication key generated in Tailscale Admin Console (**Settings -> Keys**).
* **`TS_HOSTNAME`**  
  *Default*: `homelab`  
  *Description*: Node name advertised to the Tailscale mesh overlay.
* **`TS_ROUTES`**  
  *Default*: `192.168.0.0/24`  
  *Description*: LAN subnet route advertised to the mesh network.
* **`TS_EXTRA_ARGS`**  
  *Default*: `--snat-subnet-routes=true --accept-dns=false`  
  *Description*: Extra CLI flags enabling SNAT masquerading and preserving container-local DNS resolution.

---

### `vpn-bridge` Stack
*See [VPN Bridge Service Entry](file:///home/brandon/services/.docs/service-catalog.md#vpn-bridge-tailscale-exit-node-via-pia-wireguard).*

* **`VPN_USER`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account username (`pXXXXXXX`).
* **`VPN_PASS`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account password.
* **`TS_AUTHKEY`**  
  *Default*: None (Required Secret)  
  *Description*: One-time or reusable pre-authentication key generated in Tailscale Admin Console (**Settings -> Keys**) with Exit Node permissions.
* **`PIA_REGION`**  
  *Default*: `us_east,us_chicago,us_nyc`  
  *Description*: Comma-separated list of PIA US server regions for exit node egress.

---

### `qbittorrentvpn` Stack
*See [WireGuard PIA & qBittorrent Service Entry](file:///home/brandon/services/.docs/service-catalog.md#wireguard-pia-vpn--qbittorrent).*

* **`VPN_USER`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account username (`pXXXXXXX`).
* **`VPN_PASS`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account password.
* **`QBITTORRENT_PASSWORD`**  
  *Default*: None (Required Secret)  
  *Description*: WebUI administrator password for qBittorrent.
* **`LOC`**  
  *Default*: `ca_ontario,ca_toronto,ca_montreal`  
  *Description*: Comma-separated list of PIA regions supporting NextGen dynamic port forwarding.
* **`LOCAL_NETWORK`**  
  *Default*: `192.168.0.0/16`  
  *Description*: LAN and Docker subnets permitted to reach the WebUI without traversing the WireGuard tunnel.
* **`PORT_FORWARDING`**  
  *Default*: `1`  
  *Description*: Enables automated dynamic port forward requests from PIA.
* **`PORT_PERSIST`**  
  *Default*: `1`  
  *Description*: Persists signature tokens in `/pia/portsig.json` across container restarts.
* **`PORT_SCRIPT`**  
  *Default*: `/set-qbt-port.sh`  
  *Description*: Callback script executed upon port assignment to update qBittorrent via WebUI API.

---

### `jellyfin` Stack
*See [Jellyfin Service Entry](file:///home/brandon/services/.docs/service-catalog.md#jellyfin).*

* **`JELLYFIN_API_KEY`**  
  *Default*: None (Tracked Secret)  
  *Description*: API token generated in Jellyfin Dashboard (**Administration -> API Keys**). Used by Homepage to poll live stream metrics.

---

### `sonarr-radarr` Stack
*See [Radarr](file:///home/brandon/services/.docs/service-catalog.md#radarr), [Sonarr](file:///home/brandon/services/.docs/service-catalog.md#sonarr), and [Prowlarr](file:///home/brandon/services/.docs/service-catalog.md#prowlarr).*

* **`RADARR_API_KEY`**  
  *Default*: None (Deterministic Secret)  
  *Description*: 32-character REST API token for Radarr service integrations and Homepage widgets.
* **`SONARR_API_KEY`**  
  *Default*: None (Deterministic Secret)  
  *Description*: 32-character REST API token for Sonarr service integrations and Homepage widgets.
* **`PROWLARR_API_KEY`**  
  *Default*: None (Deterministic Secret)  
  *Description*: 32-character REST API token for Prowlarr indexer synchronization.

---

### `seerr` Stack
*See [Seerr Service Entry](file:///home/brandon/services/.docs/service-catalog.md#seerr).*

* **`SEERR_API_KEY`**  
  *Default*: None (Deterministic Secret)  
  *Description*: 32-character REST API token for Seerr request management and media monitoring.

---

### `tandoor` Stack
*See [Tandoor Recipes Service Entry](file:///home/brandon/services/.docs/service-catalog.md#tandoor-recipes).*

* **`SECRET_KEY`**  
  *Default*: None (Required Cryptographic Secret)  
  *Description*: Django cryptographic signing key (generate via `base64 /dev/urandom | head -c50`).
* **`POSTGRES_DB`**  
  *Default*: `recipes`  
  *Description*: Database name in PostgreSQL.
* **`POSTGRES_USER`**  
  *Default*: `djangouser`  
  *Description*: PostgreSQL database username.
* **`POSTGRES_PASSWORD`**  
  *Default*: `recipes_password`  
  *Description*: PostgreSQL database password.

---

### `homepage` Stack
*See [Homepage Service Entry](file:///home/brandon/services/.docs/service-catalog.md#homepage).*

* **`HOMEPAGE_VAR_PIHOLE_KEY`**  
  *Default*: None (Tracked Secret)  
  *Description*: Pi-hole administrative Web password or API token used by Homepage to query local DNS metrics.

---

### `postgres` Stack
*See [PostgreSQL Service Entry](file:///home/brandon/services/.docs/service-catalog.md#postgresql).*

* **`POSTGRES_DB`**  
  *Default*: `postgres`  
  *Description*: Default maintenance database name.
* **`POSTGRES_USER`**  
  *Default*: `postgres`  
  *Description*: PostgreSQL superuser username.
* **`POSTGRES_PASSWORD`**  
  *Default*: `postgres`  
  *Description*: Superuser password (isolated to internal `homelab` Docker bridge).

---

### `nginx` Stack
*See [NPM Service Entry](file:///home/brandon/services/.docs/service-catalog.md#nginx-proxy-manager-npm).*

* **`DISABLE_IPV6`**  
  *Default*: `"true"`  
  *Description*: Forces Nginx Proxy Manager to listen on IPv4 only.
* **`DB_SQLITE_FILE`**  
  *Default*: `/data/db.sqlite`  
  *Description*: Path to NPM SQLite database inside container.

---

## 3. Homepage Dashboard Secret Interpolation

Homepage widgets consume service secrets without committing plaintext credentials to version control:

1. **Docker Container Labels (Internal Containers)**:
   Containers (`jellyfin`, `qbittorrentvpn`, `sonarr-radarr`) declare widget configuration using `${VAR}` syntax in their `compose.yml`:
   ```yaml
   labels:
     - homepage.group=Media
     - homepage.name=Jellyfin
     - homepage.widget.type=jellyfin
     - homepage.widget.url=http://jellyfin:8096
     - homepage.widget.key=${JELLYFIN_API_KEY}
   ```
   Docker Compose reads each stack's `.env` and interpolates the API key into container metadata. Homepage reads the resolved key via `/var/run/docker.sock` and polls the service across the `homelab` bridge.
2. **Static Environment Substitution (`HOMEPAGE_VAR_*` for External Appliances)**:
   Non-containerized appliances (like Pi-hole on `192.168.0.2`) are declared in [.configs/homepage/services.yaml](file:///home/brandon/services/.configs/homepage/services.yaml). Homepage natively interpolates `{{HOMEPAGE_VAR_<NAME>}}` placeholders with matching environment variables declared in `homepage/compose.yml`.
