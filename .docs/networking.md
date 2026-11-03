# Dual-Ingress Networking and Security Architecture

This document specifies the dual-ingress topology, Docker subnets, IP assignments, split DNS routing, TLS certificate management, edge security hardening, and alternative reverse proxy configurations for the homelab.

---

## 1. Dual-Ingress Architecture Overview

Ingress traffic is strictly segmented into two non-overlapping pillars. Public internet traffic reaches media and recipe services exclusively through Cloudflare Zero Trust, while private homelab traffic traverses the local LAN and Tailscale WireGuard mesh:

```text
[ Internet Client ] ---> Cloudflare Edge ---> [ Cloudflare Tunnel ] ---+
                                                                       |
[ Remote Phone/PC ] ---> Tailscale Mesh  ---> [ Tailscale Router ] ----+---> [ Caddy Proxy ] ------------> [ Backend Stacks ]
                                              (192.168.0.5 / homelab)  |     (192.168.0.4 / macvlan)        (192.168.255.0/24)
                                                                       |
[ Remote Mobile/PC] ---> Tailscale Mesh  ---> [ VPN Bridge Exit Node ] ----> [ PIA WireGuard (wg0) ] -----> [ Public Internet ]
                                              (vpn-bridge-tailscale)         (vpn-bridge-pia)
                                                                       |
[ Local LAN Client] ---------------------------------------------------+
```

### Pillar 1: Public Web Ingress (`*.kamakakai.com`)
* **Outbound-Only Tunnel (`cloudflared`)**: Connects outbound over QUIC / HTTP/2 to Cloudflare edge data centers. Does not require port forwarding on the residential gateway and operates transparently behind Carrier-Grade NAT (CGNAT).
* **Tunnel Routing**: Public Hostnames in Cloudflare Zero Trust (`jellyfin.kamakakai.com`, `mealie.kamakakai.com`, `recipes.kamakakai.com`, `mom.kamakakai.com`) forward down the tunnel to `https://caddy:443` with `No TLS Verify` enabled.
* **Caddy Reverse Proxy**: Caddy Docker Proxy inspects the incoming SNI / Host header, matches container labels, and reverse proxies over the internal `homelab` bridge network (`192.168.255.0/24`).
* **Cloudflare CDN Cache Bypass (Streaming Optimization)**:
  Media streaming through Cloudflare Tunnel should bypass edge caching to prevent stream buffering, latency, and compliance issues with large video chunk caching:
  1. Cloudflare Dashboard -> `kamakakai.com` -> **Caching -> Cache Rules -> Create Rule**.
  2. Rule Name: `Bypass Jellyfin Video Cache`.
  3. Match: `Hostname equals jellyfin.kamakakai.com`.
  4. Action: **Bypass cache**.

### Pillar 2: Private Homelab Ingress (`*.kamaka.tech`)
* **Pi-hole v6 Wildcard DNS**: Local DNS resolver injects `address=/kamaka.tech/192.168.0.4` directly into Pi-hole FTL, resolving all internal subdomains to Caddy without manual per-host record management.
* **Dedicated Macvlan LAN IP (`192.168.0.4`)**: Caddy binds to `192.168.0.4` on `eth0` via Docker macvlan (`external_npm`), isolating reverse-proxied traffic from the host OS portal on `192.168.0.3`.
* **Automated DNS-01 ACME Certificates**: Caddy automatically provisions and renews trusted Let's Encrypt certificates across all subdomains using its Cloudflare DNS module (`caddy-dns/cloudflare`), guaranteeing green browser padlocks without deploying internal root CAs.
* **UGOS Portal Reverse Proxy (`nas.kamaka.tech`)**: Macvlan isolation prevents macvlan children from reaching the host directly. Caddy routes `https://nas.kamaka.tech` across the Docker bridge to `https://192.168.255.1:9443` with `tls_insecure_skip_verify`.
* **Client File Delivery (`download.kamaka.tech`)**: Staged files in `${DOCKER_DATA_DIR}/caddy/downloads` are served over HTTPS with an interactive HTML directory index (`file_server browse`), enabling direct mobile and desktop downloads.

