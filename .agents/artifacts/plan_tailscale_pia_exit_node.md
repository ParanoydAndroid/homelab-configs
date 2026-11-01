# Engineering Implementation Plan: Dedicated Tailscale PIA Exit Node Stack

## 1. Executive Summary & Objective

The objective is to deploy a dedicated, independent Docker Compose stack (`vpn-exit`) pairing a Private Internet Access (PIA) WireGuard client with a Tailscale node advertising `--advertise-exit-node`.

This topology enables any client device running Tailscale (e.g. mobile phones, travel laptops) to route public internet browsing traffic securely and privately through PIA without leaking the homelab's public ISP IP, while preserving full, zero-latency access to internal homelab services (`192.168.0.0/24` and `*.turing.home`) via the existing `tailscale` LAN subnet router.

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

## 3. Implementation Steps & File Modifications

### Step 1: Environment Variable Declarations

Add configurable variables to root `.env.example` and root `.env`:
* `PIA_EXIT_REGION`: Preferred PIA US region cluster (default: `us_east,us_chicago,us_nyc`).
* Reuses existing root secrets (`VPN_USER`, `VPN_PASS`, `TS_AUTHKEY`) without requiring duplicate credentials.

### Step 2: Stack Definition (`vpn-exit/compose.yml`)

Create `vpn-exit/compose.yml` following strict project Compose conventions:
* Omit deprecated `version` and `name`.
* Services:
  * `vpn`: `thrnz/docker-wireguard-pia:latest`
    * `container_name: vpn-exit-pia`
    * `hostname: vpn-exit`
    * `cap_add: [NET_ADMIN]`
    * `sysctls: [net.ipv4.ip_forward=1, net.ipv4.conf.all.src_valid_mark=1, net.ipv6.conf.all.disable_ipv6=1]`
    * `environment`: `USER`, `PASS`, `LOC=${PIA_EXIT_REGION}`, `PORT_FORWARDING=0`, `FIREWALL=1`, `FWD_IFACE=tailscale+`, `LOCAL_NETWORK=192.168.0.0/16,100.64.0.0/10`.
    * `volumes`: `${DOCKER_DATA_DIR}/vpn-exit/data/pia:/pia`
    * `networks`: `homelab`
  * `tailscale`: `tailscale/tailscale:latest`
    * `container_name: vpn-exit-tailscale`
    * `hostname: pia-exit`
    * `network_mode: "service:vpn"`
    * `depends_on: { vpn: { condition: service_healthy } }`
    * `cap_add: [NET_ADMIN, NET_RAW]`
    * `devices: [/dev/net/tun:/dev/net/tun]`
    * `environment`: `TS_AUTHKEY`, `TS_HOSTNAME=pia-exit`, `TS_STATE_DIR=/var/lib/tailscale`, `TS_USERSPACE=false`, `TS_EXTRA_ARGS=--advertise-exit-node --snat-subnet-routes=true --accept-dns=false`
    * `volumes`: `${DOCKER_DATA_DIR}/vpn-exit/data/tailscale:/var/lib/tailscale`, `/dev/net/tun:/dev/net/tun`, `tmpfs: [/tmp]`

### Step 3: Homelab Automation Integration

* Update [`homelab.sh`](file:///opt/brandon/dockge/stacks/homelab.sh):
  * Register `"vpn-exit"` in `STACKS` array in the standard dependency order (after `tailscale` and before application stacks).
  * Update `env-tools.sh` sync logic to propagate variables into `vpn-exit/.env`.
* Update [`.scripts/backup.sh`](file:///opt/brandon/dockge/stacks/.scripts/backup.sh):
  * Add `/volume2/docker/vpn-exit` data directory to volume backup paths and retention policies.

### Step 4: Test Suite Coverage

Add automated assertions to [`.tests/suites/test_containers.sh`](file:///opt/brandon/dockge/stacks/.tests/suites/test_containers.sh) and [`.tests/suites/test_interconnect.sh`](file:///opt/brandon/dockge/stacks/.tests/suites/test_interconnect.sh):
1. `test_docker_up_vpn_exit`: Verify `vpn-exit-pia` is running and healthy.
2. `test_docker_up_vpn_exit_tailscale`: Verify `vpn-exit-tailscale` is running.
3. `test_interconnect_vpn_exit_routing`: Verify that egress from `vpn-exit-tailscale` resolves to a PIA public IP, not the host ISP WAN IP.
4. `test_interconnect_vpn_exit_tailscale_state`: Verify `vpn-exit-tailscale` reports `BackendState: Running` and advertises exit node route `0.0.0.0/0`.

### Step 5: Documentation & Artifacts

* Update [`README.md`](file:///opt/brandon/dockge/stacks/README.md) and [`.docs/service-catalog.md`](file:///opt/brandon/dockge/stacks/.docs/service-catalog.md) documenting the dual-Tailscale network model.
* Update [`.agents/artifacts/architecture.md`](file:///opt/brandon/dockge/stacks/.agents/artifacts/architecture.md).

---

## 4. Verification & Validation Protocol

1. **Container Runtime & Health**:
   * Inspect container logs to confirm PIA WireGuard negotiates `wg0` handshake with US endpoint.
   * Confirm Tailscale successfully logs in and registers as `pia-exit` on Tailnet.
2. **Egress Leak Prevention**:
   * Execute `docker exec vpn-exit-pia curl -s https://am.i.mullvad.net/json` (or `ipinfo.io`) to verify outbound IP belongs to Private Internet Access.
3. **Tailscale Admin Console Verification**:
   * In Tailscale Admin Console (Machines tab): Locate `pia-exit` and approve the advertised exit node route (`0.0.0.0/0`).
4. **Client Device End-to-End Test**:
   * On mobile client: Enable Tailscale.
   * Access `https://jellyfin.turing.home` (verifies LAN subnet routing works).
   * Enable "Use Exit Node" → `pia-exit`.
   * Check browser IP at `ipleak.net`: Verify IP is PIA US and DNS is private.
   * Access `https://jellyfin.turing.home` while exit node is active: Verify LAN split routing continues to function seamlessly.

---

## 5. Potential Hazards & Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Tailscale Admin Approval Required** | Exit node advertised but unusable by clients until approved | Document manual approval step in Tailscale admin console or configure Tailnet ACL auto-approval (`autoApprovers: { exitNode: [...] }`). |
| **IP Forwarding Blocked** | Client connects to exit node but has no internet connectivity | Set `net.ipv4.ip_forward=1` sysctl and verify `FWD_IFACE=tailscale+` establishes iptables MASQUERADE on `wg0`. |
| **PIA Reconnection Flap** | Tailscale disconnects if PIA drops | Tailscale's `containerboot` handles reconnections automatically; `vpn` healthcheck marks unhealthy and restarts container on fatal tunnel loss. |
