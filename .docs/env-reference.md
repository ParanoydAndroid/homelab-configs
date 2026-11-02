# Environment Variable Reference & Cheat Sheet

This document serves as the central dictionary and reference guide for every environment variable used across the homelab infrastructure.

Configuration follows a two-tier model with explicit runtime assertions:
1. **Global Root Variables ([`.env.example`](../.env.example))**: Define host paths, network interfaces, runtime IDs, and timezone. Automatically propagated into child stack `.env` files by `./homelab.sh setup`.
2. **Per-Stack Variables & Secrets ([`<stack>/.env.example`](../))**: Define application secrets, credentials, and API keys.

### Single Source of Truth & Required Variable Enforcement
- **Default Value Single Source of Truth**: All runtime variable defaults are defined strictly in `.env.example` templates.
- **Compose Assertion Syntax**: Docker Compose files (`compose.yml`) treat runtime variables as required using `${VAR}`. This guarantees that missing variables are caught immediately at deploy time without duplicating default values across multiple Compose files.
- **Fixed Invariants**: Variables representing immutable architectural decisions (such as `HOMEPAGE_ALLOWED_HOSTS`, `LOG_LEVEL`, `TS_EXTRA_ARGS`, and `CAPTCHA_SOLVER`) are inlined directly as literal values in `compose.yml` and omitted from `.env.example`.
- **Automatic Secret Generation**: Cryptographic secrets like Django `SECRET_KEY` are automatically generated from `/dev/urandom` during `./homelab.sh setup` if left blank.

---

## 1. Global Settings (Root `.env`)

These variables are defined in the repository root `.env` and synced automatically across all stack `.env` files and `${DOCKGE_DIR}/.env`:

