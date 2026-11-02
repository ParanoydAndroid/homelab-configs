# Homelab Service Catalog & Selection Matrix

When scaffolding a new homelab instance using `start-homelab`, use this catalog to classify services into **Keep (Immediate)**, **Defer (Disabled)**, or **Remove (Pruned)**.

| Stack Directory | Services Included | Category | Primary Dependencies | Target Ports / Routing | Resource Profile |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `postgres` | `postgresql` | Database | None | Internal (`postgresql:5432`) | Low RAM (128–256MB), persistent storage |
| `nginx` | `nginx` (NPM) | Ingress Proxy | LAN macvlan (`external_npm`) | Subdomains (`*.home`, `*.domain`) | Low RAM (128MB), network bound |
| `tailscale` | `tailscale` | VPN Mesh | None (host `/dev/net/tun`) | Tailnet Mesh (`100.64.0.0/10`) | Minimal (30MB RAM) |
| `vpn-bridge` | `vpn-bridge-pia`, `vpn-bridge-tailscale` | Privacy Exit Node | PIA VPN credentials | Tailscale Exit Node | Low RAM (64MB) |
| `homepage` | `homepage` | Dashboard | Docker socket (read-only) | `homepage.turing.home` | Low RAM (80MB) |
| `jellyfin` | `jellyfin` | Media Streaming | Media volume (`:ro`), `/dev/dri` | `jellyfin.turing.home`, UDP 7359 | Moderate to High (512MB–2GB+ during transcode) |
| `qbittorrentvpn` | `wireguard-pia`, `qbittorrentvpn` | Torrents & VPN | VPN credentials, download volume | `torrent.turing.home`, PIA forward port | Moderate RAM (256MB–1GB with write cache) |
| `sonarr-radarr` | `radarr`, `sonarr`, `prowlarr`, `flaresolverr` | Media Automation | `qbittorrentvpn`, indexers | `radarr.turing.home`, `sonarr.turing.home`, `prowlarr.turing.home` | Moderate RAM (1–2GB across all 4 containers) |
| `seerr` | `seerr` | Request Portal | `jellyfin`, `sonarr-radarr` | `seerr.turing.home` | Low to Moderate (256MB RAM) |
| `tandoor` | `tandoor` | Recipes & Meal Prep | `postgres` (or SQLite) | `recipes.turing.home` | Low to Moderate (256MB RAM) |
| `cloudflared` | `cloudflared` | Cloud Ingress | Cloudflare Tunnel Token | Outbound TLS tunnel | Minimal (50MB RAM) |

---

## Service Selection Profiles

### Profile A: Full Media & Automation Stack
- **Target**: Users wanting automated media downloading, streaming, requests, and recipe management.
- **Keep**: All 11 stacks.

### Profile B: Lightweight Media Server Only
- **Target**: Users wanting local media playback without automated torrenting or VPNs.
- **Keep**: `nginx`, `tailscale`, `homepage`, `jellyfin`.
- **Remove**: `qbittorrentvpn`, `sonarr-radarr`, `seerr`, `vpn-bridge`, `tandoor`, `postgres`.

### Profile C: Privacy & Remote Access Hub
- **Target**: Users wanting a dedicated travel VPN exit node, secure subnet routing, and dashboard.
- **Keep**: `nginx`, `tailscale`, `vpn-bridge`, `homepage`, `cloudflared`.
- **Remove**: Media and downloader stacks (`jellyfin`, `qbittorrentvpn`, `sonarr-radarr`, `seerr`, `tandoor`, `postgres`).

### Profile D: Self-Hosted Home Management
- **Target**: Recipe management, private cloud sync, dashboard, and secure routing.
- **Keep**: `postgres`, `tandoor`, `nginx`, `tailscale`, `homepage`.
- **Remove**: All media and download services.
