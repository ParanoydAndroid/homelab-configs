# Homelab Service Catalog & Selection Matrix

When scaffolding a new homelab instance using `start-homelab`, use this catalog to classify services into **Keep (Immediate)**, **Defer (Disabled)**, or **Remove (Pruned)**.

| Stack Directory | Services Included | Category | Primary Dependencies | Target Ports / Routing | Resource Profile |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `ingress` | `caddy`, `cloudflared` | Ingress Proxy & Cloud Tunnel | LAN macvlan (`external_npm` on `192.168.0.4`), Docker socket, Cloudflare Tunnel Token | Subdomains (`*.kamaka.tech`, `*.kamakakai.com`) | Low RAM (~100MB), high throughput |
| `dashboard` | `homepage` | Dashboard | Docker socket (read-only) | `homepage.kamaka.tech` | Low RAM (~80MB) |
| `mesh` | `tailscale`, `vpn-bridge-pia`, `vpn-bridge-tailscale` | Privacy Exit Node & VPN Mesh | PIA VPN credentials, Tailscale auth key, host `/dev/net/tun` | Tailnet Mesh (`100.64.0.0/10`), Subnet Router (`192.168.0.0/24`), Exit Node (`vpn-bridge`) | Low RAM (~100MB) |
| `media` | `jellyfin`, `seerr`, `radarr`, `sonarr`, `prowlarr`, `flaresolverr` | Media Automation & Streaming | Media volume (`${MEDIA_DIR}`), GPU (`/dev/dri`), `qbittorrent`, indexers | `jellyfin.kamaka.tech`, `seerr.kamaka.tech`, `radarr.kamaka.tech`, `sonarr.kamaka.tech`, `prowlarr.kamaka.tech`, UDP 7359 | Moderate to High (1.5GB–3GB+ during transcode) |
| `books` | `calibre-web`, `bindery`, `royalroad-sync` | Book Catalog & Automation | Books volume (`${MEDIA_DIR}/books`), `prowlarr`, `qbittorrent` | `books.kamaka.tech`, `bindery.kamaka.tech`, `readarr.kamaka.tech` | Low to Moderate (~300MB RAM) |
| `torrent` | `wireguard-pia`, `qbittorrent`, `cleanuparr` | Torrents & VPN Queue Management | VPN credentials, download volume, NVMe scratch buffer | `torrent.kamaka.tech`, `cleanuparr.kamaka.tech`, PIA forward port | Moderate RAM (300MB–1GB with write cache) |
| `productivity` | `mealie` | Recipes & Home Management | SQLite volume | `recipes.kamaka.tech`, `recipes.kamakakai.com`, `mom.kamakakai.com` | Low to Moderate (~150MB RAM) |

---

## Service Selection Profiles

### Profile A: Full Media & Automation Stack
- **Target**: Users wanting automated media downloading, streaming, e-books, requests, and recipe management.
- **Keep**: All 7 stacks (`books`, `dashboard`, `ingress`, `media`, `mesh`, `productivity`, `torrent`).

### Profile B: Lightweight Media Server Only
- **Target**: Users wanting local media playback without automated torrenting or VPN exit nodes.
- **Keep**: `ingress`, `dashboard`, `mesh`, `media`.
- **Remove**: `torrent`, `books`, `productivity`.

### Profile C: Privacy & Remote Access Hub
- **Target**: Users wanting a dedicated travel VPN exit node, secure subnet routing, cloud ingress, and dashboard.
- **Keep**: `ingress`, `dashboard`, `mesh`.
- **Remove**: `media`, `books`, `torrent`, `productivity`.

### Profile D: Self-Hosted Home Management
- **Target**: Recipe management, private cloud sync, dashboard, and secure routing.
- **Keep**: `ingress`, `dashboard`, `mesh`, `productivity`.
- **Remove**: `media`, `books`, `torrent`.
