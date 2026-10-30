# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and automation scripts for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at `${DOCKGE_STACKS_DIR}` (symlinked to `/home/${USER}/services`) so that all stacks are simultaneously version-controlled in git and manageable through [Dockge](https://dockge.kuma.pet/). Persistent state is mapped to NVMe storage (`/volume2/docker`) for high-IOPS performance, while media libraries reside on mechanical RAID 5 storage (`/volume1/media`).

---

## 1. High-Level Ingress Topology

Traffic ingress is divided into two strict, non-overlapping pillars:

```text
[ Internet Client ] ---> Cloudflare Edge ---> [ Cloudflare Tunnel ] ---+
                                                                       |
[ Remote Phone/PC ] ---> Tailscale Mesh  ---> [ Tailscale Router ] ----+---> [ Nginx Proxy Manager ] ---> [ Backend Stacks ]
                                                                       |     (192.168.0.4 / turing)      (192.168.255.0/24)
[ Local LAN Client] ---------------------------------------------------+
```

* **Public Web Ingress (`*.kamaka.tech`)**: Ingress routes through an outbound Cloudflare Zero Trust tunnel (`cloudflared`) to Nginx Proxy Manager without requiring port forwarding behind CGNAT residential internet.
* **Private Admin Ingress (`*.turing.home`)**: Remote management routes through an encrypted Tailscale WireGuard mesh overlay via an internal subnet router (`192.168.0.5`), restricted by reverse proxy ACLs (`192.168.0.0/16`).

---

## 2. Quickstart

### 2.1 Fresh Host Provisioning

```bash
# 1. Clone the repository into ${DOCKGE_STACKS_DIR} and symlink to ~/services
sudo mkdir -p "${DOCKGE_DIR:-/opt/${USER}/dockge}"
git clone <repo-url> "${DOCKGE_STACKS_DIR:-/opt/${USER}/dockge/stacks}"
ln -s "${DOCKGE_STACKS_DIR:-/opt/${USER}/dockge/stacks}" "/home/${USER}/services"
cd "/home/${USER}/services"

# 2. Run initial convergence (creates networks, root .env, and stack templates)
sudo ./homelab.sh setup

# 3. Populate required per-stack secrets in generated .env files
#    (cloudflared, tailscale, qbittorrentvpn, jellyfin, sonarr-radarr, seerr, tandoor)

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
| `sudo ./homelab.sh setup` | End-to-end host convergence: applies OS fixes, syncs `.env` files, provisions networks, deploys configs, and starts all stacks. |
| `./homelab.sh startup` | Non-interactive boot hook designed for systemd execution on host startup with database readiness checks. |
| `./homelab.sh deploy-configs` | Deploys tracked configs from `.configs/` to live host volumes with diff inspection and conflict resolution. |
| `./homelab.sh pull-configs` | Extracts live configurations (Homepage YAML, NPM SQLite routing tables, and `.conf` files) into `.configs/`. |
| `./homelab.sh backup [--tag]` | Pulls live configs, commits git changes, applies CalVer/SemVer tags, and archives all live `.env` secrets. |
| `./homelab.sh test [suite]` | Modular smoke and regression test suite verifying containers, direct admin ports, routing, interconnects, and security. |

---

## 4. Documentation Index

Detailed architectural specifications, configuration runbooks, and references are organized into dedicated documents under `.docs/`:

* **[Project Organization & Architecture](.docs/project-organization.md)**: Filesystem layout, Dockge compatibility constraints, storage tiering rationale (PCIe NVMe vs mechanical RAID 5), and the bidirectional configuration synchronization model.
* **[Service Catalog and Port Reference](.docs/service-catalog.md)**: Uniform catalog entries for all 15 services and the host OS portal, active port bindings, internal/external addresses, volume mappings, and container interconnections.
* **[Environment Variable Reference & Cheat Sheet](.docs/env-reference.md)**: Central dictionary of every global and per-stack environment variable, defaults, secrets, and Homepage dashboard discovery mechanisms.
* **[Dual-Ingress Networking & Security](.docs/networking.md)**: Subnet topology (`192.168.0.0/24` LAN, `192.168.255.0/24` bridge), macvlan routing, static IP table, split DNS, TLS certificates, and edge security hardening.
* **[Operations and Appliance Engineering](.docs/operations.md)**: Operational runbooks, backup and secret restoration procedures, systemd background units, asynchronous mount handling, and OS workarounds.
* **[Changelog](CHANGELOG.md)**: Historical release milestones with paired semantic and CalVer tags.
* **[Project Backlog](BACKLOG.md)**: Tracked technical improvements and non-blocking optimizations.
