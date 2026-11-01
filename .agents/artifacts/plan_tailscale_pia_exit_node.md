# Engineering Implementation Plan: Dedicated Tailscale PIA Exit Node Stack & Env Defaults Standardization

## 1. Executive Summary & Objective

This engineering initiative delivers two foundational improvements to the homelab:
1. **Dedicated Exit Node Stack (`vpn-exit`)**: Deploys an independent Docker Compose stack pairing a Private Internet Access (PIA) WireGuard client with a Tailscale node advertising `--advertise-exit-node`. This enables client devices on the Tailnet to route public internet traffic securely through a domestic US PIA endpoint without leaking the homelab ISP IP, while preserving local LAN routing to homelab services (`192.168.0.0/24` and `*.turing.home`) via the existing `tailscale` subnet router.
2. **Environment Variable Handling Overhaul**: Transitions the homelab from brittle inline fallbacks (`${VAR:-default}`) scattered across multiple Compose files to a centralized Single Source of Truth in `.env.example` templates, paired with strict required-variable assertions (`${VAR:?}`) in all `compose.yml` files.

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
                      └──► Routed to Exit Node (pia-exit)
                                │
   ┌────────────────────────────┼────────────────────────────────────────────────────────┐
   │ 'vpn-exit' Shared Network  │ Namespace                                              │
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

1. **Dedicated Stack (`vpn-exit/compose.yml`)**:
   - Completely isolated from `qbittorrentvpn`. qBittorrent remains configured for Canadian incoming port forwarding without interference.
   - Completely isolated from `tailscale/compose.yml` (the LAN subnet router on `192.168.0.5`).
2. **US-Based Region Selection**:
   - Default region configured to low-latency US endpoints (`us_east,us_chicago,us_nyc`).
   - Ensures domestic IP geolocation for mobile web browsing, streaming services, and online banking.
   - `PORT_FORWARDING: 0` (unnecessary for outbound web traffic).
3. **Native Transit Forwarding**:
   - Uses `thrnz/docker-wireguard-pia`'s native `FWD_IFACE=tailscale+` configuration with `net.ipv4.ip_forward=1`.
   - Automatically establishes `iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE` and bidirectional `FORWARD` acceptance between `tailscale0` and `wg0`.
4. **Tailscale Node Identity**:
   - Node hostname on Tailnet: `pia-exit`.
   - Flags: `--advertise-exit-node --snat-subnet-routes=true --accept-dns=false`.

---

## 3. Environment Variable Handling Overhaul: Centralized Defaults & Required Assertions

### 3.1 Problem Statement: Brittle Inline Fallbacks
Currently, homelab Docker Compose files rely heavily on repeated inline fallback substitution:
```yaml
volumes:
  - ${DOCKER_DATA_DIR:-/volume2/docker}/jellyfin/data:/config
  - ${MEDIA_DIR:-/volume1/media}:/media
environment:
  - PUID=${PUID:-1000}
  - PGID=${PGID:-100}
  - TZ=${TZ:-America/New_York}
```
This pattern introduces several operational and maintenance hazards:
1. **Scattered Multi-Line Edits**: Modifying a default (e.g. changing storage root path or timezone) requires searching and editing dozens of lines across 12+ `compose.yml` files.
2. **Silent Failure & Masked Drift**: If a variable is accidentally omitted from `.env`, Compose silently falls back to the hardcoded default, obscuring missing configuration or subtle deployment errors.
3. **Template Desynchronization**: Inline defaults in Compose files frequently drift out of sync with comments and declarations in `.env.example`.

### 3.2 Target Declarative Model: Single Source of Truth (`.env.example`) & Required Compose Assertions
We standardize a clean, declarative model across the entire repository:

1. **Defaults Set Exclusively in `.env.example` Templates**:
   All default values are declared once in root `.env.example` (for globals) and per-stack `.env.example` (for stack-specific settings):
   ```bash
   # Root .env.example (Single Source of Truth for Defaults)
   DOCKER_DATA_DIR=/volume2/docker
   MEDIA_DIR=/volume1/media
   PUID=1000
   PGID=100
   TZ=America/New_York
   EXTERNAL_NPM_SUBNET=192.168.0.0/24
   EXTERNAL_NPM_GATEWAY=192.168.0.1
   EXTERNAL_NPM_PARENT=eth0
   NPM_IPV4_ADDRESS=192.168.0.4
   TAILSCALE_IPV4_ADDRESS=192.168.0.5
   PIA_EXIT_REGION=us_east,us_chicago,us_nyc
   ```
   * Anyone copying `.env.example` to `.env` immediately receives functional, validated defaults.
   * Updating a default value in the homelab requires editing exactly **one line** in `.env.example` and running `./homelab.sh setup` (or `init_and_sync_env`).

