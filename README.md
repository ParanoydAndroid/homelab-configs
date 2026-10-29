# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and management automation for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at [`${DOCKGE_STACKS_DIR}`](#21-global-settings-root-env) (symlinked to `/home/${USER}/services`) so that all service stacks are simultaneously version-controlled in git and manageable through Dockge. Persistent service state and media libraries are mapped to [`${DOCKER_DATA_DIR}`](#21-global-settings-root-env) and [`${MEDIA_DIR}`](#21-global-settings-root-env). For architectural principles, container privilege boundaries, and directory layout, see [the architecture specification](file:///home/brandon/services/.agents/artifacts/architecture.md).

---

## Table of Contents

- [1. External Dependencies, Cloud Accounts & Operational Assumptions](#1-external-dependencies-cloud-accounts--operational-assumptions)
  - [1.1 Commercial Cloud Accounts](#11-commercial-cloud-accounts)
  - [1.2 Environmental Assumptions (Unconfigurable Host Realities)](#12-environmental-assumptions-unconfigurable-host-realities)
- [2. Portable Host Configuration & Environment Variable Architecture](#2-portable-host-configuration--environment-variable-architecture)
  - [2.1 Global Settings (Root .env)](#21-global-settings-root-env)
  - [2.2 Per-Service Variables, Defaults & Secrets](#22-per-service-variables-defaults--secrets)
  - [2.3 Homepage Dashboard Service Discovery & Widget Keys](#23-homepage-dashboard-service-discovery--widget-keys)
- [3. Quickstart & Lifecycle Automation (homelab.sh)](#3-quickstart--lifecycle-automation-homelabsh)
  - [3.1 Fresh Host Provisioning](#31-fresh-host-provisioning)
  - [3.2 Routine Updates](#32-routine-updates)
  - [3.3 Automation CLI Subcommands](#33-automation-cli-subcommands)
  - [3.4 Common Operational Guides](#34-common-operational-guides)
- [4. Dual-Ingress Network Architecture](#4-dual-ingress-network-architecture)
  - [4.1 Subnets and Docker Networks](#41-subnets-and-docker-networks)
  - [4.2 Pillar 1: Public Web Ingress (*.kamaka.tech via Cloudflare Zero Trust)](#42-pillar-1-public-web-ingress-kamakatech-via-cloudflare-zero-trust)
  - [4.3 Pillar 2: Private Admin Ingress (*.turing.home via Tailscale Mesh)](#43-pillar-2-private-admin-ingress-turinghome-via-tailscale-mesh)
  - [4.4 LAN Host & Static IP Assignments](#44-lan-host--static-ip-assignments)
- [5. Service Catalog and Port Reference Table](#5-service-catalog-and-port-reference-table)
- [6. Stack Configuration, Security & Hardening Procedures](#6-stack-configuration-security--hardening-procedures)
  - [6.1 TLS & Certificate Management](#61-tls--certificate-management)
  - [6.2 External Jellyfin Security Hardening & Cache Rules](#62-external-jellyfin-security-hardening--cache-rules)
  - [6.3 Tailscale Macvlan Dual-Homing & Split DNS Configuration](#63-tailscale-macvlan-dual-homing--split-dns-configuration)
  - [6.4 WireGuard PIA Automated Dynamic Port Forwarding](#64-wireguard-pia-automated-dynamic-port-forwarding)
  - [6.5 Tandoor Recipes Media Serving in NPM](#65-tandoor-recipes-media-serving-in-npm)
- [7. Host OS Configuration, Services & Appliance Engineering](#7-host-os-configuration-services--appliance-engineering)
  - [7.1 Dual-Volume Storage Tiering Architecture](#71-dual-volume-storage-tiering-architecture)
  - [7.2 Host Packages & CLI Dependencies](#72-host-packages--cli-dependencies)
  - [7.3 Systemd Boot Services](#73-systemd-boot-services)
  - [7.4 Asynchronous Storage Mount Handling](#74-asynchronous-storage-mount-handling)
  - [7.5 Appliance OS Workarounds (Go 1.23+ GODEBUG Fix)](#75-appliance-os-workarounds-go-123-godebug-fix)

---

## 1. External Dependencies, Cloud Accounts & Operational Assumptions

The homelab architecture relies on four external commercial services to achieve remote ingress, secure tunneling, encrypted BitTorrent traffic, and version control.

### 1.1 Commercial Cloud Accounts

#### Cloudflare

| Provider | Primary Homelab Role | Account Tier | Associated Secrets |
| :--- | :--- | :--- | :--- |
| **Cloudflare** | Apex domain registrar, authoritative DNS, outbound Zero Trust tunnel, and Let's Encrypt DNS challenges | Free Tier | `CLOUDFLARE_TUNNEL_TOKEN`, `dns_cloudflare_api_token` |

*   **Domain & Registrar**: The domain (`kamaka.tech`) must be registered or transferred to Cloudflare, with Cloudflare acting as authoritative DNS nameservers.
*   **Zero Trust Tunnel**:
    *   An outbound tunnel named `homelab-media` is provisioned under **Networks -> Tunnels** in the Cloudflare One dashboard.
    *   Authentication token is stored in `cloudflared/.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
    *   Public Hostname routes wildcard `*.kamaka.tech` down the tunnel to `https://nginx:443` (TLS No Verify enabled, Origin Server Name `jellyfin.kamaka.tech`).
*   **Automated DNS Challenge Token**:
    *   Nginx Proxy Manager uses the Cloudflare API to automatically negotiate and renew Let's Encrypt wildcard certificates (`kamaka.tech`, `*.kamaka.tech`).
    *   Generated in Cloudflare Dashboard -> **My Profile -> API Tokens -> Create Token -> Use template "Edit zone DNS"**.
    *   Permissions: `Zone.DNS:Edit` for `kamaka.tech`. Supplied to NPM when provisioning the certificate.

#### Tailscale

| Provider | Primary Homelab Role | Account Tier | Associated Secrets |
| :--- | :--- | :--- | :--- |
| **Tailscale** | Coordination server (control plane) for encrypted peer-to-peer WireGuard mesh overlay | Personal (Free) | `TS_AUTHKEY` |

*   **Authentication & Registration**:
    *   A pre-authentication key is generated in the Tailscale Admin Console under **Settings -> Keys -> Generate auth key**.
    *   Stored in `tailscale/.env` as `TS_AUTHKEY`. The container automatically registers node name `homelab` to your Tailnet on startup.
*   **Subnet Route Approval**:
    *   The container advertises `192.168.0.0/24`. The administrator must approve this route in **Machines -> homelab -> Edit route settings...** before remote peers can access LAN devices.
*   **Split DNS Configuration**:
    *   Configured in **DNS -> Nameservers -> Add nameserver -> Custom** pointing to Pi-hole (`192.168.0.2`) restricted to search domain `.home`, ensuring remote mobile clients resolve `<service>.turing.home` seamlessly.

#### Private Internet Access (PIA)

| Provider | Primary Homelab Role | Account Tier | Associated Secrets |
| :--- | :--- | :--- | :--- |
| **Private Internet Access (PIA)** | BitTorrent network namespace tunnel with dynamic port forwarding | Paid Subscription | `VPN_USER`, `VPN_PASS` |

*   **Credentials**: Valid PIA username (`pXXXXXXX`) and password, stored in `qbittorrentvpn/.env` as `VPN_USER` and `VPN_PASS`.
*   **Port-Forwarding Region**:
    *   PIA restricts dynamic incoming port forwarding to non-US server locations.
    *   The container defaults to Canadian endpoints (`LOC=ca_ontario,ca_toronto,ca_montreal`) to guarantee dynamic port negotiation.

#### GitHub

| Provider | Primary Homelab Role | Account Tier | Associated Secrets |
| :--- | :--- | :--- | :--- |
| **GitHub** | Remote git repository hosting and version-controlled release tagging | Free | Host SSH Key (`id_ed25519` / `id_rsa`) |

*   **Upstream Repository**: The repository remote is configured as `git@github.com:ParanoydAndroid/homelab-configs.git`.
*   **SSH Key Authentication**: The NAS host user must have an active SSH key associated with the GitHub account to push automated backups and release tags via `./homelab.sh backup`.

---

### 1.2 Environmental Assumptions (Unconfigurable Host Realities)

These elements represent physical and carrier-level facts of the environment that cannot be changed via container environment variables:

1. **Carrier-Grade NAT (CGNAT) ISP Uplink**:
   *   The residential gateway WAN interface is assigned a carrier private IP in the `100.64.0.0/10` block (RFC 6598).
   *   Inbound IPv4 port forwarding (e.g. WAN `443` -> host) is technically impossible because upstream ISP routers do not maintain subscriber port mappings.
   *   All inbound connectivity must terminate over outbound-initiated encrypted tunnels (Cloudflare Tunnel for public web applications, Tailscale STUN/DERP hole-punching for private mesh networking).
2. **Gateway Router & DHCP Server (`192.168.0.1`)**:
   *   Physical router serves as DHCP server for `192.168.0.0/24`.
   *   Distributes `192.168.0.2` (Pi-hole) as primary DNS server and `.home` as search domain to all LAN DHCP clients.
   *   Enforces gateway firewall rule: `SOURCE 192.168.0.0/16 ALLOW`, `ALL DENY`.
3. **Pi-hole Local DNS Resolver (`192.168.0.2`)**:
   *   Resolves local LAN DNS queries and forwards `.home` lookups conditionally back to `192.168.0.1`.
   *   Defines local CNAME records mapping all internal `<service>.turing.home` subdomains to `turing.home` (`192.168.0.4`).
4. **Appliance Architecture**:
   *   UGREEN NAS runs a Debian-based Linux kernel (UGOS Pro).
   *   Appliance OS enforces a global `GODEBUG=tlskyber=0` environment flag that crashes Go 1.23+ binaries unless remediated by `./homelab.sh setup`.

---

## 2. Portable Host Configuration & Environment Variable Architecture

Configuration follows a two-tier `.env.example` -> `.env` architecture. All live `.env` files are excluded from git (`.gitignore`). Host-specific interface names, storage paths, user IDs, and network parameters are customized here rather than modifying Compose stack definitions.

### 2.1 Global Settings (Root `.env`)

The root `.env` defines global host paths, runtime user/group IDs, timezone, and macvlan network parameters that `./homelab.sh setup` automatically propagates into all child `<stack>/.env` files and `${DOCKGE_DIR}/.env`:

`DOCKER_DATA_DIR`  
Default: `/volume2/docker`  
Description: Root host directory for persistent container configurations, state, and database volumes.

`MEDIA_DIR`  
Default: `/volume1/media`  
Description: Root host directory for shared media libraries (movies, TV, downloads).

`DOCKGE_DIR`  
Default: `/opt/${USER}/dockge`  
Description: Host directory where Dockge's own `compose.yml` resides (one level above stacks).

`DOCKGE_STACKS_DIR`  
Default: `/opt/${USER}/dockge/stacks`  
Description: Host directory where version-controlled Compose stack subdirectories reside.

`PUID`  
Default: `1000`  
Description: Non-root user ID assigned to application containers (`brandon` on UGREEN NAS).

`PGID`  
Default: `100`  
Description: Non-root primary group ID assigned to application containers (`users` on UGREEN NAS).

`TZ`  
Default: `America/New_York`  
Description: Timezone passed to all containers for synchronized logs and cron tasks.

`EXTERNAL_NPM_PARENT`  
Default: `eth0`  
Description: Physical host network interface used as the parent for Docker `macvlan` networks.

`EXTERNAL_NPM_SUBNET`  
Default: `192.168.0.0/24`  
Description: Physical LAN IPv4 subnet CIDR block.

`EXTERNAL_NPM_GATEWAY`  
Default: `192.168.0.1`  
Description: Physical LAN gateway router IPv4 address.

`NPM_IPV4_ADDRESS`  
Default: `192.168.0.4`  
Description: Static LAN IP assigned to Nginx Proxy Manager on the `external_npm` macvlan network (`turing.home`).

`TAILSCALE_IPV4_ADDRESS`  
Default: `192.168.0.5`  
Description: Static LAN IP assigned to the Tailscale Subnet Router on the `external_npm` macvlan network (`homelab`).

---

### 2.2 Per-Service Variables, Defaults & Secrets

Per-stack `.env.example` templates define external secrets, application keys, and stack-specific overrides:

### cloudflared

`CLOUDFLARE_TUNNEL_TOKEN`  
Default: None  
Description: Cloudflare Zero Trust tunnel authentication token (see [Cloudflare Details](#cloudflare)).

### tailscale

`TS_AUTHKEY`  
Default: None  
Description: Pre-authentication key generated from Tailscale admin console for automated registration (see [Tailscale Details](#tailscale)).

`TS_HOSTNAME`  
Default: `homelab`  
Description: Tailscale node name advertised to the tailnet mesh.

`TS_ROUTES`  
Default: `192.168.0.0/24`  
Description: Subnet route advertised by the container to the tailnet.

`TS_EXTRA_ARGS`  
Default: `--snat-subnet-routes=true --accept-dns=false`  
Description: Tailscale CLI arguments enabling SNAT masquerading and preserving container DNS.

### qbittorrentvpn

`VPN_USER`  
Default: None  
Description: Private Internet Access account username (`pXXXXXXX`; see [PIA Details](#private-internet-access-pia)).

`VPN_PASS`  
Default: None  
Description: Private Internet Access account password.

`QBITTORRENT_PASSWORD`  
Default: None  
Description: WebUI administrator password for qBittorrent.

`LOC`  
Default: `ca_ontario,ca_toronto,ca_montreal`  
Description: Comma-separated list of PIA regions supporting NextGen dynamic port forwarding.

`LOCAL_NETWORK`  
Default: `192.168.0.0/16`  
Description: Subnets allowed to access qBittorrent WebUI without traversing the WireGuard tunnel.

`PORT_FORWARDING`  
Default: `1`  
Description: Enables NextGen dynamic incoming port forwarding on non-US PIA endpoints.

`PORT_PERSIST`  
Default: `1`  
Description: Persists PIA port signature in `/pia/portsig.json` across container restarts.

`PORT_SCRIPT`  
Default: `/set-qbt-port.sh`  
Description: Callback script invoked when PIA assigns a port to update qBittorrent via WebUI API.

### jellyfin

`JELLYFIN_API_KEY`  
Default: None  
Description: Jellyfin API key generated in Jellyfin Dashboard -> Administration -> API Keys. Used by Homepage container labels to poll streaming metrics.

### sonarr-radarr

`RADARR_API_KEY`  
Default: None  
Description: Deterministic 32-character API key for Radarr REST API and indexer integration.

`SONARR_API_KEY`  
Default: None  
Description: Deterministic 32-character API key for Sonarr REST API and indexer integration.

`PROWLARR_API_KEY`  
Default: None  
Description: Deterministic 32-character API key for Prowlarr indexer synchronization.

### seerr

`SEERR_API_KEY`  
Default: None  
Description: Deterministic 32-character API key for Seerr media discovery and request management.

### tandoor

`SECRET_KEY`  
Default: None  
Description: Django cryptographic signing secret (generate via `base64 /dev/urandom | head -c50`).

`POSTGRES_DB`  
Default: `recipes`  
Description: Database name for Tandoor in the PostgreSQL container.

`POSTGRES_USER`  
Default: `djangouser`  
Description: Database username for Tandoor.

`POSTGRES_PASSWORD`  
Default: `recipes_password`  
Description: Database password for Tandoor.

### homepage

`HOMEPAGE_VAR_PIHOLE_KEY`  
Default: None  
Description: Pi-hole admin password or API token for Homepage DNS query widget.

### postgres

`POSTGRES_DB`  
Default: `postgres`  
Description: Default maintenance database name.

`POSTGRES_USER`  
Default: `postgres`  
Description: PostgreSQL superuser username.

`POSTGRES_PASSWORD`  
Default: `postgres`  
Description: PostgreSQL superuser password (isolated to internal `homelab` Docker bridge).

### nginx

`DISABLE_IPV6`  
Default: `"true"`  
Description: Forces Nginx Proxy Manager to listen on IPv4 only.

`DB_SQLITE_FILE`  
Default: `/data/db.sqlite`  
Description: Path to SQLite database file inside the Nginx container volume.

---

### 2.3 Homepage Dashboard Service Discovery & Widget Keys

Homepage (`ghcr.io/gethomepage/homepage`) displays live status widgets (active streams, bandwidth, download queues, DNS statistics) without committing any secrets to git:

1. **Docker Container Labels (Containerized Services)**:
   *   Homepage mounts `/var/run/docker.sock` and inspects container labels.
   *   Compose files (`jellyfin`, `qbittorrentvpn`, `sonarr-radarr`) declare widget configuration using `${VAR}` syntax:
       ```yaml
       labels:
         - homepage.group=Media
         - homepage.name=Jellyfin
         - homepage.widget.type=jellyfin
         - homepage.widget.url=http://jellyfin:8096
         - homepage.widget.key=${JELLYFIN_API_KEY}
       ```
   *   Docker Compose reads each stack's `.env` and interpolates the API key into container metadata. Homepage reads the resolved key and polls the service directly across the `homelab` bridge network.
2. **Static YAML Environment Substitution (`HOMEPAGE_VAR_*` for Non-Docker Appliances)**:
   *   External appliances (such as Pi-hole on `192.168.0.2`) are defined statically in [.configs/homepage/services.yaml](file:///home/brandon/services/.configs/homepage/services.yaml).
   *   Homepage natively substitutes `{{HOMEPAGE_VAR_<NAME>}}` placeholders with matching environment variables passed to the `homepage` container via `homepage/compose.yml`.

---

## 3. Quickstart & Lifecycle Automation (homelab.sh)

### 3.1 Fresh Host Provisioning

```bash
# 1. Clone the repository into ${DOCKGE_STACKS_DIR} and symlink to ~/services
#    (See Section 2.1 for variable definitions)
sudo mkdir -p "${DOCKGE_DIR:-/opt/${USER}/dockge}"
git clone <repo-url> "${DOCKGE_STACKS_DIR:-/opt/${USER}/dockge/stacks}"
ln -s "${DOCKGE_STACKS_DIR:-/opt/${USER}/dockge/stacks}" "/home/${USER}/services"
cd "/home/${USER}/services"

# 2. Initialize .env files, Docker networks, and host workarounds
sudo ./homelab.sh setup

# 3. Populate required per-stack secrets and API keys in the generated .env files
#    (See Section 2.2 for per-service definitions and external dependencies):
#    - cloudflared/.env    (CLOUDFLARE_TUNNEL_TOKEN)
#    - tailscale/.env      (TS_AUTHKEY)
#    - qbittorrentvpn/.env (VPN_USER, VPN_PASS, QBITTORRENT_PASSWORD)
#    - homepage/.env       (HOMEPAGE_VAR_PIHOLE_KEY)
#    - jellyfin/.env       (JELLYFIN_API_KEY)
#    - sonarr-radarr/.env  (RADARR_API_KEY, SONARR_API_KEY, PROWLARR_API_KEY)
#    - seerr/.env          (SEERR_API_KEY)
#    - tandoor/.env        (SECRET_KEY)

# 4. Re-run setup to sync variables, deploy tracked configs, and start all containers
sudo ./homelab.sh setup
```

### 3.2 Routine Updates

```bash
cd ~/services
git pull
sudo ./homelab.sh setup
```

---

### 3.3 Automation CLI Subcommands

`homelab.sh` is an idempotent management script anchoring repository configurations to host volumes:

*   `sudo ./homelab.sh setup [--overwrite-all | --keep-all]`:
    Remediates host OS Go 1.23+ bugs, initializes `.env` files, syncs root global variables into stack `.env` files, audits for blank secrets, provisions `homelab` and `external_npm` networks, deploys tracked configurations, starts Dockge, and brings up all Compose stacks in dependency order.
*   `./homelab.sh test`:
    Zero-downtime regression and smoke test suite across all 14 containers: verifies container runtimes and healthchecks, direct admin interfaces (Dockge 8010 and NPM API), client-impersonated virtual host routing over NPM (validating SSL status codes and security blocks across `*.turing.home` and `*.kamaka.tech`), internal Docker DNS sockets, PIA VPN port sync, and Tailscale subnet router authentication.
*   `./homelab.sh startup`:
    Non-interactive boot and headless recovery orchestration hook designed for systemd execution on host startup: waits for storage volumes to mount, ensures Docker networks exist, and launches Dockge and all stacks in strict dependency order with database socket readiness verification.
*   `./homelab.sh deploy-configs [--overwrite-all | --keep-all]`:
    Compares tracked files in `.configs/` against live host files in `${DOCKER_DATA_DIR}/...`. Displays unified diffs on conflict, guards against deploying NPM configs referencing missing SSL certificates, and reloads Nginx dynamically on change.
*   `./homelab.sh pull-configs`:
    Retrieves live configuration changes made via Web UIs (Homepage YAML, NPM SQLite host tables, generated Nginx `.conf` files, and `set-qbt-port.sh`) from `${DOCKER_DATA_DIR}/...` back into `.configs/` for git versioning.
*   `./homelab.sh backup [--tag [tag_name]] [-m <message>]`:
    Pulls live service configurations into `.configs/`, stages and commits tracked repository changes, optionally tags `HEAD` (chronological CalVer `YYYY.M.D[.N]` or custom tag), and creates an encrypted archive of all live untracked `.env` secret files in `${DOCKER_DATA_DIR}/backup/homelab/`.

---

### 3.4 Common Operational Guides

#### Editing Proxy Hosts in NPM and Versioning in Git
1. Configure proxy hosts in the NPM Admin UI at `https://proxy.turing.home` (or `http://192.168.0.4:81`).
2. Pull the updated SQLite export and generated `.conf` files back into git:
   ```bash
   cd ~/services
   ./homelab.sh pull-configs
   git diff .configs/nginx/
   git add .configs/nginx/
   git commit -m "Update NPM proxy host configuration"
   ```

#### Updating Homepage Dashboard YAML
1. Edit [.configs/homepage/services.yaml](file:///home/brandon/services/.configs/homepage/services.yaml) or [.configs/homepage/settings.yaml](file:///home/brandon/services/.configs/homepage/settings.yaml).
2. Deploy the configuration to the live volume:
   ```bash
   ./homelab.sh deploy-configs
   ```

#### Creating Backups and Restoring Secrets
```bash
cd ~/services

# Run full backup with automatic chronological tag (e.g., 2026.10.29):
./homelab.sh backup --tag

# Run backup with custom release message and semantic tag:
./homelab.sh backup -m "Release 2.2.0: Tailscale subnet router" --tag 2.2.0

# Push committed history and tags to GitHub:
git push && git push --tags

# To restore all .env secrets on a fresh machine:
tar -xzf "${DOCKER_DATA_DIR:-/volume2/docker}/backup/homelab/latest_env_secrets.tar.gz" -C ~/services
sudo ./homelab.sh setup
```

---

## 4. Dual-Ingress Network Architecture

Ingress is divided into two strict, non-overlapping pillars: public traffic enters through Cloudflare Zero Trust, while private administrative traffic traverses the Tailscale WireGuard mesh.

```text
[ Internet Client ] ---> Cloudflare Edge ---> [ Cloudflare Tunnel ] ---+
                                                                       |
[ Remote Phone/PC ] ---> Tailscale Mesh  ---> [ Tailscale Router ] ----+---> [ Nginx Proxy Manager ] ---> [ Backend Stacks ]
                                                                       |     (192.168.0.4 / turing)      (192.168.255.0/24)
[ Local LAN Client] ---------------------------------------------------+
```

### 4.1 Subnets and Docker Networks

| Network Name | Driver / Type | Subnet | Gateway | Parent Interface | Role in Homelab |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **LAN** | Physical Ethernet | `192.168.0.0/24` | `192.168.0.1` | [`${EXTERNAL_NPM_PARENT}`](#21-global-settings-root-env) | Primary home network for physical appliances and Wi-Fi devices |
| **Tailscale Overlay** | WireGuard Mesh | `100.64.0.0/10` | N/A | Subnet Router | Encrypted peer-to-peer overlay network linking remote devices to LAN |
| **`homelab`** | Docker `bridge` | `192.168.255.0/24` | `192.168.255.1` | `br-*` | Isolated container-to-container bridge linking NPM and backend services |
| **`external_npm`** | Docker `macvlan` | `192.168.0.0/24` | `192.168.0.1` | [`${EXTERNAL_NPM_PARENT}`](#21-global-settings-root-env) | Assigns dedicated LAN IPs to NPM (`192.168.0.4`) and Tailscale (`192.168.0.5`) |

To create the Docker networks manually (automated by `./homelab.sh setup`):
```bash
docker network create -d bridge \
  --subnet=192.168.255.0/24 \
  --gateway=192.168.255.1 \
  homelab

docker network create -d macvlan \
  --subnet="${EXTERNAL_NPM_SUBNET:-192.168.0.0/24}" \
  --gateway="${EXTERNAL_NPM_GATEWAY:-192.168.0.1}" \
  -o parent="${EXTERNAL_NPM_PARENT:-eth0}" \
  external_npm
```

---

### 4.2 Pillar 1: Public Web Ingress (`*.kamaka.tech` via Cloudflare Zero Trust)

*   **Outbound-Only Tunnel (`cloudflared`)**: Connects outbound over QUIC / HTTP/2 to Cloudflare data centers. Requires no open router ports and functions transparently behind CGNAT.
*   **Wildcard Routing**: Public Hostname `*.kamaka.tech` routes down the tunnel to `https://nginx:443` (TLS No Verify enabled, Origin Server Name `jellyfin.kamaka.tech`).
*   **Centralized Edge Security**:
    *   `jellyfin.kamaka.tech` routes to `jellyfin:8096` with WebSockets, HSTS, video cache bypass, and reverse-proxy blocks on `/metrics`, `/swagger`, and `/api-docs`.
    *   `recipes.kamaka.tech` routes to `tandoor:8080` with static `/media/` serving.
    *   Unmapped subdomains hit NPM's default host and return 404.

---

### 4.3 Pillar 2: Private Admin Ingress (`*.turing.home` via Tailscale Mesh)

*   **Subnet Router (`tailscale`)**:
    *   Dual-homed on `external_npm` (`192.168.0.5`) and `homelab` (`192.168.255.0/24`).
    *   Advertises `192.168.0.0/24` to the Tailscale mesh with SNAT masquerading (`--snat-subnet-routes=true`).
*   **Subnet Access Restriction (`192.168.0.0/16`)**:
    *   All internal `*.turing.home` virtual hosts enforce `allow 192.168.0.0/16; allow 127.0.0.1; deny all;`.
    *   Tailscale clients arrive at NPM bearing source IP `192.168.0.5` and are accepted. External WAN requests targeting `.turing.home` are dropped with `HTTP 403 Forbidden`.
*   **UGOS Portal Access (`nas.turing.home`)**:
    *   Linux kernel macvlan isolation prevents macvlan child `192.168.0.5` from communicating directly with host `192.168.0.3`.
    *   Access is standardized by routing `https://nas.turing.home` through NPM, which forwards across the `homelab` bridge directly to `https://192.168.255.1:9443`.

---

### 4.4 LAN Host & Static IP Assignments

| Hostname / Domain | IP Address | Network Interface | Operational Role & Routing Behavior |
| :--- | :--- | :--- | :--- |
| **Gateway / Router** | `192.168.0.1` | Physical Gateway | DHCP server; authorative for `.home` hostnames; forwards DNS queries to Pi-hole |
| **Pi-hole** | `192.168.0.2` | Dedicated Appliance | Local DNS resolver; defines CNAME records: `*.turing.home` -> `turing.home` |
| **`nas.home`** | `192.168.0.3` | UGREEN NAS (`eth0`) | Host OS portal (`https://nas.home:9443`) and emergency Dockge port (`8010`) |
| **`turing.home`** | `192.168.0.4` | `external_npm` macvlan | Nginx Proxy Manager dedicated LAN IP; terminates HTTP (`80`), HTTPS (`443`), and Admin UI (`81`) |
| **`homelab` (Tailscale)** | `192.168.0.5` | `external_npm` macvlan | Tailscale Subnet Router; advertises `192.168.0.0/24` to Tailscale WireGuard mesh |

---

## 5. Service Catalog and Port Reference Table

All web applications are reverse-proxied by Nginx Proxy Manager over the internal `homelab` Docker network (`192.168.255.0/24`). Host ports on `192.168.0.3` are exposed only where strictly required for non-HTTP broadcast discovery or emergency orchestrator fallback.

*(Paths reference host volume variables [`${DOCKER_DATA_DIR}` and `${MEDIA_DIR}`](#21-global-settings-root-env)).*

| Service Name | Stack / Path | Host Port (`nas.home`) | Container Port | Protocol | Active Host Binding | Internal Address (`turing.home`) | External Address (`kamaka.tech`) | Persistent Host Data Path |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **UGREEN NAS (UGOS)** | Host OS | `9443` / `80` / `443` | N/A | HTTP / HTTPS | Yes (Host OS) | `https://nas.turing.home` | None | N/A |
| **Dockge** | `.configs/dockge` | `8010` | `5001` | TCP (HTTP) | **Yes** (`8010:5001`) | `https://dockge.turing.home` | None | `${DOCKER_DATA_DIR}/dockge/data` |
| **Nginx Proxy Manager** | `nginx/` | `8480`/`8443`/`8444` | `80`/`443`/`81` | TCP | Macvlan (`192.168.0.4`) | `https://proxy.turing.home` | `https://*.kamaka.tech` (via Tunnel) | `${DOCKER_DATA_DIR}/nginx/data` |
| **Tailscale Router** | `tailscale/` | None | None | WireGuard | Macvlan (`192.168.0.5`) | `homelab` (Mesh) | None | `${DOCKER_DATA_DIR}/tailscale/data` |
| **Cloudflare Tunnel** | `cloudflared/` | None | None | QUIC / HTTP/2 | No (Egress Tunnel) | None | Ingress for `*.kamaka.tech` | Stateless |
| **Jellyfin** | `jellyfin/` | `8020` / `8021` | `8096` / `8920` | TCP (HTTP/S) | No (Proxied via NPM) | `https://jellyfin.turing.home` | `https://jellyfin.kamaka.tech` | `${DOCKER_DATA_DIR}/jellyfin/data/config` |
| **Jellyfin Discovery** | `jellyfin/` | `8022` | `7359` | UDP | **Yes** (`8022:7359/udp`) | LAN Broadcast | None | N/A |
| **Homepage** | `homepage/` | `8030` | `3000` | TCP (HTTP) | No (Proxied via NPM) | `https://homepage.turing.home` | None | `${DOCKER_DATA_DIR}/homepage/data` |
| **Radarr** | `sonarr-radarr/` | `8040` | `7878` | TCP (HTTP) | No (Proxied via NPM) | `https://radarr.turing.home` | None | `${DOCKER_DATA_DIR}/radarr/data` |
| **Sonarr** | `sonarr-radarr/` | `8041` | `8989` | TCP (HTTP) | No (Proxied via NPM) | `https://sonarr.turing.home` | None | `${DOCKER_DATA_DIR}/sonarr/data` |
| **Prowlarr** | `sonarr-radarr/` | `8042` | `9696` | TCP (HTTP) | No (Proxied via NPM) | `https://prowlarr.turing.home` | None | `${DOCKER_DATA_DIR}/prowlarr/data` |
| **FlareSolverr** | `sonarr-radarr/` | `8043` | `8191` | TCP (HTTP) | No (Internal / NPM) | `https://flaresolverr.turing.home` | None | Stateless |
| **Seerr** | `seerr/` | `8055` | `5055` | TCP (HTTP) | No (Proxied via NPM) | `https://seerr.turing.home` | None | `${DOCKER_DATA_DIR}/seerr/data` |
| **Tandoor Recipes** | `tandoor/` | `8050` | `8050` | TCP (HTTP) | No (Proxied via NPM) | `https://recipes.turing.home` | `https://recipes.kamaka.tech` | `${DOCKER_DATA_DIR}/tandoor/data/{staticfiles,mediafiles}` |
| **PostgreSQL** | `postgres/` | None | `5432` | TCP | No (`homelab` only) | `postgresql:5432` (Internal) | None | `${DOCKER_DATA_DIR}/postgres/data` |
| **WireGuard PIA VPN** | `qbittorrentvpn/` | `8081` | `8081` | TCP (WebUI) | No (Proxied via NPM) | `https://torrent.turing.home` | None | `${DOCKER_DATA_DIR}/qbittorrentvpn/data/{pia,pia-shared}` |
| **qBittorrent** | `qbittorrentvpn/` | Dynamic (PIA) | Dynamic (PIA) | TCP / UDP | No (`wg0` Tunnel) | `http://qbittorrentvpn:8081` (Internal) | VPN Tunnel (`wg0`) | `${DOCKER_DATA_DIR}/qbittorrentvpn/data/config`, `${MEDIA_DIR}` |

---

## 6. Stack Configuration, Security & Hardening Procedures

### 6.1 TLS & Certificate Management

#### Combined Local Wildcard Certificate (`turing.home` & `nas.home`)
Avoids browser security warnings across all internal web services and the NAS host OS:
1. Generate `turing.key` and `turing.crt` (valid for 10 years covering `turing.home`, `*.turing.home`, `nas.home`, `*.nas.home`):
   ```bash
   cd ~/services/.configs/nginx
   ./generate-local-cert.sh
   ```
2. **Client Import**: Import `turing.crt` into your OS/browser Trusted Root Certification Authorities store.
3. **UGREEN NAS Import**: Under **Control Panel -> Security -> Certificate**, upload `turing.key` and `turing.crt` and set as default.
4. **NPM Import**:
   - Open `https://proxy.turing.home` -> **SSL Certificates -> Add SSL Certificate -> Custom**.
   - Name: `Local Wildcard (turing.home + nas.home)`, Key: `turing.key`, Certificate: `turing.crt`.
   - Assign to all `*.turing.home` proxy hosts.

#### Cloudflare Let's Encrypt Wildcard Certificate (`*.kamaka.tech`)
1. In NPM -> **SSL Certificates -> Add SSL Certificate -> Let's Encrypt**.
2. Domains: `kamaka.tech`, `*.kamaka.tech`.
3. Select **Use a DNS Challenge** -> Provider: **Cloudflare**.
4. Enter `dns_cloudflare_api_token = <your-cloudflare-token>` and save.
5. Assign to external proxy hosts (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`).
6. If setting up a fresh host where `deploy-configs` skipped NPM `.conf` files due to missing certs, re-run `./homelab.sh deploy-configs` after creating the certificates.

---

### 6.2 External Jellyfin Security Hardening & Cache Rules

#### Container & Proxy Hardening (Automated in Repo)
*   `jellyfin/compose.yml` runs Jellyfin non-root (`user: "1000:100"`), drops capabilities (`cap_drop: [ALL]`), enforces `no-new-privileges:true`, and mounts media read-only (`:ro`).
*   The NPM proxy host ([proxy_host/3.conf](file:///home/brandon/services/.configs/nginx/nginx/proxy_host/3.conf)) enforces Force SSL, HTTP/2, HSTS, WebSockets, disables proxy buffering, and returns `HTTP 403 Forbidden` on `/swagger`, `/api-docs`, and `/metrics`.

#### Cloudflare Cache Bypass for Video Streaming
To prevent Cloudflare's CDN caching layer from buffering or throttling video chunks:
1. In Cloudflare Dashboard -> `kamaka.tech` -> **Caching -> Cache Rules -> Create Rule**.
2. Name: `Bypass Jellyfin Video Cache`.
3. Match: Field `Hostname` equals `jellyfin.kamaka.tech`.
4. Action: **Bypass cache**.

#### Jellyfin Server Settings (One-Time UI Check)
In **Jellyfin Dashboard -> Networking** and **Dashboard -> Users**:
1. **Local Subnets**: Add `192.168.255.0/24`.
2. **Known Proxies**: Add `192.168.255.0/24` (or NPM bridge hostname `nginx`) so Jellyfin logs real client IPs.
3. **Disable Remote Admin**: Administrative User -> Profile -> uncheck **Allow remote connections to this server**.
4. **Hide Users & Lockout**: Check **Hide this user from login screens** for all users; set **Invalid login attempts before lockout** to `3` or `5`.

---

### 6.3 Tailscale Macvlan Dual-Homing & Split DNS Configuration

#### The Macvlan Dual-Homing Rationale
The Tailscale container must connect to both `external_npm` (`192.168.0.5`) and `homelab` (`192.168.255.0/24`):
*   Linux kernel macvlan driver security forbids macvlan child interfaces from communicating directly with the parent host interface (`192.168.0.3` on `eth0`).
*   However, macvlan child interfaces **can** communicate with other macvlan children (`192.168.0.4` NPM) and physical LAN devices (`192.168.0.1`, `192.168.0.2`).
*   By dual-homing on `external_npm`, Tailscale reaches NPM and physical LAN devices directly.
*   By dual-homing on `homelab`, NPM proxies `https://nas.turing.home` across the bridge directly to `https://192.168.255.1:9443`, bypassing the host macvlan drop rule.

#### Subnet Route Approval & Split DNS Guide
1. **Approve Route**: In the [Tailscale Admin Console](https://login.tailscale.com/admin/machines), locate node `homelab` -> **Edit route settings...** -> enable `192.168.0.0/24`.
2. **Configure Split DNS**: In Tailscale Admin Console -> **DNS -> Nameservers -> Add nameserver -> Custom**:
   *   Nameserver IP: `192.168.0.2` (Pi-hole).
   *   Enable **Restrict to search domain** and enter **`.home`**.
   *   Remote mobile clients query Pi-hole for `<service>.turing.home` while general internet lookups use local Wi-Fi/cellular DNS.

---

### 6.4 WireGuard PIA Automated Dynamic Port Forwarding

#### Two-Container Shared Network Namespace
`qbittorrentvpn/compose.yml` decouples the VPN tunnel and BitTorrent client into two dedicated containers:
1. **`vpn` (`wireguard-pia`)**: Authenticates with PIA, registers a WireGuard interface (`wg0`), enforces an `iptables` kill switch (`FIREWALL: 1`), and permits local WebUI traffic from `LOCAL_NETWORK: 192.168.0.0/16`.
2. **`qbittorrent` (`qbittorrentvpn`)**: Uses `network_mode: "service:vpn"`. It shares `wireguard-pia`'s network stack and cannot transmit traffic outside `wg0`.

#### Automated Listening Port Synchronization (`set-qbt-port.sh`)
PIA NextGen port forwarding automates port binding:
1. **Token Signature**: `/scripts/pf.sh` requests a cryptographic port signature from the PIA gateway (`https://<cn>:19999/getSignature`), caches it in `/pia/portsig.json` (~60-day lease), and opens the port on `wg0`.
2. **WebUI Sync**: Executes `PORT_SCRIPT: /set-qbt-port.sh <port>` ([.configs/qbittorrentvpn/set-qbt-port.sh](file:///home/brandon/services/.configs/qbittorrentvpn/set-qbt-port.sh)), which waits for qBittorrent's WebUI listener (`127.0.0.1:8081`) and sends an HTTP POST to `/api/v2/app/setPreferences` with `json={"listen_port":<port>}`.
3. **15-Minute Keepalive Loop**: `/scripts/pf.sh` re-binds the port every 900 seconds. If port forwarding fails, `PORT_FATAL: 1` triggers container exit and automated failover.

---

### 6.5 Tandoor Recipes Media Serving in NPM

Tandoor's Gunicorn application server does not serve user-uploaded `/media/` files directly in production. Instead, `nginx/compose.yml` mounts `${DOCKER_DATA_DIR}/tandoor/data/mediafiles:/media:ro` read-only, and the `recipes.kamaka.tech` and `recipes.turing.home` proxy hosts include the custom Nginx block:
```nginx
location /media/ {
    root /;
}
```

---

## 7. Host OS Configuration, Services & Appliance Engineering

This section documents host-level configurations, background services, package prerequisites, and appliance workarounds implemented directly on the host operating system (UGOS Pro / Debian 12) to support the homelab architecture.

### 7.1 Dual-Volume Storage Tiering Architecture

The homelab divides storage across two distinct physical media tiers rather than using fragile SSD caching layers:

| Mount Point | Physical Tier | Filesystem | Workload & Purpose |
| :--- | :--- | :--- | :--- |
| **`/volume1`** | 3x 10TB HDDs (RAID 5) | Btrfs | Shared media libraries (`/volume1/media`) and compressed backup archives (`/volume1/backups`). Sequential I/O excels on mechanical drives. |
| **`/volume2`** | 500GB NVMe SSD (M.2 Slot 1) | Btrfs | High-IOPS container configurations, databases, and image caches (`/volume2/docker`). Delivers 300,000+ random 4K IOPS with sub-millisecond seek latency. |

**Reasoning**:
Jellyfin, Nginx Proxy Manager, and Homepage perform continuous random read/write transactions against SQLite databases (`jellyfin.db`, `db.sqlite`) and look up tens of thousands of individual thumbnail files. On spinning disks, 10–15 ms mechanical head seeks cause severe library scrolling stutter and blank poster pop-in. Moving `${DOCKER_DATA_DIR}` to native PCIe NVMe eliminates seek latency entirely (reducing page load times from 15+ seconds down to <1.5 seconds) while keeping large sequential video files on fault-tolerant HDD storage.

### 7.2 Host Packages & CLI Dependencies

The host operating system requires the following standard packages to support `homelab.sh` automation, testing, and backups:

*   **`sqlite3`**: Required by `homelab.sh pull-configs` and `homelab.sh backup` to perform clean, non-sensitive SQL table dumps of NPM routing tables (`npm_hosts.sql`) and atomic online SQLite database snapshots without taking services offline.
*   **`rsync`**: Required for archive-grade configuration and data synchronization preserving exact Unix UIDs, GIDs, file modes, and extended attributes (`-aHX`).
*   **`tar` & `zstd`**: Used to generate compressed `.env` secret archives and Docker volume backups.
*   **`curl` & `jq`**: Required by `./homelab.sh test` to execute HTTPS client impersonation probes, validate TLS certificates, and inspect Docker network state.

To install missing dependencies on Debian/UGOS Pro:
```bash
sudo apt update && sudo apt install -y sqlite3 rsync zstd curl jq
```

**User Lingering**:
To allow background user processes and systemd managers to persist when no interactive SSH session is open:
```bash
sudo loginctl enable-linger brandon
```

### 7.3 Systemd Boot Services

Tracked unit definitions are maintained in `.configs/systemd/` and deployed to `/etc/systemd/system/`.

#### 1. Antigravity Remote Control Daemon (`antigravity-remote-control.service`)

*   **Unit File**: `/etc/systemd/system/antigravity-remote-control.service`
*   **Tracked Template**: `.configs/systemd/antigravity-remote-control.service`
*   **Purpose**: Keeps the Google Antigravity Remote Control daemon (`Aumaka`) persistently online across system reboots.
*   **Operational Behavior**:
    Runs `/home/brandon/.gemini/bin/agy remote-control serve` as user `brandon`. Includes an `ExecStartPre` polling loop that waits until `/home/brandon/.gemini/bin/agy` exists on disk before attempting startup, and sets `Restart=always` with `RestartSec=5s` so the daemon recovers instantly once user files are accessible.

To install or reload the service:
```bash
sudo cp ~/services/.configs/systemd/antigravity-remote-control.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now antigravity-remote-control.service
```

#### 2. Homelab Startup Orchestrator (`homelab-startup.service`)

*   **Unit File**: `/etc/systemd/system/homelab-startup.service`
*   **Tracked Template**: `.configs/systemd/homelab-startup.service`
*   **Purpose**: Automatically initializes Docker networks, Dockge, and all application stacks in strict dependency order on host boot.
*   **Operational Behavior**:
    Executes `/home/brandon/services/homelab.sh startup` after `docker.service` and `storage_serv.service` reach readiness. The script:
    1. Polls until `${DOCKER_DATA_DIR}` (`/volume2/docker`) is mounted (up to a 60-second safety window).
    2. Provisions the `homelab` (`192.168.255.0/24`) and `external_npm` (`192.168.0.0/24`) Docker networks if absent.
    3. Launches the Dockge orchestrator.
    4. Launches stacks in order (`postgres`, `nginx`, `tailscale`, `homepage`, `jellyfin`, `qbittorrentvpn`, `sonarr-radarr`, `seerr`, `tandoor`), actively verifying PostgreSQL socket readiness via `docker exec postgres pg_isready` before starting dependent services.

To install or reload the service:
```bash
sudo cp ~/services/.configs/systemd/homelab-startup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable homelab-startup.service
```

### 7.4 Asynchronous Storage Mount Handling

On UGOS Pro, user home directories (`/home/<user>`) and secondary storage pools (`/volume2`) are mounted **asynchronously** by UGREEN's internal Go storage daemon (`storage_serv`) well after systemd's early boot phase.

*   **The Problem with Standard User Units (`systemd --user`)**:
    When systemd starts `user@1000.service`, `/home/brandon` is not yet mounted from `/volume1/@home/brandon`. As a result, `systemd --user` processes an empty directory, misses user unit files in `~/.config/systemd/user/`, and reaches `default.target` prematurely. When `/home/brandon` is finally mounted minutes later, user units remain dormant.
*   **The Architectural Remediation**:
    Critical background services (like Antigravity Remote Control and Homelab Stack Orchestration) are placed in `/etc/systemd/system/` under `multi-user.target`, bound to `User=brandon`, and equipped with startup polling loops. This guarantees reliable execution regardless of how late UGOS mounts underlying volumes.

### 7.5 Appliance OS Workarounds (Go 1.23+ GODEBUG Fix)

UGREEN NAS OS injects `GODEBUG=tlskyber=0` into `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`. Because Go 1.23 removed the legacy `tlskyber` flag, Go 1.23+ binaries (including developer tools, telemetry agents, and remote servers) panic on startup.

`sudo ./homelab.sh setup` automatically remediates this idempotently on every run. To apply the fix manually after an OS firmware update:
```bash
sudo sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
sudo sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
sudo systemctl unset-environment GODEBUG
systemctl --user unset-environment GODEBUG || true
sudo systemctl daemon-reexec
```
