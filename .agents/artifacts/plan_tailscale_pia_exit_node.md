# Engineering Implementation Plan: Dedicated Tailscale PIA Exit Node Stack (vpn-bridge) & Env Defaults Standardization

## 1. Executive Summary & Objective

This engineering initiative delivers two focused improvements to the homelab:
1. **Dedicated Exit Node Stack (`vpn-bridge`)**: Deploys an independent Docker Compose stack pairing a Private Internet Access (PIA) WireGuard client with a Tailscale node (`vpn-bridge`) advertising `--advertise-exit-node`. This enables client devices on the Tailnet to route public internet traffic securely through a domestic US PIA endpoint without leaking the homelab ISP IP, while preserving local LAN routing to homelab services (`192.168.0.0/24` and `*.turing.home`) via the existing `tailscale` subnet router.
2. **Environment Variable Handling Overhaul**: Transitions the homelab from brittle inline fallbacks (`${VAR:-default}`) scattered across Compose files to a centralized Single Source of Truth in `.env.example` templates, paired with strict required-variable assertions in all `compose.yml` files (`${VAR:?VAR is required (see .env.example for defaults)}`).

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
   - Configured to low-latency US endpoints (`PIA_REGION=us_east,us_chicago,us_nyc`).
   - Ensures domestic IP geolocation for mobile web browsing, streaming services, and online banking.
   - `PORT_FORWARDING: 0` (unnecessary for outbound web traffic).
3. **Native Transit Forwarding**:
   - Uses `thrnz/docker-wireguard-pia`'s native `FWD_IFACE=tailscale+` configuration with `net.ipv4.ip_forward=1`.
   - Automatically establishes `iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE` and bidirectional `FORWARD` acceptance between `tailscale0` and `wg0`.
4. **Tailscale Node Identity**:
   - Node hostname on Tailnet: `vpn-bridge`.
   - Flags: `--advertise-exit-node --snat-subnet-routes=true --accept-dns=false`.

---

## 3. Strict Minimization & Pruning Audit

Every planned change, variable, script, and step was audited for strict necessity to prevent redundant definitions or unnecessary state mutations:

| Component | Audit Verdict | Justification |
| :--- | :--- | :--- |
| **`.scripts/backup.sh`** | **ZERO changes** | `${DOCKER_DATA_DIR}` (`/volume2/docker`) is already backed up recursively. `vpn-bridge` data is included automatically without script edits. Staging and retention logic need no changes. |
| **`.scripts/env-tools.sh`** | **ZERO changes** | Regex `grep -qE "(\\\$|\\\$\{)${key}[:}]?"` already matches `${KEY:?...}` required syntax. Global sync to stack `.env` files works out-of-the-box. |
| **Global `PIA_REGION`** | **Pruned from root `.env`** | `PIA_REGION` is specific to `vpn-bridge`. Adding it to root `.env.example` would pollute 11 unrelated stacks. It is scoped exclusively to `vpn-bridge/.env.example`. |
| **`homelab.sh`** | **Single array addition** | Add `"vpn-bridge"` to `STACKS=( ... )` so Dockge and homelab orchestration manage its lifecycle. No logic changes. |
| **Shell Scripts** | **Excluded from `:?` formatting** | Per user requirement, required-variable syntax applies strictly to `compose.yml`. Scripts continue using standard parameter expansion (`${VAR}`). |
| **Optional Secrets (`TS_AUTHKEY`)** | **Preserved as `${TS_AUTHKEY:-}`** | Once Tailscale authenticates, login tokens persist on disk (`/var/lib/tailscale`) and the auth key is consumed. Forcing `:?` on `TS_AUTHKEY` would cause Compose failures on subsequent container restarts. |

---

## 4. Environment Variable Handling Overhaul: Centralized Defaults & Required Assertions

### 4.1 Target Declarative Model: Single Source of Truth (`.env.example`)
All default values are declared once in `.env.example` templates:

1. **Root `.env.example` (Global Parameters)**:
   ```bash
   DOCKER_DATA_DIR=/volume2/docker
   MEDIA_DIR=/volume1/media
   DOCKGE_DIR=/opt/${USER}/dockge
   DOCKGE_STACKS_DIR=/opt/${USER}/dockge/stacks
   PUID=1000
   PGID=100
   TZ=America/New_York
   EXTERNAL_NPM_SUBNET=192.168.0.0/24
   EXTERNAL_NPM_GATEWAY=192.168.0.1
   EXTERNAL_NPM_PARENT=eth0
   NPM_IPV4_ADDRESS=192.168.0.4
   TAILSCALE_IPV4_ADDRESS=192.168.0.5
   BACKUP_RESTIC_REPO=/volume1/backups/homelab-docker
   BACKUP_RETENTION_DAYS=30
   ```

