# Engineering Implementation Plan: Dedicated Tailscale PIA Exit Node Stack (vpn-bridge) & Env Defaults Standardization

## 1. Executive Summary & Objective

This engineering initiative delivers two focused improvements to the homelab:
1. **Dedicated Exit Node Stack (`vpn-bridge`)**: Deploys an independent Docker Compose stack pairing a Private Internet Access (PIA) WireGuard client with a Tailscale node (`vpn-bridge`) advertising `--advertise-exit-node`. This enables client devices on the Tailnet to route public internet traffic securely through a domestic US PIA endpoint without leaking the homelab ISP IP, while preserving local LAN routing to homelab services (`192.168.0.0/24` and `*.turing.home`) via the existing `tailscale` subnet router.
2. **Environment Variable Handling Overhaul**: Transitions the homelab from brittle inline fallbacks (`${VAR:-default}`) to a clean separation of concerns:
   - **Fixed Stack Invariants**: Directly inlined in `compose.yml` (e.g. `HOMEPAGE_ALLOWED_HOSTS`, `LOG_LEVEL`, `TS_EXTRA_ARGS`).
   - **Runtime Host & Secret Variables**: Declared exclusively in `.env.example` templates and required in `compose.yml` using `${VAR:?VAR is required (see .env.example for defaults)}`.
   - **Zero-Touch Secret Auto-Generation**: Automatic generation of arbitrary cryptographic keys (e.g. Tandoor Django `SECRET_KEY`) directly inside `.scripts/env-tools.sh` during environment synchronization.

---

## 2. Architecture & Data Plane

### 2.1 Packet Flow & Network Namespace Co-Location

By placing both the `vpn` (PIA WireGuard) and `tailscale` (Exit Node) services in the **exact same Docker network namespace** (`network_mode: "service:vpn"`), packet routing between the two tunnels occurs entirely in Linux kernel memory without cross-container network hops.

```
 [ Client Device (Phone/Laptop) ]
                 │
                 ├──► Destination in 192.168.0.0/24 (LAN/Homelab)
                 │    └──► Routed to Subnet Router (tailscale at 192.168.0.5) ──► Direct Local LAN
                 │
                 └──► Destination 0.0.0.0/0 (Public Internet)
                      └──► Routed to Exit Node (vpn-bridge)
                                │
   ┌────────────────────────────┼────────────────────────────────────────────────────────┐
   │ 'vpn-bridge' Shared Net    │ Namespace                                              │
   │                            ▼                                                        │
   │                   [ tailscale0 ] (Tailscale tunnel device)                          │
   │                            │                                                        │
   │                            │ Kernel Routing: Default gateway dev wg0                │
   │                            ▼                                                        │
   │                   [ iptables NAT: MASQUERADE -o wg0 ]                               │
   │                            │                                                        │
   │                            ▼                                                        │
   │                   [ wg0 Interface ] (PIA WireGuard tunnel)                          │
   └────────────────────────────┼────────────────────────────────────────────────────────┘
                                │
                                ▼
                       [ Public Internet ] (PIA US Egress IP)
```

### 2.2 Key Architectural Decisions

1. **Dedicated Stack (`vpn-bridge/compose.yml`)**:
   - Completely isolated from `qbittorrentvpn`. qBittorrent remains configured for Canadian incoming port forwarding without interference.
   - Completely isolated from `tailscale/compose.yml` (the LAN subnet router on `192.168.0.5`).
2. **US-Based Region Selection**:
   - Configured to low-latency US endpoints (`PIA_REGION=us_east,us_chicago,us_nyc` in `vpn-bridge/.env.example`).
   - Ensures domestic IP geolocation for mobile web browsing, streaming services, and online banking.
   - `PORT_FORWARDING: 0` (unnecessary for outbound web traffic).
3. **Native Transit Forwarding**:
   - Uses `thrnz/docker-wireguard-pia`'s native `FWD_IFACE=tailscale+` configuration with `net.ipv4.ip_forward=1`.
   - Automatically establishes `iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE` and bidirectional `FORWARD` acceptance between `tailscale0` and `wg0`.
4. **Tailscale Node Identity**:
   - Node hostname on Tailnet: `vpn-bridge`.
   - Inlined flag argument: `TS_EXTRA_ARGS: --advertise-exit-node --snat-subnet-routes=true --accept-dns=false`.

---

## 3. Environment Variable Division: Inlined vs. Exposed

### 3.1 Fixed Stack Invariants (Directly Inlined in `compose.yml`)
The following configuration parameters represent permanent architectural decisions of their respective stacks and will be **directly inlined** as literal strings in `compose.yml`:

* `HOMEPAGE_ALLOWED_HOSTS: homepage.turing.home,www.turing.home,turing.home,192.168.0.4` (tied to homelab domain & reverse proxy)
* `LOG_LEVEL: info` (in `seerr` and `sonarr-radarr` FlareSolverr)
* `LOG_HTML: "false"` (in `sonarr-radarr` FlareSolverr)
* `CAPTCHA_SOLVER: none` (FlareSolverr internal challenge solver module; verified as functional state in running container)
* `TS_EXTRA_ARGS: --snat-subnet-routes=true --accept-dns=false` (in `tailscale/compose.yml`)
* `TS_EXTRA_ARGS: --advertise-exit-node --snat-subnet-routes=true --accept-dns=false` (in `vpn-bridge/compose.yml`)
* `WEBUI_PORT: 8081` (internal bridge port for qBittorrent)
* `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=password` (bridge-isolated internal database credentials)

### 3.2 Runtime Environment & External Secrets (Exposed in `.env.example`)
Only parameters that depend on the physical host, storage topology, network interface, or external accounts are exposed:

1. **Root `.env.example` (Global Host Parameters)**:
   * `DOCKER_DATA_DIR=/volume2/docker`
   * `MEDIA_DIR=/volume1/media`
   * `DOCKGE_DIR=/opt/${USER}/dockge`
   * `DOCKGE_STACKS_DIR=/opt/${USER}/dockge/stacks`
   * `PUID=1000`
   * `PGID=100`
   * `TZ=America/New_York`
   * `EXTERNAL_NPM_SUBNET=192.168.0.0/24`
   * `EXTERNAL_NPM_GATEWAY=192.168.0.1`
   * `EXTERNAL_NPM_PARENT=eth0`
   * `NPM_IPV4_ADDRESS=192.168.0.4`
   * `TAILSCALE_IPV4_ADDRESS=192.168.0.5`
   * `BACKUP_RESTIC_REPO=/volume1/backups/homelab-docker`
   * `BACKUP_RETENTION_DAYS=30`

2. **Per-Stack `<stack>/.env.example` (External Credentials & Regional Selection)**:
   * `vpn-bridge`: `PIA_REGION=us_east,us_chicago,us_nyc`, `VPN_USER=`, `VPN_PASS=`, `TS_AUTHKEY=`
   * `qbittorrentvpn`: `VPN_USER=`, `VPN_PASS=`, `QBITTORRENT_PASSWORD=`
   * `tailscale`: `TS_AUTHKEY=`
   * `cloudflared`: `CLOUDFLARE_TUNNEL_TOKEN=`
   * `homepage`: `HOMEPAGE_VAR_PIHOLE_KEY=`
   * `jellyfin`: `JELLYFIN_API_KEY=`
   * `seerr`: `SEERR_API_KEY=`
   * `sonarr-radarr`: `RADARR_API_KEY=`, `SONARR_API_KEY=`, `PROWLARR_API_KEY=`
   * `tandoor`: `SECRET_KEY=`

### 3.3 Zero-Touch Secret Auto-Generation (`SECRET_KEY`)
In `.scripts/env-tools.sh`, within `init_and_sync_env()`, an existing validation hook checks for blank keys. For arbitrary cryptographic tokens like `SECRET_KEY`:
* If `SECRET_KEY` is blank in `tandoor/.env`, the script automatically generates a secure 50-character random cryptographic string (`LC_ALL=C tr -dc 'A-Za-z0-9!#%&*+,-./:;<=>?@^_~' < /dev/urandom | head -c 50`) and injects it via `upsert_env_var`.
* No manual user input is required; the key is established automatically upon initial environment sync.

---

## 4. Step-by-Step Implementation Plan

