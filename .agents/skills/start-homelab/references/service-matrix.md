# Homelab Service Catalog & Selection Matrix

When scaffolding a new homelab instance using `start-homelab`, use this catalog to classify services into **Keep (Immediate)**, **Defer (Disabled)**, or **Remove (Pruned)**.

| Stack Directory | Services Included | Category | Primary Dependencies | Target Ports / Routing | Resource Profile |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `postgres` | `postgresql` | Database | None | Internal (`postgresql:5432`) | Low RAM (128–256MB), persistent storage |
| `caddy` | `caddy` | Ingress Proxy | LAN macvlan (`external_npm`) | Subdomains (`*.kamaka.tech`, `*.kamakakai.com`) | Low RAM (64MB), high throughput |
| `tailscale` | `tailscale` | VPN Mesh | None (host `/dev/net/tun`) | Tailnet Mesh (`100.64.0.0/10`) | Minimal (30MB RAM) |
| `vpn-bridge` | `vpn-bridge-pia`, `vpn-bridge-tailscale` | Privacy Exit Node | PIA VPN credentials | Tailscale Exit Node | Low RAM (64MB) |
| `homepage` | `homepage` | Dashboard | Docker socket (read-only) | `homepage.kamaka.tech` | Low RAM (80MB) |
| `jellyfin` | `jellyfin` | Media Streaming | Media volume (`:ro`), `/dev/dri` | `jellyfin.kamaka.tech`, UDP 7359 | Moderate to High (512MB–2GB+ during transcode) |
| `torrent` | `wireguard-pia`, `qbittorrent`, `cleanuparr` | Torrents & VPN | VPN credentials, download volume | `torrent.kamaka.tech`, PIA forward port | Moderate RAM (256MB–1GB with write cache) |
| `media` | `jellyfin`, `seerr`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr` | Media Automation | `qbittorrent`, indexers | `radarr.kamaka.tech`, `sonarr.kamaka.tech`, `prowlarr.kamaka.tech` | Moderate RAM (1–2GB across all 4 containers) |
| `seerr` | `seerr` | Request Portal | `jellyfin`, `sonarr-radarr` | `seerr.kamaka.tech` | Low to Moderate (256MB RAM) |
| `mealie` | `mealie` | Recipes & Meal Prep | SQLite volume | `recipes.kamaka.tech` | Low to Moderate (150MB RAM) |
| `cloudflared` | `cloudflared` | Cloud Ingress | Cloudflare Tunnel Token | Outbound TLS tunnel | Minimal (50MB RAM) |

---

## Service Selection Profiles

### Profile A: Full Media & Automation Stack
- **Target**: Users wanting automated media downloading, streaming, requests, and recipe management.
- **Keep**: All 11 stacks.

### Profile B: Lightweight Media Server Only
- **Target**: Users wanting local media playback without automated torrenting or VPNs.
- **Keep**: `caddy`, `tailscale`, `homepage`, `jellyfin`.
- **Remove**: `torrent`, `media`, `mesh`, `productivity`.

### Profile C: Privacy & Remote Access Hub
- **Target**: Users wanting a dedicated travel VPN exit node, secure subnet routing, and dashboard.
- **Keep**: `caddy`, `tailscale`, `vpn-bridge`, `homepage`, `cloudflared`.
- **Remove**: Media and downloader stacks (`jellyfin`, `torrent`, `media`, `productivity`).

### Profile D: Self-Hosted Home Management
- **Target**: Recipe management, private cloud sync, dashboard, and secure routing.
- **Keep**: `mealie`, `caddy`, `tailscale`, `homepage`.
- **Remove**: All media and download services.