### Pillar 3: Secure VPN Bridge Egress (`vpn-bridge`)
* **Decoupled Privacy Exit Node**: Remote mobile and desktop devices route public internet traffic through the private Tailscale WireGuard mesh node `vpn-bridge`.
* **Network Namespace Sharing**: The Tailscale container (`vpn-bridge-tailscale`) runs inside the network namespace of the PIA container (`vpn-bridge-pia` via `network_mode: "service:vpn"`).
* **WireGuard NAT Egress**: The PIA container establishes an encrypted WireGuard tunnel (`wg0`) to US server regions (`PIA_REGION: us_east,us_chicago,us_nyc`), enables IP forwarding, sets forward interface `FWD_IFACE: tailscale+`, and applies NAT masquerading (`-o wg0 -j MASQUERADE`).
* **Traffic Isolation**: Protects mobile clients on untrusted public Wi-Fi networks without exposing the homelab residential ISP IP or interfering with local LAN subnet routing.

---

## 2. Subnets and Docker Networks

| Network Name | Driver / Type | Subnet CIDR | Gateway | Parent Interface | Operational Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Physical LAN** | Physical Ethernet | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Primary local network for physical NAS host, router, and client devices |
| **Tailscale Overlay** | WireGuard Mesh | `100.64.0.0/10` | N/A | Subnet Router | Encrypted peer-to-peer overlay network connecting remote devices to LAN |
| **`homelab`** | Docker `bridge` | `192.168.255.0/24` | `192.168.255.1` | `br-*` | Isolated container bridge linking Caddy with backend services |
| **`external_npm`** | Docker `macvlan` | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Assigns dedicated LAN IPs to Caddy (`192.168.0.4`) and Tailscale (`192.168.0.5`) |

---

## 3. LAN Host & Static IP Assignments

| Hostname / Domain | IP Address | Interface Binding | Operational Role & Routing Behavior |
| :--- | :--- | :--- | :--- |
| **Gateway / Router** | `192.168.0.1` | Physical Gateway | Residential DHCP server; authoritative for router; distributes Pi-hole as DNS |
| **Pi-hole** | `192.168.0.2` | Dedicated Appliance | Local DNS resolver; wildcard `address=/kamaka.tech/192.168.0.4` |
| **`nas.home`** | `192.168.0.3` | UGREEN NAS (`eth0`) | Host OS management portal (`https://nas.home:9443`) and emergency Dockge port (`8010`) |
| **`caddy` (Macvlan)** | `192.168.0.4` | `external_npm` macvlan | Caddy dedicated LAN IP; terminates HTTP (`80`) and HTTPS (`443`) |
| **`homelab` (Tailscale)** | `192.168.0.5` | `external_npm` macvlan | Tailscale Subnet Router; advertises `192.168.0.0/24` to Tailscale WireGuard mesh |

---

## 4. Split DNS Configuration

1. **Local LAN Clients**:
   * Router (`192.168.0.1`) hands out `192.168.0.2` (Pi-hole) as primary DNS server.
   * Pi-hole defines wildcard DNS line in `/etc/pihole/pihole.toml`:
     ```toml
     [misc]
     dnsmasq_lines = ["address=/kamaka.tech/192.168.0.4"]
     ```
   * Applied via CLI: `sudo pihole-FTL --config misc.dnsmasq_lines '["address=/kamaka.tech/192.168.0.4"]'`.
2. **Remote Tailscale Clients**:
   * In Tailscale Admin Console -> **DNS -> Nameservers -> Add nameserver -> Custom**:
     * Nameserver IP: `192.168.0.2`
     * Enable **Restrict to search domain** and enter **`kamaka.tech`**.
   * When remote devices query `*.kamaka.tech`, Tailscale routes the query across the subnet router to Pi-hole, returning `192.168.0.4`.

