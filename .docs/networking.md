# Dual-Ingress Networking and Security Architecture

This document specifies the dual-ingress topology, Docker subnets, IP assignments, split DNS routing, TLS certificate management, and edge security hardening for the homelab.

---

## 1. Dual-Ingress Architecture Overview

Ingress traffic is strictly segmented into two non-overlapping pillars. Public internet traffic reaches media services exclusively through Cloudflare Zero Trust, while private administrative traffic traverses the Tailscale WireGuard mesh:

```text
[ Internet Client ] ---> Cloudflare Edge ---> [ Cloudflare Tunnel ] ---+
                                                                       |
[ Remote Phone/PC ] ---> Tailscale Mesh  ---> [ Tailscale Router ] ----+---> [ Nginx Proxy Manager ] ---> [ Backend Stacks ]
                                                                       |     (192.168.0.4 / turing)      (192.168.255.0/24)
[ Local LAN Client] ---------------------------------------------------+
```

### Pillar 1: Public Web Ingress (`*.kamaka.tech`)
* **Outbound-Only Tunnel (`cloudflared`)**: Connects outbound over QUIC / HTTP/2 to Cloudflare edge data centers. Does not require port forwarding on the residential gateway and operates transparently behind Carrier-Grade NAT (CGNAT).
* **Wildcard Ingress**: Public Hostname `*.kamaka.tech` forwards down the tunnel to `https://nginx:443` (TLS No Verify enabled, Origin Server Name `jellyfin.kamaka.tech`).
* **Reverse Proxy Termination**: Nginx Proxy Manager inspects the SNI / Host header:
  * `jellyfin.kamaka.tech` routes to `jellyfin:8096`.
  * `recipes.kamaka.tech` routes to `tandoor:8050`.
  * Unmapped subdomains terminate at NPM's default host returning `404 Not Found`.

### Pillar 2: Private Admin Ingress (`*.turing.home`)
* **Tailscale Subnet Router (`tailscale`)**: Dual-homed on `external_npm` (`192.168.0.5`) and `homelab` bridge (`192.168.255.0/24`). Advertises `192.168.0.0/24` with SNAT masquerading (`--snat-subnet-routes=true`).
* **Subnet Access Control (`192.168.0.0/16`)**: Every internal `*.turing.home` virtual host enforces:
  ```nginx
  allow 192.168.0.0/16;
  allow 127.0.0.1;
  deny all;
  ```
  Requests originating from the Tailscale mesh arrive bearing source IP `192.168.0.5` and are allowed. WAN requests targeting `.turing.home` are dropped with `HTTP 403 Forbidden`.
* **UGOS Portal Macvlan Bypass (`nas.turing.home`)**: Linux kernel macvlan isolation prevents macvlan child `192.168.0.5` from communicating directly with host `192.168.0.3`. Access is solved cleanly by routing `https://nas.turing.home` through NPM, which forwards across the `homelab` bridge directly to `https://192.168.255.1:9443`.

---

## 2. Subnets and Docker Networks

| Network Name | Driver / Type | Subnet CIDR | Gateway | Parent Interface | Operational Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Physical LAN** | Physical Ethernet | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Primary local network for physical NAS host, router, and client devices |
| **Tailscale Overlay** | WireGuard Mesh | `100.64.0.0/10` | N/A | Subnet Router | Encrypted peer-to-peer overlay network connecting remote devices to LAN |
| **`homelab`** | Docker `bridge` | `192.168.255.0/24` | `192.168.255.1` | `br-*` | Isolated container bridge linking Nginx Proxy Manager with backend services |
| **`external_npm`** | Docker `macvlan` | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Assigns dedicated LAN IPs to NPM (`192.168.0.4`) and Tailscale (`192.168.0.5`) |

---

## 3. LAN Host & Static IP Assignments