2. **Per-Stack `.env.example` (Stack-Specific Defaults)**:
   Make explicit the defaults previously buried inside Compose files:
   * `homepage/.env.example`: add `HOMEPAGE_ALLOWED_HOSTS=homepage.turing.home,www.turing.home,turing.home,192.168.0.4`
   * `seerr/.env.example`: add `LOG_LEVEL=info`
   * `sonarr-radarr/.env.example`: add `LOG_LEVEL=info`, `LOG_HTML=false`, `CAPTCHA_SOLVER=none`
   * `tailscale/.env.example`: add `TS_EXTRA_ARGS=--snat-subnet-routes=true --accept-dns=false`
   * `vpn-bridge/.env.example`: declare `PIA_REGION=us_east,us_chicago,us_nyc`, `VPN_USER=`, `VPN_PASS=`, `TS_AUTHKEY=`

3. **Compose Required-Variable Syntax (`:?`) with User Guidance**:
   In all `compose.yml` files, replace `${VAR:-default}` with Docker Compose's standard required-variable syntax:
   ```yaml
   ${VAR:?VAR is required (see .env.example for defaults)}
   ```
   * If a required variable is missing or blank in `.env`, Docker Compose refuses to launch and halts immediately with a clear parse-time error pointing directly to `.env.example`.
   * Stacks remain fully runnable standalone because `./homelab.sh setup` syncs all root and stack defaults into `<stack>/.env`.

---

## 5. Step-by-Step Implementation Plan

### Step 1: Environment Template Standardization
* Update `homepage/.env.example`, `seerr/.env.example`, `sonarr-radarr/.env.example`, and `tailscale/.env.example` to declare their respective defaults.
* Audit and refactor all existing `compose.yml` files (`dockge`, `homepage`, `jellyfin`, `nginx`, `postgres`, `qbittorrentvpn`, `recipes`, `seerr`, `sonarr-radarr`, `tailscale`, `cloudflared`, `tandoor`):
  * Replace inline fallbacks (`${VAR:-default}`) with `${VAR:?VAR is required (see .env.example for defaults)}`.
  * Keep intentionally optional variables (`TS_AUTHKEY`) as `${TS_AUTHKEY:-}`.
* Run `./homelab.sh setup` to synchronize defaults into all stack `.env` files.
* Verify every stack parses cleanly with `docker compose config`.

### Step 2: Create `vpn-bridge` Stack
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

### Step 3: Homelab Automation & Test Integration
* In `homelab.sh`: Add `"vpn-bridge"` to `STACKS` array (ordered after `tailscale` and before application stacks).
* In `.tests/suites/test_containers.sh`: Add `test_docker_up_vpn_bridge_pia` and `test_docker_up_vpn_bridge_tailscale`.
* In `.tests/suites/test_interconnect.sh`: Add `test_interconnect_vpn_bridge_routing` (verifying egress IP is PIA) and `test_interconnect_vpn_bridge_tailscale_state` (verifying `BackendState: Running`).

### Step 4: Documentation & Convention Governance
* Update [`.agents/rules/project-conventions.md`](file:///opt/brandon/dockge/stacks/.agents/rules/project-conventions.md) codifying:
  * Single Source of Truth for defaults in `.env.example`.
  * Required `${VAR:?VAR is required (see .env.example for defaults)}` syntax for mandatory Compose variables.
  * Prohibition of `${VAR:?}` syntax in shell scripts.
* Update [`README.md`](file:///opt/brandon/dockge/stacks/README.md) and [`.docs/env-reference.md`](file:///opt/brandon/dockge/stacks/.docs/env-reference.md).
* Update [`.agents/artifacts/architecture.md`](file:///opt/brandon/dockge/stacks/.agents/artifacts/architecture.md).

---

## 6. Verification & Validation Protocol

1. **Required Variable Enforcement Check**:
   * Temporarily unset a variable in a scratch Compose test to verify `docker compose config` halts immediately with:
     `required variable ... is missing a value: ... (see .env.example for defaults)`
2. **Container Runtime & Health**:
   * Inspect container logs to confirm PIA WireGuard negotiates `wg0` handshake with US endpoint.
   * Confirm Tailscale successfully logs in and registers as `vpn-bridge` on Tailnet.
3. **Egress Leak Prevention**:
   * Execute `docker exec vpn-bridge-pia curl -s https://am.i.mullvad.net/json` (or `ipinfo.io`) to verify outbound IP belongs to Private Internet Access.
4. **Automated Smoke Test**:
   * Run `./homelab.sh test` to verify all 51+ tests pass with zero regressions.
5. **Tailscale Admin Console Approval & Client Verification**:
   * In Tailscale Admin Console: Approve the advertised exit node route (`0.0.0.0/0`) on `vpn-bridge`.
   * On mobile client: Enable Tailscale, toggle "Use Exit Node" → `vpn-bridge`, and confirm public IP is PIA US while `https://jellyfin.turing.home` remains accessible via LAN subnet routing.