2. **Compose Variables Treated as Required (`:?`)**:
   In all `compose.yml` files, replace `${VAR:-default}` with Docker Compose's standard required-variable syntax:
   ```yaml
   volumes:
     - ${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required}/jellyfin/data:/config
     - ${MEDIA_DIR:?MEDIA_DIR is required}:/media
   environment:
     - PUID=${PUID:?PUID is required}
     - PGID=${PGID:?PGID is required}
     - TZ=${TZ:?TZ is required}
   ```
   * If any variable is unset or empty in the environment/`.env`, Docker Compose refuses to launch and immediately halts with a clean parse-time diagnostic error:
     `required variable DOCKER_DATA_DIR is missing a value: DOCKER_DATA_DIR is required`
   * This guarantees missing variables are immediately obvious at runtime.

3. **Automation & Two-Tier Sync Preservation**:
   * `init_and_sync_env` in `.scripts/env-tools.sh` continues to propagate defined global variables from root `.env` down into each `<stack>/.env`.
   * Stacks remain fully runnable standalone with `docker compose up -d` because their local `.env` contains the required values synced from root.

---

## 4. Implementation Steps & File Modifications

### Step 1: Environment Template Updates & Required Variable Refactor

1. **Root `.env.example` & Root `.env`**:
   * Populate all default values explicitly (no blank globals).
   * Add `PIA_EXIT_REGION=us_east,us_chicago,us_nyc`.
2. **Global Compose Audit & Refactoring**:
   * Update all `compose.yml` files across every stack (`dockge`, `homepage`, `jellyfin`, `nginx`, `postgres`, `qbittorrentvpn`, `recipes`, `seerr`, `tailscale`, `cloudflared`, and `vpn-exit`):
     * Replace `${DOCKER_DATA_DIR:-...}` with `${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required}`
     * Replace `${MEDIA_DIR:-...}` with `${MEDIA_DIR:?MEDIA_DIR is required}`
     * Replace `${PUID:-...}` with `${PUID:?PUID is required}`
     * Replace `${PGID:-...}` with `${PGID:?PGID is required}`
     * Replace `${TZ:-...}` with `${TZ:?TZ is required}`
     * Replace `${NPM_IPV4_ADDRESS:-...}` with `${NPM_IPV4_ADDRESS:?NPM_IPV4_ADDRESS is required}`
     * Replace `${TAILSCALE_IPV4_ADDRESS:-...}` with `${TAILSCALE_IPV4_ADDRESS:?TAILSCALE_IPV4_ADDRESS is required}`
3. **Run Environment Sync**:
   * Execute `./homelab.sh setup` to propagate all defaults into every stack's `.env`.
   * Verify all stacks parse cleanly with `docker compose -f <stack>/compose.yml config`.

### Step 2: Stack Definition (`vpn-exit/compose.yml`)

Create `vpn-exit/compose.yml` adhering strictly to project conventions:
* Services:
  * `vpn`: `thrnz/docker-wireguard-pia:latest`
    * `container_name: vpn-exit-pia`
    * `hostname: vpn-exit`
    * `cap_add: [NET_ADMIN]`
    * `sysctls: [net.ipv4.ip_forward=1, net.ipv4.conf.all.src_valid_mark=1, net.ipv6.conf.all.disable_ipv6=1]`
    * `environment`: `USER: ${VPN_USER:?VPN_USER is required}`, `PASS: ${VPN_PASS:?VPN_PASS is required}`, `LOC: ${PIA_EXIT_REGION:?PIA_EXIT_REGION is required}`, `PORT_FORWARDING: 0`, `FIREWALL: 1`, `FWD_IFACE: tailscale+`, `LOCAL_NETWORK: 192.168.0.0/16,100.64.0.0/10`.
    * `volumes`: `${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required}/vpn-exit/data/pia:/pia`
    * `networks`: `homelab`
  * `tailscale`: `tailscale/tailscale:latest`
    * `container_name: vpn-exit-tailscale`
    * `hostname: pia-exit`
    * `network_mode: "service:vpn"`
    * `depends_on: { vpn: { condition: service_healthy } }`
    * `cap_add: [NET_ADMIN, NET_RAW]`
    * `devices: [/dev/net/tun:/dev/net/tun]`
    * `environment`: `TS_AUTHKEY: ${TS_AUTHKEY:-}`, `TS_HOSTNAME: pia-exit`, `TS_STATE_DIR: /var/lib/tailscale`, `TS_USERSPACE: false`, `TS_EXTRA_ARGS: --advertise-exit-node --snat-subnet-routes=true --accept-dns=false`
    * `volumes`: `${DOCKER_DATA_DIR:?DOCKER_DATA_DIR is required}/vpn-exit/data/tailscale:/var/lib/tailscale`, `/dev/net/tun:/dev/net/tun`, `tmpfs: [/tmp]`