| Hostname / Domain | IP Address | Interface Binding | Operational Role & Routing Behavior |
| :--- | :--- | :--- | :--- |
| **Gateway / Router** | `192.168.0.1` | Physical Gateway | Residential DHCP server; authoritative for `.home` hostnames; distributes Pi-hole as DNS |
| **Pi-hole** | `192.168.0.2` | Dedicated Appliance | Local DNS resolver; defines CNAME records: `*.turing.home` -> `turing.home` (`192.168.0.4`) |
| **`nas.home`** | `192.168.0.3` | UGREEN NAS (`eth0`) | Host OS management portal (`https://nas.home:9443`) and emergency Dockge port (`8010`) |
| **`turing.home`** | `192.168.0.4` | `external_npm` macvlan | Nginx Proxy Manager dedicated LAN IP; terminates HTTP (`80`), HTTPS (`443`), and Admin UI (`81`) |
| **`homelab` (Tailscale)** | `192.168.0.5` | `external_npm` macvlan | Tailscale Subnet Router; advertises `192.168.0.0/24` to Tailscale WireGuard mesh |

---

## 4. Split DNS Configuration

To ensure seamless access to `<service>.turing.home` from both local Wi-Fi and remote cellular connections:

1. **Local LAN Clients**:
   * Router (`192.168.0.1`) hands out `192.168.0.2` (Pi-hole) as primary DNS server and `.home` as search domain.
   * Pi-hole defines wildcard CNAMEs pointing `*.turing.home` to `turing.home` (`192.168.0.4`).
2. **Remote Tailscale Clients**:
   * In Tailscale Admin Console -> **DNS -> Nameservers -> Add nameserver -> Custom**:
     * Nameserver IP: `192.168.0.2`
     * Enable **Restrict to search domain** and enter **`.home`**.
   * When remote devices request `<service>.turing.home`, Tailscale forwards the query across the subnet router to Pi-hole, returning `192.168.0.4`. All standard internet queries continue through local Wi-Fi/cellular DNS.

---

## 5. TLS & Certificate Management

### Combined Local Wildcard Certificate (`turing.home` & `nas.home`)
Eliminates browser security warnings across all internal services and the host NAS portal:
1. Generate `turing.key` and `turing.crt` (valid for 10 years covering `turing.home`, `*.turing.home`, `nas.home`, `*.nas.home`):
   ```bash
   cd ~/services/.configs/nginx
   ./generate-local-cert.sh
   ```
2. **Client Import**: Import `turing.crt` into your OS/browser Trusted Root Certification Authorities store.
3. **UGREEN NAS Import**: Under **Control Panel -> Security -> Certificate**, upload `turing.key` and `turing.crt` and set as default certificate.
4. **NPM Import**:
   * Open `https://proxy.turing.home` -> **SSL Certificates -> Add SSL Certificate -> Custom**.
   * Name: `Local Wildcard (turing.home + nas.home)`, Private Key: `turing.key`, Certificate: `turing.crt`.
   * Assign to all `*.turing.home` proxy hosts.

### Cloudflare Let's Encrypt Wildcard Certificate (`*.kamaka.tech`)
1. In NPM -> **SSL Certificates -> Add SSL Certificate -> Let's Encrypt**.
2. Domains: `kamaka.tech`, `*.kamaka.tech`.
3. Check **Use a DNS Challenge** -> Provider: **Cloudflare**.
4. Credentials: `dns_cloudflare_api_token = <your-cloudflare-token>`.
5. Assign to external proxy hosts (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`).

---

## 6. Security Hardening Procedures

### External Jellyfin Hardening
* **Container Hardening**: Runs as non-root (`user: "1000:100"`), drops all capabilities (`cap_drop: [ALL]`), sets `security_opt: [no-new-privileges:true]`, and mounts media read-only (`:ro`).
* **Reverse Proxy Endpoint Blocking**: The NPM proxy host config ([proxy_host/3.conf](file:///home/brandon/services/.configs/nginx/nginx/proxy_host/3.conf)) returns `HTTP 403 Forbidden` on `/swagger`, `/api-docs`, and `/metrics`.
* **Cloudflare Video Cache Bypass**:
  1. Cloudflare Dashboard -> `kamaka.tech` -> **Caching -> Cache Rules -> Create Rule**.
  2. Rule Name: `Bypass Jellyfin Video Cache`.
  3. Match: `Hostname equals jellyfin.kamaka.tech`.
  4. Action: **Bypass cache**.
* **Server UI Settings**:
  * **Known Proxies**: Add `192.168.255.0/24` (or `nginx`) under **Dashboard -> Networking**.
  * **Disable Remote Admin**: In user profile, uncheck **Allow remote connections to this server**.
  * **Lockout**: Set **Invalid login attempts before lockout** to `3` or `5`.
