# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and automation scripts for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at `${DOCKGE_STACKS_DIR}` (symlinked to `${HOME}/services`) so that all stacks are simultaneously version-controlled in git and manageable through [Dockge](https://dockge.kuma.pet/). Persistent state is mapped to NVMe storage (`/volume2/docker`) for high-IOPS performance, while media libraries reside on mechanical RAID 5 storage (`/volume1/media`).

---

## 1. High-Level Ingress and Egress Topology

Traffic ingress and egress follow three distinct, non-overlapping paths:

```text
[ Internet Client ] ---> Cloudflare Edge ---> [ Cloudflare Tunnel ] ---+
                                                                       |
[ Remote Phone/PC ] ---> Tailscale Mesh  ---> [ Tailscale Router ] ----+---> [ Nginx Proxy Manager ] ---> [ Backend Stacks ]
                                              (192.168.0.5 / homelab)  |     (192.168.0.4 / turing)      (192.168.255.0/24)
                                                                       |
[ Remote Mobile/PC] ---> Tailscale Mesh  ---> [ VPN Bridge Exit Node ] ----> [ PIA WireGuard (wg0) ] ---> [ Public Internet ]
                                              (vpn-bridge-tailscale)         (vpn-bridge-pia)
                                                                       |
[ Local LAN Client] ---------------------------------------------------+
```

* **Public Web Ingress (`*.kamaka.tech`)**: Ingress routes through an outbound Cloudflare Zero Trust tunnel (`cloudflared`) to Nginx Proxy Manager without requiring port forwarding behind CGNAT residential internet.
* **Private Admin Ingress (`*.turing.home`)**: Remote management routes through an encrypted Tailscale WireGuard mesh overlay via an internal subnet router (`192.168.0.5`), restricted by reverse proxy ACLs (`192.168.0.0/16`).
* **Secure VPN Bridge Egress**: Remote mobile devices route internet traffic through a dedicated Tailscale exit node (`vpn-bridge`), which proxies outbound WAN traffic through an encrypted Private Internet Access (PIA) WireGuard tunnel in US server regions (`vpn-bridge-pia`), keeping ISP IP private without interfering with local subnet routing.

---

## 2. Quickstart

### 2.1 Fresh Host Provisioning

```bash
# 1. Clone the repository into ${DOCKGE_STACKS_DIR} and symlink to ~/services
sudo mkdir -p "${DOCKGE_DIR}"
git clone <repo-url> "${DOCKGE_STACKS_DIR}"
ln -s "${DOCKGE_STACKS_DIR}" "${HOME}/services"
cd "${HOME}/services"

# 2. Run initial convergence (creates networks, root .env, and stack templates)
sudo ./homelab.sh setup

# 3. Populate required per-stack secrets in generated .env files
#    (cloudflared, tailscale, vpn-bridge, qbittorrentvpn, jellyfin, sonarr-radarr, seerr, tandoor)

# 4. Re-run setup to sync variables, deploy configs, and launch all stacks
sudo ./homelab.sh setup
```

### 2.2 Routine Updates

```bash
cd ~/services
git pull
sudo ./homelab.sh setup
```

---

## 3. Automation CLI (`homelab.sh`)

`homelab.sh` is an idempotent orchestration CLI anchoring repository configurations to host state:

| Subcommand | Description |
| :--- | :--- |
| `sudo ./homelab.sh setup` | End-to-end host convergence: applies OS fixes, syncs `.env` files, provisions networks, deploys Dockge orchestrator compose, and starts all stacks. |
| `./homelab.sh startup` | Non-interactive boot hook designed for systemd execution on host startup with database readiness checks. |
| `sudo ./homelab.sh backup [-t <type|name>] [-m <msg>]` | Stages zero-downtime DB dumps, snapshots volumes with Restic, commits git changes, applies repeatable SemVer/CalVer/custom tags, pushes to remote, and archives `.env` secrets. |
| `./homelab.sh snapshots` | Lists historical Restic backup snapshots with timestamps, snapshot IDs, and repository sizes. |
| `sudo ./homelab.sh restore [snap] [svc]` | Restores full volume state or an individual service from a Restic snapshot with pre-restore safety checks. |
| `./homelab.sh test [suite]` | Modular smoke and regression test suite verifying containers, direct admin ports, routing, interconnects, security, and backup automation. |

---

## 4. Documentation Index

Detailed architectural specifications, configuration runbooks, and references are organized into dedicated documents under `.docs/`:

* **[Project Organization & Architecture](.docs/project-organization.md)**: Filesystem layout, Dockge compatibility constraints, storage tiering rationale (PCIe NVMe vs mechanical RAID 5), and the Restic-based volume backup and disaster recovery model.
* **[Service Catalog and Port Reference](.docs/service-catalog.md)**: Uniform catalog entries for all 17 containerized services and the host OS portal, active port bindings, internal/external addresses, volume mappings, and container interconnections.
* **[Post-Setup Optimization, Ergonomics & Maintenance Guide](.docs/performance-optimization.md)**: Recommended post-setup runbook covering storage anti-thrashing (No-CoW, Linux VM dirty writeback smoothing), local wildcard TLS certificates, Tailscale split-DNS, atomic media hardlinks, and disaster recovery verification.
* **[Environment Variable Reference & Cheat Sheet](.docs/env-reference.md)**: Central dictionary of every global and per-stack environment variable, defaults, secrets, and Homepage dashboard discovery mechanisms.
* **[Dual-Ingress Networking & Security](.docs/networking.md)**: Subnet topology (`192.168.0.0/24` LAN, `192.168.255.0/24` bridge), macvlan routing, static IP table, split DNS, TLS certificates, and edge security hardening.
* **[Operations and Appliance Engineering](.docs/operations.md)**: Operational runbooks, backup and secret restoration procedures, systemd background units, asynchronous mount handling, and OS workarounds.
* **[Changelog](CHANGELOG.md)**: Historical release milestones with paired semantic and CalVer tags.
* **[Project Backlog](BACKLOG.md)**: Tracked technical improvements and non-blocking optimizations.
