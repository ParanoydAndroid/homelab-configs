# VPN & Remote Access Provider Adaptation Guide

This reference details how to adapt `qbittorrentvpn` and `vpn-bridge` to different commercial VPN providers and ingress mechanisms.

---

## 1. Commercial VPN Providers

### Private Internet Access (PIA) - Native Image Default
- **Image**: `thrnz/docker-wireguard-pia:latest`
- **Dynamic Port Forwarding**: Native NextGen API with 15-minute rebind loop.
- **Port Callback**: Invokes `/set-qbt-port.sh <port>` to update qBittorrent listen port.
- **Regions**: Requires regions supporting port forwarding (`ca_ontario`, `ca_toronto`, `ca_montreal`).

### ProtonVPN (WireGuard)
- **Container Architecture**:
  - Image: `ghcr.io/qdm12/gluetun` (multi-provider VPN client).
  - Environment variables:
    ```yaml
    VPN_SERVICE_PROVIDER: protonvpn
    VPN_TYPE: wireguard
    WIREGUARD_PRIVATE_KEY: ${VPN_WIREGUARD_PRIVATE_KEY}
    WIREGUARD_ADDRESSES: ${VPN_WIREGUARD_IP}
    VPN_PORT_FORWARDING: "on"
    VPN_PORT_FORWARDING_PROVIDER: protonvpn
    ```
- **Port Forwarding**: ProtonVPN provides dynamic port forwarding via NAT-PMP; Gluetun exposes port in `/tmp/gluetun/forwarded_port`.

### Mullvad (WireGuard)
- **Container Architecture**:
  - Image: `ghcr.io/qdm12/gluetun` or native `wireguard-tools`.
  - Environment variables:
    ```yaml
    VPN_SERVICE_PROVIDER: mullvad
    VPN_TYPE: wireguard
    WIREGUARD_PRIVATE_KEY: ${VPN_WIREGUARD_PRIVATE_KEY}
    WIREGUARD_ADDRESSES: ${VPN_WIREGUARD_IP}
    SERVER_COUNTRIES: Canada
    ```
  - *Note*: Mullvad discontinued dynamic port forwarding in 2023. qBittorrent will operate in passive/inbound-closed mode (seeding and downloading still function via DHT/trackers, but incoming unsolicited peer handshakes are blocked).

### AirVPN (WireGuard)
- **Port Forwarding**: Static port forwarding configured through AirVPN client control panel.
- **Port Callback**: Inlined static port in `.env` (`PORT_FORWARDING=0`, `VPN_STATIC_PORT=12345`).

---

## 2. Remote Access & Ingress Providers

### Caddy Docker Proxy (Default)
- **Model**: Declarative reverse proxy on macvlan `external_npm` (`192.168.0.4`). Routes discovered dynamically via Compose labels (`caddy=host`, `caddy.reverse_proxy={{upstreams port}}`).
- **Certificates**: Automated Let's Encrypt DNS-01 challenges via Cloudflare DNS module (`caddy-dns/cloudflare`).
- **Client File Delivery**: Native HTTPS download endpoint at `https://download.<domain>/` backed by `${DOCKER_DATA_DIR}/caddy/downloads`.

### Alternative: Nginx Proxy Manager (GUI-Managed)
- **Model**: Imperative reverse proxy via web UI (`http://192.168.0.4:81`).
- **Data Persistence**: Uses SQLite database at `${DOCKER_DATA_DIR}/nginx/data/database.sqlite`.
- **Conversion Guide**:
  1. Replace `caddy` service in `ingress/compose.yml` with `jc21/nginx-proxy-manager:latest`.
  2. Map volumes `${DOCKER_DATA_DIR}/nginx/data:/data` and `${DOCKER_DATA_DIR}/nginx/letsencrypt:/etc/letsencrypt`.
  3. Strip `caddy.*` labels from backend Compose files.
  4. Access web UI on port `81` to configure proxy hosts and Cloudflare DNS-01 certificates manually.

### Cloudflare Zero Trust Tunnels (`cloudflared`) - Default Public Egress
- **Model**: Outbound HTTPS tunnel to Cloudflare Edge. Zero open inbound ports required on home router.
- **Auth**: `CLOUDFLARE_TUNNEL_TOKEN`.
- **Public Domain**: `*.kamakakai.com` (or custom public domain).
- **Hardening**: Reverse proxy blocks diagnostic endpoints (`/swagger`, `/api-docs`, `/metrics`) from external hosts.

### Tailscale Funnel / Subnet Routing
- **Model**: WireGuard-based mesh networking.
- **Auth**: `TS_AUTHKEY` (one-time pre-auth key).
- **Public Ingress**: Optional `tailscale funnel 443` for public access, or private tailnet access for mobile devices without exposing any public domain.

### Dynamic DNS (DuckDNS) + Let's Encrypt
- **Model**: Port forward 80/443 on WAN router to reverse proxy IP (`192.168.0.4`).
- **Certificates**: Automated HTTP-01 or DNS-01 challenges via DuckDNS API.
