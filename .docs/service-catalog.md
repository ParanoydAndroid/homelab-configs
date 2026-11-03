# Service Catalog and Port Reference

This catalog documents every containerized service, orchestrator, and host portal operating in the homelab environment.

---

## 1. Active Network Bindings & Port Reference

Host network ports on `192.168.0.3` (`nas.home`) are exposed **only** where strictly required for non-HTTP broadcast discovery or emergency orchestrator fallback. All other web applications communicate strictly over the internal `homelab` Docker bridge network (`192.168.255.0/24`) and are reverse-proxied by Caddy Docker Proxy.

| Service Name | Stack Directory | Container Name | Active Host / Network Binding | Container Port | Protocol | LAN Address (`kamaka.tech`) | WAN Address (`kamakakai.com`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **UGREEN NAS (UGOS)** | Host OS | N/A | `192.168.0.3:9443` | `9443` | HTTPS | `https://nas.kamaka.tech` | None |
| **Dockge** | `.configs/dockge` | `dockge` | `127.0.0.1:8010` / `192.168.0.3:8010` | `5001` | HTTP | `https://dockge.kamaka.tech` | None |
| **Caddy Proxy** | `ingress/` | `caddy` | Macvlan `192.168.0.4` (`80`, `443`) | `80`, `443` | HTTP / HTTPS | `https://*.kamaka.tech` | `https://*.kamakakai.com` (via Tunnel) |
| **File Delivery** | `ingress/` | `caddy` | Internal / Macvlan | `443` | HTTPS | `https://download.kamaka.tech` | None |
| **Tailscale Router** | `mesh/` | `tailscale` | Macvlan `192.168.0.5` | N/A | WireGuard | Node `homelab` on Mesh | None |
| **Cloudflare Tunnel** | `ingress/` | `cloudflared` | Outbound Egress Tunnel | N/A | QUIC / HTTP/2 | None | Public Ingress for `*.kamakakai.com` |
| **Jellyfin** | `media/` | `jellyfin` | Internal Bridge Only | `8096` | HTTP | `https://jellyfin.kamaka.tech`, `https://media.kamaka.tech` | `https://jellyfin.kamakakai.com`, `https://media.kamakakai.com` |
| **Jellyfin Discovery** | `media/` | `jellyfin` | `0.0.0.0:8022:7359/udp` | `7359` | UDP | LAN Broadcast | None |
| **Homepage** | `dashboard/` | `homepage` | Internal Bridge Only | `3000` | HTTP | `https://homepage.kamaka.tech` | None |
| **Radarr** | `media/` | `radarr` | Internal Bridge Only | `7878` | HTTP | `https://radarr.kamaka.tech` | None |
| **Sonarr** | `media/` | `sonarr` | Internal Bridge Only | `8989` | HTTP | `https://sonarr.kamaka.tech` | None |
| **Prowlarr** | `media/` | `prowlarr` | Internal Bridge Only | `9696` | HTTP | `https://prowlarr.kamaka.tech` | None |
| **FlareSolverr** | `media/` | `flaresolverr` | Internal Bridge Only | `8191` | HTTP | `https://flaresolverr.kamaka.tech` | None |
| **Seerr** | `media/` | `seerr` | Internal Bridge Only | `5055` | HTTP | `https://seerr.kamaka.tech` | None |
| **Calibre-Web** | `books/` | `calibre-web` | Internal Bridge Only | `8083` | HTTP | `https://books.kamaka.tech` | None |
| **Readarr** | `books/` | `readarr` | Internal Bridge Only | `8787` | HTTP | `https://readarr.kamaka.tech` | None |
| **Royal Road Sync** | `books/` | `royalroad-sync` | Internal Bridge Only | N/A | Daemon | None (Internal Worker) | None |
| **Mealie Recipes** | `productivity/` | `mealie` | Internal Bridge Only | `9000` | HTTP | `https://recipes.kamaka.tech` | `https://recipes.kamakakai.com`, `https://mom.kamakakai.com` |
| **WireGuard PIA VPN** | `torrent/` | `wireguard-pia` | Internal Bridge Only | `8081` | HTTP (WebUI) | `https://torrent.kamaka.tech` | None |
| **qBittorrent** | `torrent/` | `qbittorrentvpn` | Network Mode: `service:vpn` | Dynamic | BitTorrent | `http://qbittorrentvpn:8081` (Internal) | Dynamic VPN Port (`wg0`) |
| **VPN Bridge (PIA)** | `mesh/` | `vpn-bridge-pia` | Internal Bridge Only | N/A | WireGuard | Outbound PIA Tunnel (`wg0`) | Egress via US PIA Regions |
| **VPN Bridge (Tailscale)** | `mesh/` | `vpn-bridge-tailscale` | Network Mode: `service:vpn` | N/A | WireGuard | Node `vpn-bridge` on Mesh | Tailscale Exit Node |

---

## 2. Detailed Service Specifications

### UGREEN NAS (UGOS Pro)

| Attribute | Value |
| :--- | :--- |
| **Component** | Host Storage Appliance Operating System (Debian 12 base) |
| **Host IP & Port** | `192.168.0.3:9443` (Web Portal) / `80` (HTTP) / `443` (HTTPS) |
| **LAN Address** | `https://nas.kamaka.tech` |
| **WAN Address** | None (Restricted to private LAN / Tailscale) |
| **Active Host Binding** | Native Host OS Listeners |

* **Role & Capabilities**: Appliance operating system managing storage pools (`/volume1` HDD array and `/volume2` NVMe SSD), user permissions, SMB/NFS file shares, and system-level daemons.
* **Network & Access**: Accessed locally at `https://nas.home:9443` or via reverse proxy at `https://nas.kamaka.tech`. Because Linux kernel macvlan isolation prevents macvlan child `192.168.0.5` (Tailscale) from reaching host `192.168.0.3` directly, Caddy terminates TLS and bridges incoming requests from `homelab` to `http://192.168.255.1:9999`.
* **Storage & Volume Mappings**: N/A (Host root OS).

---

### Dockge

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `.configs/dockge` (Deployed to `${DOCKGE_DIR}/compose.yml`) |
| **Container Name** | `dockge` |
| **Host / Network Binding** | `8010:5001` (Emergency Host Fallback) + `homelab` bridge |
| **Internal Container Port**| `5001` |
| **LAN Address** | `https://dockge.kamaka.tech` (or direct `http://192.168.0.3:8010`) |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/dockge/data` |
| **Associated Secrets** | None |

* **Role & Capabilities**: Web-based orchestrator and visual management interface for Docker Compose stacks. Allows editing compose definitions, monitoring container health, viewing live logs, and controlling stack lifecycles.
* **Network & Access**: Proxied internally at `https://dockge.kamaka.tech`. In the event of a reverse proxy failure, direct host port `8010` provides an emergency administrative bypass.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/dockge/data:/app/data` for Dockge database and application state, `/var/run/docker.sock:/var/run/docker.sock` to interface with the Docker daemon, and `${DOCKGE_STACKS_DIR}:${DOCKGE_STACKS_DIR}` to read and manage Compose stack directories.
* **Dependencies & Interconnections**: Manages all other stacks in `${DOCKGE_STACKS_DIR}`. Deployed outside the stacks directory so it does not self-manage.

---

### Caddy Docker Proxy

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `ingress/` |
| **Container Name** | `caddy` |
| **Host / Network Binding** | Macvlan `192.168.0.4` (`80`, `443`) + `homelab` bridge (`192.168.255.0/24`) |
| **Internal Container Port**| `80` (HTTP), `443` (HTTPS) |
| **LAN Address** | `https://*.kamaka.tech` |
| **WAN Address** | `https://*.kamakakai.com` (Terminates Cloudflare Tunnel ingress) |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/caddy/data`, `${DOCKER_DATA_DIR}/caddy/downloads` |
| **Associated Secrets** | `CLOUDFLARE_API_TOKEN` (DNS-01 ACME automated wildcard challenges) |

* **Role & Capabilities**: Declarative reverse proxy and automated TLS termination gateway. Discovers service backends dynamically through Docker Compose labels (`caddy=host`, `caddy.reverse_proxy={{upstreams port}}`), automates Let's Encrypt certificates via Cloudflare DNS-01, and provides a mobile-friendly file delivery server at `https://download.kamaka.tech/`.
* **Network & Access**: Dual-homed on `external_npm` macvlan (`192.168.0.4`) and `homelab` bridge (`192.168.255.0/24`).
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/caddy/data:/data` for Let's Encrypt certificates and ACME state, `${DOCKER_DATA_DIR}/caddy/config:/config` for autosaved JSON runtime state, `${DOCKER_DATA_DIR}/caddy/downloads:/downloads` for client file delivery, and `/var/run/docker.sock:/var/run/docker.sock:ro` for container event observation.
* **Dependencies & Interconnections**: Routes HTTP/HTTPS traffic to all backend containers across the `homelab` bridge network.

---

### Mealie Recipe Manager

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `productivity/` |
| **Container Name** | `mealie` |
| **Host / Network Binding** | Internal Bridge Only (`homelab`) |
| **Internal Container Port**| `9000` (HTTP) |
| **LAN Address** | `https://recipes.kamaka.tech` |
| **WAN Address** | `https://recipes.kamakakai.com`, `https://mom.kamakakai.com` |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/mealie/data` |
| **Associated Secrets** | None |

* **Role & Capabilities**: Recipe manager and meal planner with recipe scraping, shopping lists, and REST API.
* **Network & Access**: Accessible locally at `https://recipes.kamaka.tech` and publicly at `https://recipes.kamakakai.com` / `https://mom.kamakakai.com`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/mealie/data:/app/data` for persistent application data and recipe assets.
* **Dependencies & Interconnections**: None.

---

### Tailscale Router

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `mesh/` |
| **Container Name** | `tailscale` |
| **Host / Network Binding** | Macvlan `192.168.0.5` (`external_npm`) + `homelab` bridge |
| **Internal Container Port**| N/A (WireGuard Mesh Daemon) |
| **LAN Address** | Node `homelab` on Tailscale Mesh |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/tailscale/data` |
| **Associated Secrets** | `TS_AUTHKEY` |

* **Role & Capabilities**: Secure subnet router connecting the homelab to the private Tailscale WireGuard mesh. Advertises `192.168.0.0/24` with SNAT masquerading (`--snat-subnet-routes=true`), enabling authorized remote devices (laptops, phones) to reach internal LAN services without open firewall ports.
* **Network & Access**: Dual-homed on `external_npm` (`192.168.0.5`) to reach LAN devices (`192.168.0.1`, `192.168.0.2`, `192.168.0.4`) and `homelab` bridge to proxy `nas.kamaka.tech`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/tailscale/data:/var/lib/tailscale` for node identity and cryptographic keys, and `/dev/net/tun:/dev/net/tun` for kernel tunnel routing.
* **Dependencies & Interconnections**: Requires `NET_ADMIN` and `NET_RAW` capabilities. Integrates with Pi-hole for split DNS resolution.

---

### Cloudflare Tunnel (`cloudflared`)

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `ingress/` |
| **Container Name** | `cloudflared` |
| **Host / Network Binding** | Outbound Tunnel (Internal Bridge Only) |
| **Internal Container Port**| N/A |
| **LAN Address** | None |
| **WAN Address** | Ingress tunnel for `*.kamakakai.com` |
| **Persistent Data Path** | Stateless |
| **Associated Secrets** | `CLOUDFLARE_TUNNEL_TOKEN` |

* **Role & Capabilities**: Zero Trust outbound edge tunnel exposing public services (`jellyfin.kamakakai.com`, `recipes.kamakakai.com`, `mom.kamakakai.com`) securely through CGNAT residential internet connections without port forwarding.
* **Network & Access**: Attaches to the `homelab` Docker bridge network and forwards incoming public requests directly to `https://caddy:443`.
* **Storage & Volume Mappings**: Stateless container.
* **Dependencies & Interconnections**: Outbound internet connectivity to Cloudflare edge nodes and internal connectivity to `caddy`.

---

### Jellyfin

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `jellyfin` |
| **Host / Network Binding** | `8022:7359/udp` (LAN Discovery) + `homelab` bridge |
| **Internal Container Port**| `8096` (HTTP), `8920` (HTTPS), `7359` (UDP Discovery) |
| **LAN Address** | `https://jellyfin.kamaka.tech`, `https://media.kamaka.tech` |
| **WAN Address** | `https://jellyfin.kamakakai.com`, `https://media.kamakakai.com` |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/jellyfin/data/config` |
| **Associated Secrets** | `JELLYFIN_API_KEY` |

* **Role & Capabilities**: Central media server for movies, television shows, and music. Features hardware-accelerated transcoding (`/dev/dri`), multi-user management, and client synchronization.
* **Network & Access**: Reverse-proxied over the `homelab` bridge at `https://jellyfin.kamaka.tech` (internal) and `https://jellyfin.kamakakai.com` (external). Binds host port `8022:7359/udp` for local client autodiscovery.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/jellyfin/data/config:/config` for server configuration and metadata, and `${MEDIA_DIR}:/data/media:ro` read-only for bulk media libraries. Exposes Intel iGPU render node `/dev/dri/renderD128` for Quick Sync transcoding.
* **Dependencies & Interconnections**: Passes streaming metrics to Homepage via `JELLYFIN_API_KEY`. Connects to Seerr for media requests.

---

### Homepage

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `dashboard/` |
| **Container Name** | `homepage` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `3000` |
| **LAN Address** | `https://homepage.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/homepage/data` |
| **Associated Secrets** | `HOMEPAGE_VAR_PIHOLE_KEY` |

* **Role & Capabilities**: Central service dashboard providing quick navigation links, active container metrics, BitTorrent download progress, Jellyfin stream counters, and Pi-hole DNS query statistics.
* **Network & Access**: Accessible internally at `https://homepage.kamaka.tech`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/homepage/data:/app/config` for YAML configuration files (`services.yaml`, `settings.yaml`, `widgets.yaml`, `custom.css`), and `/var/run/docker.sock:/var/run/docker.sock` for automated Docker service discovery.
* **Dependencies & Interconnections**: Interfaces with Docker daemon labels and polls APIs across the `homelab` bridge (`jellyfin:8096`, `qbittorrentvpn:8081`, `radarr:7878`, `sonarr:8989`) and LAN (`192.168.0.2:80`).

---

### Radarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `radarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `7878` |
| **LAN Address** | `https://radarr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/radarr/data` |
| **Associated Secrets** | `RADARR_API_KEY` |

* **Role & Capabilities**: Automated movie collection manager, release indexer, and download coordinator. Searches for movie releases via Prowlarr, sends downloads to qBittorrent, and organizes files into media libraries.
* **Network & Access**: Accessible internally at `https://radarr.kamaka.tech`. REST API is authenticated via `RADARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/radarr/data:/config` for application configuration and SQLite database, and `${MEDIA_DIR}:/media` for file organization and hardlinking.
* **Dependencies & Interconnections**: Connects to Prowlarr (`http://prowlarr:9696`), qBittorrent (`http://qbittorrentvpn:8081`), and Seerr.

---

### Sonarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `sonarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `8989` |
| **LAN Address** | `https://sonarr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/sonarr/data` |
| **Associated Secrets** | `SONARR_API_KEY` |

* **Role & Capabilities**: Automated television series collection manager, episode monitor, and release grabber. Interfaces with Prowlarr to monitor indexers and delegates downloads to qBittorrent.
* **Network & Access**: Accessible internally at `https://sonarr.kamaka.tech`. REST API is authenticated via `SONARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/sonarr/data:/config` for application database and settings, and `${MEDIA_DIR}:/media` for automated media renaming and hardlinking.
* **Dependencies & Interconnections**: Connects to Prowlarr (`http://prowlarr:9696`), qBittorrent (`http://qbittorrentvpn:8081`), and Seerr.

---

### Prowlarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `prowlarr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `9696` |
| **LAN Address** | `https://prowlarr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/prowlarr/data` |
| **Associated Secrets** | `PROWLARR_API_KEY` |

* **Role & Capabilities**: Centralized indexer proxy and aggregator for BitTorrent trackers and Usenet indexers. Automatically synchronizes indexer configurations and health across Radarr, Sonarr, and Readarr.
* **Network & Access**: Accessible internally at `https://prowlarr.kamaka.tech`. API authenticated via `PROWLARR_API_KEY`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/prowlarr/data:/config` for application database and settings.
* **Dependencies & Interconnections**: Integrates with FlareSolverr (`http://flaresolverr:8191`) for Cloudflare challenge resolution, and pushes indexer definitions to Radarr (`http://radarr:7878`), Sonarr (`http://sonarr:8989`), and Readarr (`http://readarr:8787`).
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/prowlarr/data:/config` for application settings and indexer configurations.
* **Dependencies & Interconnections**: Routes Cloudflare-protected indexer requests through FlareSolverr (`http://flaresolverr:8191`). Syncs directly to Radarr (`radarr:7878`) and Sonarr (`sonarr:8989`).

---

### FlareSolverr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `flaresolverr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `8191` |
| **LAN Address** | `https://flaresolverr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | Stateless |
| **Associated Secrets** | None |

* **Role & Capabilities**: Headless Chromium proxy server designed to solve Cloudflare anti-bot challenges and DDoS protections on behalf of indexers managed by Prowlarr.
* **Network & Access**: Accessible internally at `https://flaresolverr.kamaka.tech` and directly over the `homelab` bridge at `http://flaresolverr:8191`.
* **Storage & Volume Mappings**: Stateless container (no persistent volume mounts).
* **Dependencies & Interconnections**: Used exclusively by Prowlarr as an indexing proxy.

---

### Seerr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `media/` |
| **Container Name** | `seerr` |
| **Host / Network Binding** | Internal `homelab` bridge only |
| **Internal Container Port**| `5055` |
| **LAN Address** | `https://seerr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/seerr/data` |
| **Associated Secrets** | `SEERR_API_KEY` |

* **Role & Capabilities**: Media request, discovery, and approval portal. Allows users to search for movies and television shows, view trailers, request additions, and automatically track download progress.
* **Network & Access**: Accessible internally at `https://seerr.kamaka.tech`.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/seerr/data:/app/config` for application state and SQLite database.
* **Dependencies & Interconnections**: Interfaces directly with Jellyfin (`http://jellyfin:8096`) for user authentication and library discovery, Radarr (`http://radarr:7878`) for movie requests, and Sonarr (`http://sonarr:8989`) for TV requests.

---

### WireGuard PIA VPN & qBittorrent

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `torrent/` |
| **Container Names** | `wireguard-pia` (VPN) & `qbittorrentvpn` (BitTorrent) |
| **Host / Network Binding** | Internal `homelab` bridge only (`8081` WebUI) |
| **Internal Container Port**| `8081` (WebUI), Dynamic Forwarded Port (BitTorrent) |
| **LAN Address** | `https://torrent.kamaka.tech` |
| **WAN Address** | None (Traffic routes exclusively via WireGuard tunnel `wg0`) |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/qbittorrentvpn/data` |
| **Associated Secrets** | `VPN_USER`, `VPN_PASS`, `QBITTORRENT_PASSWORD` |

* **Role & Capabilities**: Decoupled VPN network namespace and BitTorrent client. The `wireguard-pia` container maintains an encrypted WireGuard tunnel (`wg0`) to Private Internet Access with a strict `iptables` kill switch. The `qbittorrentvpn` container runs inside the VPN's network namespace (`network_mode: "service:vpn"`).
* **Network & Access**: WebUI accessible internally at `https://torrent.kamaka.tech` and directly over the bridge at `http://qbittorrentvpn:8081`. Local access without VPN traversal is permitted via `LOCAL_NETWORK: 192.168.0.0/16`.
* **Automated Port Forwarding**: The PIA container requests an open port dynamically and synchronizes active listening port and anti-thrashing preferences to qBittorrent via [.configs/qbittorrentvpn/set-qbt-port.sh](../.configs/qbittorrentvpn/set-qbt-port.sh).
* **Storage & Volume Mappings**:
  * **`wireguard-pia` (VPN)**: Mounts `${DOCKER_DATA_DIR}/qbittorrentvpn/data/pia:/pia` for port tokens, `${DOCKER_DATA_DIR}/qbittorrentvpn/data/pia-shared:/pia-shared` for port sync state, and `${DOCKER_DATA_DIR}/qbittorrentvpn/data/set-qbt-port.sh:/set-qbt-port.sh:ro`.
  * **`qbittorrentvpn` (BitTorrent)**: Mounts `${DOCKER_DATA_DIR}/qbittorrentvpn/data/config:/config` for preferences and state, `${DOCKER_DATA_DIR}/qbittorrentvpn/data/incomplete:/incomplete` as scratch storage, and `${MEDIA_DIR}:/media` for completed downloads.
* **Dependencies & Interconnections**: Downloads managed by Radarr and Sonarr via REST API.

---

### VPN Bridge (Tailscale Exit Node via PIA WireGuard)

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `mesh/` |
| **Container Names** | `vpn-bridge-pia` (VPN) & `vpn-bridge-tailscale` (Tailscale Exit Node) |
| **Host / Network Binding** | Internal `homelab` bridge only (No exposed host ports) |
| **Internal Container Port**| N/A (WireGuard Tunnel & Mesh Daemon) |
| **LAN Address** | Node `vpn-bridge` on Tailscale Mesh |
| **WAN Address** | Egress via WireGuard tunnel (`wg0`) |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/vpn-bridge/data` |
| **Associated Secrets** | `VPN_USER`, `VPN_PASS`, `TS_AUTHKEY` |

* **Role & Capabilities**: Dedicated privacy bridge providing an encrypted Tailscale exit node routing remote client WAN traffic through Private Internet Access.
* **Network & Access**: The Tailscale container operates inside the network namespace of the PIA container (`network_mode: "service:vpn"`). Devices selecting `vpn-bridge` route public traffic through the WireGuard tunnel without exposing the homelab ISP IP.
* **Storage & Volume Mappings**:
  * **`vpn-bridge-pia` (VPN)**: Mounts `${DOCKER_DATA_DIR}/vpn-bridge/data/pia:/pia` for WireGuard lease state.
  * **`vpn-bridge-tailscale` (Tailscale Exit Node)**: Mounts `${DOCKER_DATA_DIR}/vpn-bridge/data/tailscale:/var/lib/tailscale` for node state, `/dev/net/tun:/dev/net/tun` for tunnel routing, and `tmpfs: [/tmp]`.
* **Dependencies & Interconnections**: Requires `NET_ADMIN` capability on `vpn-bridge-pia` and `NET_ADMIN`, `NET_RAW` capabilities on `vpn-bridge-tailscale`.

---

### Calibre-Web

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `books/` |
| **Container Name** | `calibre-web` |
| **Host / Network Binding** | Internal `homelab` bridge only (No exposed host ports) |
| **Internal Container Port**| `8083` |
| **LAN Address** | `https://books.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/calibre-web/data` |
| **Associated Secrets** | None |

* **Role & Capabilities**: Web-based clean e-book reading UI, Calibre catalog browser, OPDS server (`/opds`) for Boox e-ink readers and KOReader, and Send-to-Kindle outbound email dispatcher. Features `universal-calibre` mod for automated `ebook-convert` and `kepubify` conversions.
* **Network & Access**: Proxied internally at `https://books.kamaka.tech` with TLS termination and LAN restriction. OPDS endpoint supports HTTP Basic Authentication for e-ink readers.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/calibre-web/data:/config` for app configuration and `app.db`, `${MEDIA_DIR}/books/library:/books` for the shared Calibre library and `metadata.db`, and `${MEDIA_DIR}/books/import:/import` for inbound e-book imports.
* **Dependencies & Interconnections**: Reads the Calibre library managed by Readarr and imports EPUBs generated by the Royal Road sync daemon.

---

### Readarr

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `books/` |
| **Container Name** | `readarr` |
| **Host / Network Binding** | Internal `homelab` bridge only (No exposed host ports) |
| **Internal Container Port**| `8787` |
| **LAN Address** | `https://readarr.kamaka.tech` |
| **WAN Address** | None |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/readarr/data` |
| **Associated Secrets** | `READARR_API_KEY` |

* **Role & Capabilities**: Automated book collection manager, author monitor, and indexer search coordinator. Integrates with Prowlarr for indexers and qBittorrent for downloads.
* **Network & Access**: Proxied internally at `https://readarr.kamaka.tech`. Protected by mandatory API key authentication.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/readarr/data:/config` for SQLite databases and application state, `${MEDIA_DIR}/books/library:/books` as the root library destination, and `${MEDIA_DIR}:/media` enabling atomic zero-copy hardlinks from `/media/downloads/books`.
* **Dependencies & Interconnections**: Connects to Prowlarr (`http://prowlarr:9696`) for indexer definitions and qBittorrent (`http://qbittorrentvpn:8081`) for torrent client automation.

---

### Royal Road Sync (FanFicFare)

| Attribute | Value |
| :--- | :--- |
| **Stack Directory** | `books/` |
| **Container Name** | `royalroad-sync` |
| **Host / Network Binding** | Internal `homelab` bridge only (No exposed host ports) |
| **Internal Container Port**| N/A (Background Daemon) |
| **LAN Address** | None |
| **WAN Address** | Outbound HTTPS for chapter scraping |
| **Persistent Data Path** | `${DOCKER_DATA_DIR}/royalroad/data` |
| **Associated Secrets** | None |

* **Role & Capabilities**: Background automation container compiling Royal Road web serials into EPUB files using FanFicFare. Polls tracked story URLs every 4 hours, downloads newly published chapters incrementally, and outputs updated EPUBs into Calibre-Web's import folder.
* **Network & Access**: Internal bridge network with standard outbound internet egress.
* **Storage & Volume Mappings**: Mounts `${DOCKER_DATA_DIR}/royalroad/data:/config` containing `stories.txt` and FanFicFare cache, and `${MEDIA_DIR}/books/import:/import` for outputting compiled EPUB files.
* **Dependencies & Interconnections**: Outputs compiled EPUBs to `/volume1/media/books/import` where Calibre-Web or Readarr can ingest them.
