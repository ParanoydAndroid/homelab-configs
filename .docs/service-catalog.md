# Service Catalog and Port Reference

This catalog documents every containerized service, orchestrator, and host portal operating in the homelab environment.

---

## 1. Active Network Bindings & Port Reference

Host network ports on `192.168.0.3` (`nas.home`) are exposed **only** where strictly required for non-HTTP broadcast discovery or emergency orchestrator fallback. All other web applications communicate strictly over the internal `homelab` Docker bridge network (`192.168.255.0/24`) and are reverse-proxied by Nginx Proxy Manager.

| Service Name | Stack Directory | Container Name | Active Host / Network Binding | Container Port | Protocol | Internal Address (`turing.home`) | External Address (`kamaka.tech`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **UGREEN NAS (UGOS)** | Host OS | N/A | `192.168.0.3:9443` | `9443` | HTTPS | `https://nas.turing.home` | None |
| **Dockge** | `.configs/dockge` | `dockge` | `127.0.0.1:8010` / `192.168.0.3:8010` | `5001` | HTTP | `https://dockge.turing.home` | None |
| **Nginx Proxy Manager** | `nginx/` | `nginx` | Macvlan `192.168.0.4` (`80`, `443`, `81`) | `80`, `443`, `81` | HTTP / HTTPS | `https://proxy.turing.home` | `https://*.kamaka.tech` (via Tunnel) |
| **Tailscale Router** | `tailscale/` | `tailscale` | Macvlan `192.168.0.5` | N/A | WireGuard | Node `homelab` on Mesh | None |
| **Cloudflare Tunnel** | `cloudflared/` | `cloudflared` | Outbound Egress Tunnel | N/A | QUIC / HTTP/2 | None | Public Ingress for `*.kamaka.tech` |
| **Jellyfin** | `jellyfin/` | `jellyfin` | Internal Bridge Only | `8096` | HTTP | `https://jellyfin.turing.home` | `https://jellyfin.kamaka.tech` |
| **Jellyfin Discovery** | `jellyfin/` | `jellyfin` | `0.0.0.0:8022:7359/udp` | `7359` | UDP | LAN Broadcast | None |
| **Homepage** | `homepage/` | `homepage` | Internal Bridge Only | `3000` | HTTP | `https://homepage.turing.home` | None |
| **Radarr** | `sonarr-radarr/` | `radarr` | Internal Bridge Only | `7878` | HTTP | `https://radarr.turing.home` | None |
| **Sonarr** | `sonarr-radarr/` | `sonarr` | Internal Bridge Only | `8989` | HTTP | `https://sonarr.turing.home` | None |
| **Prowlarr** | `sonarr-radarr/` | `prowlarr` | Internal Bridge Only | `9696` | HTTP | `https://prowlarr.turing.home` | None |
| **FlareSolverr** | `sonarr-radarr/` | `flaresolverr` | Internal Bridge Only | `8191` | HTTP | `https://flaresolverr.turing.home` | None |
| **Seerr** | `seerr/` | `seerr` | Internal Bridge Only | `5055` | HTTP | `https://seerr.turing.home` | None |
| **Tandoor Recipes** | `tandoor/` | `tandoor` | Internal Bridge Only | `8050` | HTTP | `https://recipes.turing.home` | `https://recipes.kamaka.tech` |
| **PostgreSQL** | `postgres/` | `postgres` | Internal Bridge Only | `5432` | TCP | `postgresql:5432` (Internal) | None |
| **WireGuard PIA VPN** | `qbittorrentvpn/` | `wireguard-pia` | Internal Bridge Only | `8081` | HTTP (WebUI) | `https://torrent.turing.home` | None |
| **qBittorrent** | `qbittorrentvpn/` | `qbittorrentvpn` | Network Mode: `service:vpn` | Dynamic | BitTorrent | `http://qbittorrentvpn:8081` (Internal) | Dynamic VPN Port (`wg0`) |

---

## 2. Detailed Service Specifications

### UGREEN NAS (UGOS Pro)

| Attribute | Value |
| :--- | :--- |
| **Component** | Host Storage Appliance Operating System (Debian 12 base) |
| **Host IP & Port** | `192.168.0.3:9443` (Web Portal) / `80` (HTTP) / `443` (HTTPS) |
| **Internal Address** | `https://nas.turing.home` |
| **External Address** | None (Restricted to private LAN / Tailscale) |
| **Active Host Binding** | Native Host OS Listeners |

* **Role & Capabilities**: Appliance operating system managing storage pools (`/volume1` HDD array and `/volume2` NVMe SSD), user permissions, SMB/NFS file shares, and system-level daemons.
* **Network & Access**: Accessed locally at `https://nas.home:9443` or via reverse proxy at `https://nas.turing.home`. Because Linux kernel macvlan isolation prevents macvlan child `192.168.0.5` (Tailscale) from reaching host `192.168.0.3` directly, Nginx Proxy Manager bridges incoming requests from `homelab` to `https://192.168.255.1:9443`.
* **Storage & Volume Mappings**: N/A (Host root OS).

---

### Dockge

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `.configs/dockge` (Deployed to `${DOCKGE_DIR}/compose.yml`) |
| **Container Name** | `dockge` |
| **Host / Network Binding** | `8010:5001` (Emergency Host Fallback) + `homelab` bridge |
| **Internal Container Port**| `5001` |
| **Internal Address** | `https://dockge.turing.home` (or direct `http://192.168.0.3:8010`) |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/dockge/data` |
| **Associated Secrets** | None |

* **Role & Capabilities**: Web-based orchestrator and visual management interface for Docker Compose stacks. Allows editing compose definitions, monitoring container health, viewing live logs, and controlling stack lifecycles.
* **Network & Access**: Proxied internally at `https://dockge.turing.home`. In the event of a reverse proxy failure, direct host port `8010` provides an emergency administrative bypass.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/dockge/data` for Dockge database and application state, `/var/run/docker.sock` to interface with the Docker daemon, and `${DOCKGE_STACKS_DIR}` to manage stack subdirectories.
* **Dependencies & Interconnections**: Manages all other stacks in `${DOCKGE_STACKS_DIR}`. Deployed outside the stacks directory so it does not self-manage.

---

### Nginx Proxy Manager (NPM)

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `nginx/` |
| **Container Name** | `nginx` |
| **Host / Network Binding** | Macvlan `192.168.0.4` (`80`, `443`, `81`) + `homelab` bridge (`192.168.255.0/24`) |
| **Internal Container Port**| `80` (HTTP), `443` (HTTPS), `81` (Admin UI) |
| **Internal Address** | `https://proxy.turing.home` (Admin UI) |
| **External Address** | `https://*.kamaka.tech` (Terminates Cloudflare Tunnel ingress) |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/nginx/data` |
| **Associated Secrets** | Cloudflare DNS API Token (Let's Encrypt automated challenge) |

* **Role & Capabilities**: Central reverse proxy and TLS termination gateway. Handles virtual host routing, SSL certificate management (Let's Encrypt DNS challenges and local wildcard certs), security headers, and access control lists.
* **Network & Access**: Dual-homed on `external_npm` macvlan (`192.168.0.4`) and `homelab` bridge (`192.168.255.4`). Admin UI is available at `https://proxy.turing.home` or `http://192.168.0.4:81`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/nginx/data` for SQLite database (`db.sqlite`), generated Nginx configurations (`data/nginx`), custom and Let's Encrypt SSL certificates (`data/custom_ssl`, `data/letsencrypt`), and `${DOCKER_DATA_DIR}/tandoor/data/mediafiles:/media:ro` for static media serving.
* **Dependencies & Interconnections**: Routes HTTP/HTTPS traffic to all containerized backend web services over the `homelab` bridge network.

---

### Tailscale Router

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `tailscale/` |
| **Container Name** | `tailscale` |
| **Host / Network Binding** | Macvlan `192.168.0.5` (`external_npm`) + `homelab` bridge |
| **Internal Container Port**| N/A (WireGuard Mesh Daemon) |
| **Internal Address** | Node `homelab` on Tailscale Mesh |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/tailscale/data` |
| **Associated Secrets** | `TS_AUTHKEY` |

* **Role & Capabilities**: Secure subnet router connecting the homelab to the private Tailscale WireGuard mesh. Advertises `192.168.0.0/24` with SNAT masquerading (`--snat-subnet-routes=true`), enabling authorized remote devices (laptops, phones) to reach internal LAN services without open firewall ports.
* **Network & Access**: Dual-homed on `external_npm` (`192.168.0.5`) to reach LAN devices (`192.168.0.1`, `192.168.0.2`, `192.168.0.4`) and `homelab` bridge to proxy `nas.turing.home`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/tailscale/data:/var/lib/tailscale` for node identity and cryptographic keys, and `/dev/net/tun:/dev/net/tun` for kernel tunnel routing.
* **Dependencies & Interconnections**: Requires `NET_ADMIN` and `NET_RAW` capabilities. Integrates with Pi-hole for split DNS resolution.

---

### Cloudflare Tunnel (`cloudflared`)

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `cloudflared/` |
| **Container Name** | `cloudflared` |
| **Host / Network Binding** | Outbound Tunnel (No host ports or LAN IP) |
| **Internal Container Port**| N/A |
| **Internal Address** | None |
| **External Address** | Egress tunnel for `*.kamaka.tech` |
| **Persistent Data Path** | Stateless (No persistent volume) |
| **Associated Secrets** | `CLOUDFLARE_TUNNEL_TOKEN` |

* **Role & Capabilities**: Zero Trust outbound edge tunnel. Connects over QUIC/HTTP2 to Cloudflare data centers to expose public services (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`) securely through CGNAT residential internet connections without port forwarding.
* **Network & Access**: Attaches strictly to the `homelab` Docker bridge network. Forwards incoming wildcard `*.kamaka.tech` requests down the tunnel directly to `https://nginx:443`.
* **Storage & Volume Mappings**: Stateless container; configuration and authentication are driven purely by `CLOUDFLARE_TUNNEL_TOKEN`.
* **Dependencies & Interconnections**: Requires outbound internet connectivity to Cloudflare edge nodes and DNS resolution for `nginx` on the `homelab` bridge.

---

### Jellyfin

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `jellyfin/` |
| **Container Name** | `jellyfin` |
| **Host / Network Binding** | `8022:7359/udp` (LAN Discovery) + `homelab` bridge |
| **Internal Container Port**| `8096` (HTTP), `8920` (HTTPS), `7359` (UDP Discovery) |
| **Internal Address** | `https://jellyfin.turing.home` |
| **External Address** | `https://jellyfin.kamaka.tech` |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/jellyfin/data` |
| **Associated Secrets** | `JELLYFIN_API_KEY` |

* **Role & Capabilities**: Central media server for movies, television shows, and music. Features hardware-accelerated transcoding (`/dev/dri`), multi-user management, stream monitoring, and client synchronization.
* **Network & Access**: Reverse-proxied over the `homelab` bridge at `https://jellyfin.turing.home` (internal) and `https://jellyfin.kamaka.tech` (external). Binds host port `8022:7359/udp` for local client autodiscovery.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/jellyfin/data/config` for SQLite databases and metadata, `${DOCKER_DATA_DIR}/jellyfin/data/cache` for temporary transcoding chunks, and `${MEDIA_DIR}:/media:ro` read-only for bulk media libraries.
* **Dependencies & Interconnections**: Passes streaming metrics to Homepage via `JELLYFIN_API_KEY`. Connects to Seerr for media requests.

---

### Homepage

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `homepage/` |
| **Container Name** | `homepage` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `3000` |
| **Internal Address** | `https://homepage.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/homepage/data` |
| **Associated Secrets** | `HOMEPAGE_VAR_PIHOLE_KEY` |

* **Role & Capabilities**: Central service dashboard providing quick navigation links, active container metrics, BitTorrent download progress, Jellyfin stream counters, and Pi-hole DNS query statistics.
* **Network & Access**: Accessible internally at `https://homepage.turing.home`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/homepage/data` for YAML configuration files (`services.yaml`, `settings.yaml`, `widgets.yaml`, `custom.css`), and `/var/run/docker.sock:ro` for automated Docker service discovery.
* **Dependencies & Interconnections**: Interfaces with Docker daemon labels and polls APIs across the `homelab` bridge (`jellyfin:8096`, `qbittorrentvpn:8081`, `radarr:7878`, `sonarr:8989`) and LAN (`192.168.0.2:80`).

---

### Radarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `sonarr-radarr/` |
| **Container Name** | `radarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `7878` |
| **Internal Address** | `https://radarr.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/radarr/data` |
| **Associated Secrets** | `RADARR_API_KEY` |

* **Role & Capabilities**: Automated movie collection manager, release indexer, and download coordinator. Searches for movie releases via Prowlarr, sends downloads to qBittorrent, and organizes files into media libraries.
* **Network & Access**: Accessible internally at `https://radarr.turing.home`. REST API is authenticated via `RADARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/radarr/data` for application configuration and database, and `${MEDIA_DIR}:/media` for file organization and hardlinking.
* **Dependencies & Interconnections**: Connects to Prowlarr (`http://prowlarr:9696`), qBittorrent (`http://qbittorrentvpn:8081`), and Seerr.

---

### Sonarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `sonarr-radarr/` |
| **Container Name** | `sonarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `8989` |
| **Internal Address** | `https://sonarr.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/sonarr/data` |
| **Associated Secrets** | `SONARR_API_KEY` |

* **Role & Capabilities**: Automated television series collection manager, episode monitor, and release grabber. Interfaces with Prowlarr to monitor indexers and delegates downloads to qBittorrent.
* **Network & Access**: Accessible internally at `https://sonarr.turing.home`. REST API is authenticated via `SONARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/sonarr/data` for application database and settings, and `${MEDIA_DIR}:/media` for automated media renaming and hardlinking.
* **Dependencies & Interconnections**: Connects to Prowlarr (`http://prowlarr:9696`), qBittorrent (`http://qbittorrentvpn:8081`), and Seerr.

---

### Prowlarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `sonarr-radarr/` |
| **Container Name** | `prowlarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `9696` |
| **Internal Address** | `https://prowlarr.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/prowlarr/data` |
| **Associated Secrets** | `PROWLARR_API_KEY` |

* **Role & Capabilities**: Centralized indexer proxy and aggregator for BitTorrent trackers and Usenet indexers. Automatically synchronizes indexer configurations and health across Radarr and Sonarr.
* **Network & Access**: Accessible internally at `https://prowlarr.turing.home`. API authenticated via `PROWLARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/prowlarr/data` for application settings and indexer configurations.
* **Dependencies & Interconnections**: Routes Cloudflare-protected indexer requests through FlareSolverr (`http://flaresolverr:8191`). Syncs directly to Radarr (`radarr:7878`) and Sonarr (`sonarr:8989`).

---

### FlareSolverr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `sonarr-radarr/` |
| **Container Name** | `flaresolverr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `8191` |
| **Internal Address** | `https://flaresolverr.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | Stateless |
| **Associated Secrets** | None |

* **Role & Capabilities**: Headless Chromium proxy server designed to solve Cloudflare anti-bot challenges and DDoS protections on behalf of indexers managed by Prowlarr.
* **Network & Access**: Accessible internally at `https://flaresolverr.turing.home` and directly over the `homelab` bridge at `http://flaresolverr:8191`.
* **Storage & Volume Mappings**: Stateless container (no persistent volume mounts).
* **Dependencies & Interconnections**: Used exclusively by Prowlarr as an indexing proxy.

---

### Seerr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `seerr/` |
| **Container Name** | `seerr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `5055` |
| **Internal Address** | `https://seerr.turing.home` |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/seerr/data` |
| **Associated Secrets** | `SEERR_API_KEY` |

* **Role & Capabilities**: Media request, discovery, and approval portal. Allows users to search for movies and television shows, view trailers, request additions, and automatically track download progress.
* **Network & Access**: Accessible internally at `https://seerr.turing.home`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/seerr/data` for application state and SQLite database.
* **Dependencies & Interconnections**: Interfaces directly with Jellyfin (`http://jellyfin:8096`) for user authentication and library discovery, Radarr (`http://radarr:7878`) for movie requests, and Sonarr (`http://sonarr:8989`) for TV requests.

---

### Tandoor Recipes

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `tandoor/` |
| **Container Name** | `tandoor` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `8050` |
| **Internal Address** | `https://recipes.turing.home` |
| **External Address** | `https://recipes.kamaka.tech` |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/tandoor/data` |
| **Associated Secrets** | `SECRET_KEY`, `POSTGRES_PASSWORD` |

* **Role & Capabilities**: Comprehensive recipe management system, meal planner, and grocery list organizer. Supports web scraping, ingredient scaling, and multi-user recipe sharing.
* **Network & Access**: Reverse-proxied over the `homelab` bridge at `https://recipes.turing.home` (internal) and `https://recipes.kamaka.tech` (external). Nginx serves user-uploaded media files directly from `${DOCKER_DATA_DIR}/tandoor/data/mediafiles:/media:ro`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/tandoor/data/staticfiles` and `${DOCKER_DATA_DIR}/tandoor/data/mediafiles`.
* **Dependencies & Interconnections**: Relies on PostgreSQL container (`postgresql:5432`) for data storage.

---

### PostgreSQL

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `postgres/` |
| **Container Name** | `postgres` |
| **Host / Network Binding** | Internal `homelab` bridge only (Isolated from host) |
| **Internal Container Port**| `5432` |
| **Internal Address** | `postgresql:5432` (Internal) |
| **External Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/postgres/data` |
| **Associated Secrets** | `POSTGRES_PASSWORD` |

* **Role & Capabilities**: Relational database server backing backend applications (currently Tandoor Recipes).
* **Network & Access**: Completely isolated to the internal `homelab` Docker bridge network (`192.168.255.0/24`). Port `5432` is not bound to host interfaces or LAN.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/postgres/data:/var/lib/postgresql/data` (owned by internal PostgreSQL UID `70`).
* **Dependencies & Interconnections**: Starts first in homelab dependency order; verified by `pg_isready` before dependent services launch.

---

### WireGuard PIA VPN & qBittorrent

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `qbittorrentvpn/` |
| **Container Names** | `wireguard-pia` (VPN) & `qbittorrentvpn` (BitTorrent) |
| **Host / Network Binding** | Internal `homelab` bridge only (`8081` WebUI) |
| **Internal Container Port**| `8081` (WebUI), Dynamic Forwarded Port (BitTorrent) |
| **Internal Address** | `https://torrent.turing.home` |
| **External Address** | None (Traffic routes exclusively via WireGuard tunnel `wg0`) |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/qbittorrentvpn/data` |
| **Associated Secrets** | `VPN_USER`, `VPN_PASS`, `QBITTORRENT_PASSWORD` |

* **Role & Capabilities**: Decoupled VPN network namespace and BitTorrent client. The `wireguard-pia` container maintains an encrypted WireGuard tunnel (`wg0`) to Private Internet Access with a strict `iptables` kill switch. The `qbittorrentvpn` container runs inside the VPN's network namespace (`network_mode: "service:vpn"`), preventing any packet from leaking to the LAN or WAN outside the tunnel.
* **Network & Access**: WebUI accessible internally at `https://torrent.turing.home` and directly over the bridge at `http://qbittorrentvpn:8081`. Local access without VPN traversal is permitted via `LOCAL_NETWORK: 192.168.0.0/16`.
* **Automated Dynamic Port Forwarding**: The PIA container dynamically requests an open port in supported regions (e.g. Canada) and runs `/set-qbt-port.sh` ([.configs/qbittorrentvpn/set-qbt-port.sh](file:///home/brandon/services/.configs/qbittorrentvpn/set-qbt-port.sh)) to automatically update qBittorrent's active listening port via WebUI API.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/qbittorrentvpn/data/config` for qBittorrent state, `${DOCKER_DATA_DIR}/qbittorrentvpn/data/pia` and `pia-shared` for port sync files, and `${MEDIA_DIR}:/media` for downloads.
* **Dependencies & Interconnections**: Downloads managed by Radarr and Sonarr via REST API.