* Create `vpn-exit/.env.example` declaring stack-specific overrides.

### Step 3: Homelab Automation Integration

* Update [`homelab.sh`](file:///opt/brandon/dockge/stacks/homelab.sh):
  * Register `"vpn-exit"` in `STACKS` array in the standard dependency order (after `tailscale` and before application stacks).
  * Ensure `env-tools.sh` sync logic propagates variables into `vpn-exit/.env`.
* Update [`.scripts/backup.sh`](file:///opt/brandon/dockge/stacks/.scripts/backup.sh):
  * Add `/volume2/docker/vpn-exit` data directory to volume backup paths and retention policies.

### Step 4: Test Suite Coverage

Add automated assertions to [`.tests/suites/test_containers.sh`](file:///opt/brandon/dockge/stacks/.tests/suites/test_containers.sh) and [`.tests/suites/test_interconnect.sh`](file:///opt/brandon/dockge/stacks/.tests/suites/test_interconnect.sh):
1. `test_docker_up_vpn_exit`: Verify `vpn-exit-pia` is running and healthy.
2. `test_docker_up_vpn_exit_tailscale`: Verify `vpn-exit-tailscale` is running.
3. `test_interconnect_vpn_exit_routing`: Verify that egress from `vpn-exit-tailscale` resolves to a PIA public IP, not the host ISP WAN IP.
4. `test_interconnect_vpn_exit_tailscale_state`: Verify `vpn-exit-tailscale` reports `BackendState: Running` and advertises exit node route `0.0.0.0/0`.
5. `test_env_required_vars`: Negative test verifying that unset required variables in Compose produce immediate parse-time errors.

### Step 5: Documentation & Rule Governance Updates

* Update [`.agents/rules/project-conventions.md`](file:///opt/brandon/dockge/stacks/.agents/rules/project-conventions.md) permanently codifying:
  * Single Source of Truth for defaults in `.env.example`.
  * Prohibition of inline fallback defaults (`${VAR:-default}`) in `compose.yml` in favor of required assertions (`${VAR:?error}`).
* Update [`README.md`](file:///opt/brandon/dockge/stacks/README.md) and [`.docs/env-reference.md`](file:///opt/brandon/dockge/stacks/.docs/env-reference.md).
* Update [`.agents/artifacts/architecture.md`](file:///opt/brandon/dockge/stacks/.agents/artifacts/architecture.md).

---

## 5. Verification & Validation Protocol

1. **Required Variable Enforcement Check**:
   * Temporarily rename a variable in a scratch `.env` to verify `docker compose config` halts immediately with `required variable ... is missing a value`.
2. **Container Runtime & Health**:
   * Inspect container logs to confirm PIA WireGuard negotiates `wg0` handshake with US endpoint.
   * Confirm Tailscale successfully logs in and registers as `pia-exit` on Tailnet.
3. **Egress Leak Prevention**:
   * Execute `docker exec vpn-exit-pia curl -s https://am.i.mullvad.net/json` (or `ipinfo.io`) to verify outbound IP belongs to Private Internet Access.
4. **Tailscale Admin Console Verification**:
   * In Tailscale Admin Console (Machines tab): Locate `pia-exit` and approve the advertised exit node route (`0.0.0.0/0`).
5. **Client Device End-to-End Test**:
   * On mobile client: Enable Tailscale.
   * Access `https://jellyfin.turing.home` (verifies LAN subnet routing works).
   * Enable "Use Exit Node" → `pia-exit`.
   * Check browser IP at `ipleak.net`: Verify IP is PIA US and DNS is private.
   * Access `https://jellyfin.turing.home` while exit node is active: Verify LAN split routing continues to function seamlessly.

---

## 6. Potential Hazards & Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Tailscale Admin Approval Required** | Exit node advertised but unusable by clients until approved | Document manual approval step in Tailscale admin console or configure Tailnet ACL auto-approval (`autoApprovers: { exitNode: [...] }`). |
| **IP Forwarding Blocked** | Client connects to exit node but has no internet connectivity | Set `net.ipv4.ip_forward=1` sysctl and verify `FWD_IFACE=tailscale+` establishes iptables MASQUERADE on `wg0`. |
| **PIA Reconnection Flap** | Tailscale disconnects if PIA drops | Tailscale's `containerboot` handles reconnections automatically; `vpn` healthcheck marks unhealthy and restarts container on fatal tunnel loss. |
| **Compose Parse Errors on Untracked Stacks** | Unsynced `.env` files cause Compose failures | `./homelab.sh setup` runs `init_and_sync_env` across all registered stacks before any stack launch. |