### Step 1: Environment Sync Hook Update & Secret Auto-Generation
* Edit [`.scripts/env-tools.sh`](file:///opt/brandon/dockge/stacks/.scripts/env-tools.sh):
  * In `init_and_sync_env()`: when validating stack keys, if `req_key == "SECRET_KEY"` and the current value is blank, auto-generate a random 50-char secret and save it to `<stack>/.env`.
* Confirm that no new scripts are created and all existing functions remain intact.

### Step 2: Compose Inlining & Required Syntax Transition
* **Inline Fixed Settings**:
  * In `homepage/compose.yml`: inline `HOMEPAGE_ALLOWED_HOSTS`.
  * In `seerr/compose.yml`: inline `LOG_LEVEL: info`.
  * In `sonarr-radarr/compose.yml`: inline `LOG_LEVEL: info`, `LOG_HTML: "false"`, `CAPTCHA_SOLVER: none`.
  * In `tailscale/compose.yml`: inline `TS_EXTRA_ARGS: --snat-subnet-routes=true --accept-dns=false`.
* **Standardize Required Variables**:
  * In all `compose.yml` files, replace `${VAR:-default}` with:
    `${VAR:?VAR is required (see .env.example for defaults)}`
  * Preserve optional auth keys as `${TS_AUTHKEY:-}`.
* Run `./homelab.sh setup` to verify environment synchronization and secret auto-generation.
* Verify all stacks parse cleanly using `docker compose config`.

### Step 3: Create `vpn-bridge` Stack
* Create directory `vpn-bridge/`.
* Create `vpn-bridge/.env.example`:
  ```bash
  VPN_USER=
  VPN_PASS=
  TS_AUTHKEY=
  PIA_REGION=us_east,us_chicago,us_nyc
  ```
* Create `vpn-bridge/compose.yml`:
  * `vpn` service (`thrnz/docker-wireguard-pia:latest`):
    * `container_name: vpn-bridge-pia`
    * `hostname: vpn-bridge`
    * `cap_add: [NET_ADMIN]`
    * `sysctls: [net.ipv4.ip_forward=1, net.ipv4.conf.all.src_valid_mark=1, net.ipv6.conf.all.disable_ipv6=1]`
    * `environment`:
      * `USER: ${VPN_USER:?VPN_USER is required (see .env.example for defaults)}`
      * `PASS: ${VPN_PASS:?VPN_PASS is required (see .env.example for defaults)}`
      * `LOC: ${PIA_REGION:?PIA_REGION is required (see .env.example for defaults)}`
      * `PORT_FORWARDING: 0`
      * `FIREWALL: 1`
      * `FWD_IFACE: tailscale+`
      * `LOCAL_NETWORK: 192.168.0.0/16,100.64.0.0/10`
    * `volumes`: `${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required (see .env.example for defaults)}/vpn-bridge/data/pia:/pia`
    * `networks`: `homelab`
  * `tailscale` service (`tailscale/tailscale:latest`):
    * `container_name: vpn-bridge-tailscale`
    * `hostname: vpn-bridge`
    * `network_mode: "service:vpn"`
    * `depends_on: { vpn: { condition: service_healthy } }`
    * `cap_add: [NET_ADMIN, NET_RAW]`
    * `devices: [/dev/net/tun:/dev/net/tun]`
    * `environment`:
      * `TS_AUTHKEY: ${TS_AUTHKEY:-}`
      * `TS_HOSTNAME: vpn-bridge`
      * `TS_STATE_DIR: /var/lib/tailscale`
      * `TS_USERSPACE: false`
      * `TS_EXTRA_ARGS: --advertise-exit-node --snat-subnet-routes=true --accept-dns=false`
    * `volumes`:
      * `${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required (see .env.example for defaults)}/vpn-bridge/data/tailscale:/var/lib/tailscale`
      * `/dev/net/tun:/dev/net/tun`
      * `tmpfs: [/tmp]`

### Step 4: Homelab Automation & Test Integration
* In `homelab.sh`: Add `"vpn-bridge"` to `STACKS` array (ordered after `tailscale` and before application stacks).
* In `.tests/suites/test_containers.sh`: Add `test_docker_up_vpn_bridge_pia` and `test_docker_up_vpn_bridge_tailscale`.
* In `.tests/suites/test_interconnect.sh`: Add `test_interconnect_vpn_bridge_routing` (verifying egress IP is PIA) and `test_interconnect_vpn_bridge_tailscale_state` (verifying `BackendState: Running`).

### Step 5: Documentation & Convention Governance
* Update [`.agents/rules/project-conventions.md`](file:///opt/brandon/dockge/stacks/.agents/rules/project-conventions.md):
  * Codify the boundary between inlined stack invariants and exposed runtime environment variables.
  * Codify the `${VAR:?VAR is required (see .env.example for defaults)}` standard.
* Update [`README.md`](file:///opt/brandon/dockge/stacks/README.md) and [`.docs/env-reference.md`](file:///opt/brandon/dockge/stacks/.docs/env-reference.md).
* Update [`.agents/artifacts/architecture.md`](file:///opt/brandon/dockge/stacks/.agents/artifacts/architecture.md).

---

## 5. Verification & Validation Protocol

1. **Required Variable Enforcement Check**:
   * Temporarily unset a variable in a test Compose file to verify `docker compose config` halts immediately with:
     `required variable ... is missing a value: ... (see .env.example for defaults)`
2. **Secret Auto-Generation Check**:
   * Verify `SECRET_KEY` is automatically generated if missing in `tandoor/.env` upon running `./homelab.sh setup`.
3. **Container Runtime & Health**:
   * Inspect container logs to confirm PIA WireGuard negotiates `wg0` handshake with US endpoint.
   * Confirm Tailscale successfully logs in and registers as `vpn-bridge` on Tailnet.
4. **Egress Leak Prevention**:
   * Execute `docker exec vpn-bridge-pia curl -s https://am.i.mullvad.net/json` (or `ipinfo.io`) to verify outbound IP belongs to Private Internet Access.
5. **Automated Smoke Test**:
   * Run `./homelab.sh test` to verify all tests pass with zero regressions.
6. **Tailscale Admin Console Approval & Client Verification**:
   * In Tailscale Admin Console: Approve the advertised exit node route (`0.0.0.0/0`) on `vpn-bridge`.
   * On client device: Enable Tailscale, toggle "Use Exit Node" → `vpn-bridge`, and confirm public IP is PIA US while `https://jellyfin.turing.home` remains accessible via LAN subnet routing.
