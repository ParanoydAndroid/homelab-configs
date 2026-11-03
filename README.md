# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and automation scripts for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at `${DOCKGE_STACKS_DIR}` (symlinked to `${HOME}/services`) so that all stacks are simultaneously version-controlled in git and manageable through [Dockge](https://dockge.kuma.pet/). Persistent state is mapped to NVMe storage (`/volume2/docker`) for high-IOPS performance, while media libraries reside on mechanical RAID 5 storage (`/volume1/media`).

---

## 1. High-Level Ingress and Egress Topology

Traffic ingress and egress follow three distinct, non-overlapping paths:

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

* **Public Web Ingress (`*.kamakakai.com`)**: Ingress routes through an outbound Cloudflare Zero Trust tunnel (`cloudflared`) to Caddy reverse proxy without requiring port forwarding behind CGNAT residential internet.
* **Private Homelab Ingress (`*.kamaka.tech`)**: Local LAN and Tailscale mesh management routes directly to Caddy (`192.168.0.4`) with automated Let's Encrypt TLS via Cloudflare DNS-01 and Pi-hole wildcard DNS.
* **Client File Delivery (`download.kamaka.tech`)**: Authorized local and Tailscale clients download staged archives and files directly over HTTPS with an interactive directory index.
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
#    (ingress, mesh, torrent, media, productivity, dashboard)

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

---

## 5. Agent Skills & Operational Runbooks

Procedural workflows, interactive scaffolding, and diagnostic algorithms are modularized as on-demand skills under `.skills/` (mirrored in `.agents/skills/`):

| Skill Name | Purpose & Operational Scope |
| :--- | :--- |
| **`start-homelab`** | Interactive onboarding wizard for new developers: guides project orientation, service selection (keep/defer/remove), hardware & platform adaptation, secret provisioning, and verified deployment. |
| **`stack-lifecycle`** | Standardized runbook for adding, retiring, or decommissioning a service stack across Compose, `.env.example`, reverse proxy, dashboard widgets, backups, and smoke tests. |
| **`tls-certificates`** | Local root CA generation, wildcard certificate provisioning (`*.home`), NPM deployment, and client OS trust distribution (macOS, Windows, Linux, iOS, Android, Firefox). |
| **`disaster-recovery-drill`** | Zero-downtime sandbox database restoration and integrity verification (`pg_restore`, SQLite PRAGMA checks) from Restic snapshots into `/tmp/dr-drill`. |
| **`homelab-audit`** | Continuous drift detection auditing container runtimes, untracked containers, volume permissions/ACLs, Btrfs No-CoW flags, routing endpoints, and backup timer health. |
| **`feature-initiation`** | Mainline synchronization, branch checkout (`feature/<name>`), architectural plan drafting, and adversarial "grill-me" design critique cycle. |
| **`feature-completion`** | Full test suite verification, stop-on-failure enforcement, roll-up SemVer/CalVer changelog synthesis, merge, and dual tagging. |
| **`stack-authoring`** | Compose authoring standards, canonical key ordering, variable assertion syntax, non-root user execution, and network attachment. |
| **`backup-recovery`** | Restic persistent volume snapshots, online database staging, snapshot inspection, and disaster recovery. |
| **`network-diagnostics`** | Systematic diagnostic triage flowchart for virtual hosts, container DNS resolution, WireGuard killswitches, and Tailscale routing. |
| **`test-authoring`** | Systematic recipe and standards for authoring automated smoke, interconnect, and security tests in `.tests/suites/`. |