---

## 5. Security Hardening Procedures

### Container Hardening
* All web applications run as non-root (`user: "${PUID}:${PGID}"`), drop all Linux capabilities (`cap_drop: [ALL]`), set `security_opt: [no-new-privileges:true]`, and mount storage volumes read-only (`:ro`) wherever write access is unneeded.

### Caddy Ingress Hardening
* **Local Subnet Isolation**: Management endpoints (`dockge`, `nas`, *arr services) are restricted to local LAN (`192.168.0.0/16`) and Tailscale (`100.64.0.0/10`) clients.
* **Jellyfin Hardening**: Diagnostic paths (`/metrics`, `/swagger`, `/api-docs`) return `HTTP 403 Forbidden` via Caddy snippets.
* **Server UI Settings**:
  * **Known Proxies**: Add `192.168.255.0/24` (or `caddy`) in Jellyfin networking dashboard.
  * **Disable Remote Admin**: In user profile, uncheck **Allow remote connections to this server**.
  * **Lockout**: Set **Invalid login attempts before lockout** to `3` or `5`.

---

## 6. Client File Delivery (`download.kamaka.tech`)

For transfer of generated archives, database backups, or exported media from the homelab directly to client devices (smartphones, tablets, remote laptops):
1. Files are placed in `${DOCKER_DATA_DIR}/caddy/downloads/<filename>` on NVMe.
2. Caddy exposes the directory at `https://download.kamaka.tech/` with automated TLS and directory browsing (`file_server browse`).
3. Clients on local Wi-Fi or Tailscale download directly in browser without Termux or SFTP sandboxing friction.

---

## 7. Alternative Reverse Proxy: Nginx Proxy Manager (NPM)

If a maintainer prefers a graphical web UI over Caddy's declarative Docker labels, Nginx Proxy Manager can be deployed as an alternative:

### Architectural Differences
* **NPM**: Uses SQLite database (`/data/database.sqlite`), an admin web GUI on port `81` (`http://192.168.0.4:81`), and imperative host creation. Certificates must be requested through the UI.
* **Caddy**: Fully declarative via Docker labels in `compose.yml` (`caddy=host`, `caddy.reverse_proxy={{upstreams port}}`), native DNS-01 Let's Encrypt automation, and zero database overhead.

### Conversion Steps to Restore NPM
1. **Compose Manifest (`ingress/compose.yml`)**:
   Replace the `caddy` service definition with:
   ```yaml
   services:
     nginx:
       image: jc21/nginx-proxy-manager:latest
       container_name: nginx
       hostname: nginx
       restart: unless-stopped
       mac_address: 2E:50:8F:7A:C4:12
       environment:
         PUID: ${PUID:?See env.example for default.}
         PGID: ${PGID:?See env.example for default.}
         TZ: ${TZ:?See env.example for default.}
         DISABLE_IPV6: "true"
       volumes:
         - ${DOCKER_DATA_DIR:?See env.example for default.}/nginx/data:/data
         - ${DOCKER_DATA_DIR:?See env.example for default.}/nginx/letsencrypt:/etc/letsencrypt
       networks:
         homelab:
           aliases:
             - services
         external_npm:
           ipv4_address: ${NPM_IPV4_ADDRESS:?See env.example for default.}
   ```
2. **Remove Caddy Labels**:
   Remove `caddy=*` and `caddy.reverse_proxy=*` labels from backend `compose.yml` files.
3. **Configure Proxy Hosts in NPM Admin UI**:
   * Access `http://192.168.0.4:81` (default login: `admin@example.com` / `changeme`).
   * Add Proxy Hosts pointing each subdomain to its respective container hostname and port (e.g. `jellyfin` -> `8096`, `mealie` -> `9000`).
   * Under **SSL**, request Let's Encrypt certificates using the Cloudflare DNS challenge with your API token.