### `DOCKER_DATA_DIR`
* **Default**: `/volume2/docker`
* **Type**: Filesystem Path
* **Description**: Root host directory on high-speed NVMe storage for persistent container data, application configurations, SQLite databases, and caches.
* **Reference**: [Storage Tiering](./project-organization.md#3-storage-tiering-architecture)

### `MEDIA_DIR`
* **Default**: `/volume1/media`
* **Type**: Filesystem Path
* **Description**: Root host directory on mechanical RAID 5 storage for bulk media libraries (`movies`, `tv`, `downloads`, `music`).

### `DOCKGE_DIR`
* **Default**: `/opt/${USER}/dockge`
* **Type**: Filesystem Path
* **Description**: Host directory where Dockge's own `compose.yml` and `.env` reside (one level above stacks).
* **Reference**: [Dockge Service Entry](./service-catalog.md#dockge)

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

### `BACKUP_RESTIC_REPO`
* **Default**: `/volume1/backups/homelab-docker`
* **Type**: Filesystem Path
* **Description**: Local destination path for the native Restic persistent volume backup repository on RAID 5 storage.

### `BACKUP_RETENTION_DAYS`
* **Default**: `30`
* **Type**: Integer
* **Description**: Number of daily backup snapshots retained before automatic pruning during `./homelab.sh backup`.

---

## 2. Per-Service Variables & Secrets

These variables represent external credentials, cryptographic secrets, runtime selections, and API keys. They are declared in each `<stack>/.env.example` template with empty defaults and populated in untracked `<stack>/.env` files.

### `cloudflared` Stack
*See [Cloudflare Tunnel Service Entry](./service-catalog.md#cloudflare-tunnel-cloudflared).*

* **`CLOUDFLARE_TUNNEL_TOKEN`**  
  *Default*: None (Required Secret)  
  *Description*: Base64 authentication token generated in Cloudflare Zero Trust Dashboard (**Networks -> Tunnels -> homelab-media**).

---

### `homepage` Stack
*See [Homepage Service Entry](./service-catalog.md#homepage).*

* **`HOMEPAGE_VAR_PIHOLE_KEY`**  
  *Default*: None (Optional Secret)  
  *Description*: Pi-hole administrative Web password or API token used by Homepage to query local DNS metrics.

---

### `jellyfin` Stack
*See [Jellyfin Service Entry](./service-catalog.md#jellyfin).*

* **`JELLYFIN_API_KEY`**  
  *Default*: None (Optional API Secret)  
  *Description*: API token generated in Jellyfin Dashboard (**Administration -> API Keys**). Used by Homepage to poll live stream metrics.

---

### `qbittorrentvpn` Stack
*See [WireGuard PIA & qBittorrent Service Entry](./service-catalog.md#wireguard-pia-vpn--qbittorrent).*

* **`VPN_USER`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account username (`pXXXXXXX`).
* **`VPN_PASS`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account password.
* **`QBITTORRENT_PASSWORD`**  
  *Default*: None (Required Secret)  
  *Description*: WebUI administrator password for qBittorrent.

---

### `seerr` Stack
*See [Seerr Service Entry](./service-catalog.md#seerr).*

* **`SEERR_API_KEY`**  
  *Default*: None (Optional API Secret)  
  *Description*: 32-character REST API token for Seerr request management and media monitoring.

---

### `sonarr-radarr` Stack
*See [Radarr](./service-catalog.md#radarr), [Sonarr](./service-catalog.md#sonarr), and [Prowlarr](./service-catalog.md#prowlarr).*

* **`RADARR_API_KEY`**  
  *Default*: None (Deterministic API Secret)  
  *Description*: 32-character REST API token for Radarr service integrations and Homepage widgets.
* **`SONARR_API_KEY`**  
  *Default*: None (Deterministic API Secret)  
  *Description*: 32-character REST API token for Sonarr service integrations and Homepage widgets.
* **`PROWLARR_API_KEY`**  
  *Default*: None (Deterministic API Secret)  
  *Description*: 32-character REST API token for Prowlarr indexer synchronization.

---

### `tailscale` Stack
*See [Tailscale Router Service Entry](./service-catalog.md#tailscale-router).*

* **`TS_AUTHKEY`**  
  *Default*: None (Optional One-Time Secret)  
  *Description*: Reusable pre-authentication key generated in Tailscale Admin Console (**Settings -> Keys**). Optional after initial node registration.

---

### `tandoor` Stack
*See [Tandoor Recipes Service Entry](./service-catalog.md#tandoor-recipes).*

* **`SECRET_KEY`**  
  *Default*: None (Required Cryptographic Secret)  
  *Description*: Django cryptographic signing key. Automatically generated from `/dev/urandom` by `./homelab.sh setup` if left blank.

---

### `vpn-bridge` Stack
*See [VPN Bridge Service Entry](./service-catalog.md#vpn-bridge-tailscale-exit-node-via-pia-wireguard).*

* **`VPN_USER`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account username (`pXXXXXXX`).
* **`VPN_PASS`**  
  *Default*: None (Required Secret)  
  *Description*: Private Internet Access account password.
* **`PIA_REGION`**  
  *Default*: `us_east,us_chicago,us_nyc`  
  *Description*: Comma-separated list of PIA US server regions for exit node egress.
* **`TS_AUTHKEY`**  
  *Default*: None (Optional One-Time Secret)  
  *Description*: One-time pre-authentication key generated in Tailscale Admin Console (**Settings -> Keys**) with Exit Node permissions.

---

## 3. Inlined Architectural Invariants (`compose.yml`)

In accordance with project conventions, configuration parameters representing fixed homelab invariants are inlined directly into `compose.yml` files rather than exposed as clutter in `.env.example` templates:

| Service | Inlined Parameter | Static Value | Architectural Rationale |
| :--- | :--- | :--- | :--- |
| **`homepage`** | `HOMEPAGE_ALLOWED_HOSTS` | `homepage.turing.home,www.turing.home,turing.home,192.168.0.4` | Enforces reverse proxy host header validation required by Homepage v0.8+. |
| **`nginx`** | `DISABLE_IPV6` | `"true"` | Standardizes single-stack IPv4 routing across internal Docker networks. |
| **`nginx`** | `DB_SQLITE_FILE` | `/data/db.sqlite` | Internal SQLite database location inside the NPM container. |
| **`postgres`** | `POSTGRES_DB` / `USER` / `PASSWORD` | `recipes` / `postgres` / `password` | Internal container-to-container credentials isolated to the private `homelab` bridge network. |
| **`qbittorrentvpn`** | `LOC` | `ca_ontario,ca_toronto,ca_montreal` | Regions supporting PIA NextGen dynamic port forwarding. |
| **`qbittorrentvpn`** | `LOCAL_NETWORK` | `192.168.0.0/16` | Bypasses VPN kill switch for LAN and Docker subnets. |
| **`qbittorrentvpn`** | `PORT_FORWARDING` / `PORT_FATAL` / `PORT_PERSIST` | `1` / `1` / `1` | Enforces automated port acquisition, fail-closed container exit on port drops, and ~60-day lease token persistence. |
| **`qbittorrentvpn`** | `PORT_SCRIPT` | `/set-qbt-port.sh` | Automated port and anti-thrashing synchronization hook. |
| **`seerr`** | `LOG_LEVEL` | `info` | Bounded logging verbosity. |
| **`tailscale`** | `TS_HOSTNAME` / `TS_ROUTES` | `homelab` / `192.168.0.0/24` | Fixed subnet router identity and LAN advertised routes. |
| **`tailscale`** | `TS_EXTRA_ARGS` | `--snat-subnet-routes=true --accept-dns=false` | Preserves local container DNS while enabling SNAT masquerading for remote peers. |
| **`vpn-bridge`** | `FWD_IFACE` / `VPN_PROTOCOL` | `tailscale+` / `wireguard` | Enforces WireGuard NAT forwarding from Tailscale interface into PIA tunnel. |

---

## 4. Homepage Dashboard Secret Interpolation

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
   Non-containerized appliances (like Pi-hole on `192.168.0.2`) are declared in `${DOCKER_DATA_DIR}/homepage/data/services.yaml`. Homepage natively interpolates `{{HOMEPAGE_VAR_<NAME>}}` placeholders with matching environment variables declared in `homepage/compose.yml`.
