# Post-Setup Optimization, Ergonomics & Maintenance Guide

This document provides a comprehensive runbook of recommended interactive configurations, optimizations, and ergonomic enhancements for newly deployed homelab stacks. It is designed to guide a stack owner through post-setup steps that maximize runtime performance, reduce hardware storage wear, improve day-to-day client usability, and ensure operational maintainability.

> **Design Philosophy & Single-Volume Scope**:
> The steps outlined below are **recommended best practices, not mandatory requirements**. The entire homelab architecture, Compose stack definitions, and `homelab.sh` lifecycle tooling are engineered to operate reliably on single-volume storage architectures (such as a single mechanical RAID array on `/volume1`). Apply these recommendations according to your specific hardware capabilities, storage topology, and operational preferences.

---

## Overview of Post-Setup Tuning Areas

| Category | Target Operational Goals | Key Systems & Services Involved |
| :--- | :--- | :--- |
| **1. Performance & Anti-Thrashing** | Eliminate mechanical disk thrashing, absorb random I/O spikes, minimize Btrfs filesystem fragmentation, and remove edge buffering latency. | Linux Kernel VM, Docker Daemon, Btrfs, Jellyfin (`tmpfs`), Cloudflare CDN. |
| **2. Ergonomics & Usability** | Remove browser security warnings, enable zero-friction remote LAN DNS resolution, configure privacy exit nodes, and enable instant media hardlinking. | Local Root CA, Tailscale Split-DNS, Homepage Dashboard, Radarr/Sonarr. |
| **3. Maintainability & Reliability** | Enforce bounded disk logging, verify hot database backups, validate disaster recovery restoration, and ensure host OS workaround stability. | Systemd Timers, Restic Backup Engine, PostgreSQL / SQLite, `homelab.sh`. |

---

# Part 1: Performance & Anti-Thrashing Tuning

## 1. Storage Tiering & Volume Topology

### Tiered Architecture (NVMe SSD + Mechanical RAID)
Where dual-volume hardware is available, separating high-IOPS random transactions from high-capacity sequential storage delivers the most responsive user experience and dramatically reduces mechanical head thrashing:

| Tier | Typical Hardware | Target Workload | Workload Characteristics |
| :--- | :--- | :--- | :--- |
| **High-IOPS Tier** (`/volume2`) | PCIe NVMe or SATA SSD | Container state (`${DOCKER_DATA_DIR}`), SQLite databases, image thumbnails, cache directories. | Random 4KB reads/writes, high queue depths, sub-millisecond seek latency. |
| **Bulk Capacity Tier** (`/volume1`) | Multi-disk mechanical RAID 5/6 | Bulk media libraries (`${MEDIA_DIR}`), completed downloads, restic backup archives. | Large sequential streaming reads/writes, multi-gigabyte continuous file transfers. |

### Single-Volume Compatibility
If operating a single RAID volume (all persistent data residing on `/volume1`):
* Configure `DOCKER_DATA_DIR=/volume1/docker` and `MEDIA_DIR=/volume1/media` in the root `.env`. Automation propagates these values to all child stacks.
* Storage tiering is an optimization rather than an architectural requirement. On single-volume setups, prioritize the Btrfs No-CoW and virtual memory tuning steps below to minimize mechanical disk contention.

---

## 2. Docker Daemon Root (`data-root`) Placement

By default, Docker stores images, container writeable overlayfs layers, and local volumes under `/var/lib/docker` (or `/volume1/@docker` on UGREEN NAS).

### Optimization
Directing Docker's `data-root` to solid-state storage (e.g. `/volume2/@docker`) ensures that:
1. Container image layer pulls, unpacks, and container restarts execute at NVMe bus speeds.
2. Writable overlayfs layers for active containers do not compete with media streaming on mechanical arrays.

### Configuration (`/etc/docker/daemon.json`)
```json
{
  "data-root": "/volume2/@docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```
*Note: On single-volume setups, leaving `data-root` on `/volume1/@docker` is completely acceptable.*

---

## 3. Btrfs Copy-on-Write (No-CoW) Optimization

On Btrfs filesystems, Copy-on-Write (CoW) causes severe file fragmentation and write amplification when modifying databases (PostgreSQL, SQLite) or updating downloading torrent payloads in-place.

### Optimization
Disable Copy-on-Write on active database and temporary download directories before populating data:

```bash
# Disable CoW on active database and temporary download directories
sudo chattr +C /volume2/docker/postgres/data
sudo chattr +C /volume2/docker/nginx/data
sudo chattr +C /volume2/docker/qbittorrentvpn/data/incomplete
```

### Verification
```bash
lsattr -d /volume2/docker/postgres/data
# Output must display the 'C' attribute flag: ---------------C------
```
*Note: This optimization is especially valuable on single mechanical RAID Btrfs arrays, where CoW fragmentation degrades read performance significantly over time.*

---

## 4. Linux Virtual Memory Dirty Ratio Smoothing

Default Linux kernel settings allow up to 20% of total system memory to accumulate unwritten "dirty" pages before forcing flushes to physical storage. On high-RAM systems with mechanical storage arrays, this can trigger periodic 10–30 second system-wide I/O lockups when gigabytes of buffered writes flush simultaneously.

### Optimization
Smooth out disk write patterns by lowering dirty memory flush thresholds in `/etc/sysctl.d/99-homelab-io.conf`:

```ini
# Start background flushing earlier in small, continuous batches
vm.dirty_background_ratio = 5

# Cap maximum dirty memory to prevent large blocking flush spikes
vm.dirty_ratio = 10
```

Apply immediately without rebooting:
```bash
sudo sysctl --system
```

---

## 5. In-Memory Transcoding Caches (`tmpfs`)

Media servers like Jellyfin transcode incompatible video streams on the fly, generating temporary HLS video segments every 2 to 6 seconds. Writing transcode segments to physical disks creates continuous disk activity and premature drive wear.

### Optimization
Mount an in-memory `tmpfs` volume for transcode scratch space:

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    tmpfs:
      - /transcode:size=4G,mode=1777
```
* Point Jellyfin's transcode path to `/transcode` in the WebUI under **Dashboard -> Playback -> Transcoding**.
* Temporary video segments exist strictly in RAM and evaporate upon stream completion.

---

## 6. Cloudflare Edge Cache Bypass for Video Streaming

When reverse-proxying media servers like Jellyfin through Cloudflare Zero Trust tunnels (`jellyfin.kamaka.tech`), Cloudflare's default CDN caching rules can attempt to buffer video segments at edge nodes. This introduces video playback stalls, increases time-to-first-frame buffering latency, and risks violating CDN terms of service regarding large media chunk caching.

### Optimization
Configure an explicit Cache Rule in the Cloudflare Dashboard to bypass edge caching for media server streams:

1. In the Cloudflare Dashboard, select your domain (`kamaka.tech`) and navigate to **Caching -> Cache Rules -> Create Rule**.
2. **Rule Name**: `Bypass Jellyfin Video Cache`.
3. **If incoming requests match...**:
   * **Field**: `Hostname`
   * **Operator**: `equals`
   * **Value**: `jellyfin.kamaka.tech`
4. **Then...**:
   * **Cache eligibility**: Select **Bypass cache**.
5. Save and deploy the rule.

This instructs the Cloudflare edge to stream media chunks directly from the tunnel origin without intermediary caching delays.

---

## 7. Read-Only Media Mount Enforcement (`:ro`)

Services that only consume media (e.g. Jellyfin for playback, Seerr for requests) should never mount media storage with write permissions.

### Optimization
Append `:ro` to volume mappings for read-only consumers in `compose.yml`:

```yaml
volumes:
  - ${MEDIA_DIR:?See env.example for default.}:/data/media:ro
```
This prevents accidental modification, avoids acquiring unnecessary directory write locks on the host filesystem, and strengthens container defense-in-depth.

---

# Part 2: Ergonomics & Client Usability

## 8. Local Wildcard TLS Certificate Trust (Eliminating Browser Warnings)

Default self-signed certificates trigger browser warning screens across internal LAN addresses (`*.turing.home`, `nas.home`). Generating a local root Certificate Authority (CA) and wildcard certificate establishes instant HTTPS padlocks across all client devices.

### Interactive Configuration
1. **Generate Certificates**:
   ```bash
   cd ~/services/.configs/nginx
   ./generate-local-cert.sh
   ```
   This generates `turing.key` and `turing.crt` valid for 10 years covering `turing.home`, `*.turing.home`, `nas.home`, and `*.nas.home`.
2. **Import Root CA into Client OS**:
   * **macOS**: Drag `turing.crt` into **Keychain Access -> System -> Certificates**, double-click, and select **Always Trust**.
   * **Windows**: Run `certmgr.msc`, navigate to **Trusted Root Certification Authorities -> Certificates**, right-click, and choose **Import -> turing.crt**.
   * **Linux**: Copy `turing.crt` to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates`.
   * **Browsers (Firefox)**: Import `turing.crt` under **Settings -> Privacy & Security -> Certificates -> View Certificates -> Authorities -> Import**.
3. **Import into UGREEN NAS Portal**:
   * Open **Control Panel -> Security -> Certificate**.
   * Upload `turing.key` and `turing.crt`, then set as the default host certificate.
4. **Import into Nginx Proxy Manager**:
   * Open `https://proxy.turing.home` -> **SSL Certificates -> Add SSL Certificate -> Custom**.
   * Name: `Local Wildcard (turing.home + nas.home)`, Key: `turing.key`, Certificate: `turing.crt`.
   * Assign to all `*.turing.home` proxy hosts.

---

## 9. Tailscale Split-DNS Routing for Mobile & Remote Devices

To allow mobile phones and remote laptops to seamlessly access `<service>.turing.home` without modifying Wi-Fi settings or breaking regular internet DNS:

### Interactive Configuration
1. In the **Tailscale Admin Console**, navigate to **DNS -> Nameservers -> Add nameserver -> Custom**.
2. **Nameserver IP**: Enter `192.168.0.2` (Pi-hole LAN IP).
3. Check **Restrict to search domain** and enter **`.home`**.
4. Save the configuration.

### Ergonomic Result
* When remote devices query `<service>.kamaka.tech`, Tailscale routes the DNS query through the Subnet Router (`192.168.0.5`) to Pi-hole (`192.168.0.2`), resolving to Caddy (`192.168.0.4`).
* All standard internet queries (e.g. Google, GitHub) continue using local Wi-Fi/cellular DNS, maintaining maximum browsing speed without battery drain or DNS latency.

---

## 10. Privacy Exit Node on Untrusted Networks (`vpn-bridge`)

When traveling or connecting to public Wi-Fi (coffee shops, hotels, airports), remote devices can route all public internet traffic through the private WireGuard PIA VPN bridge without leaking the home ISP IP address.

### Interactive Configuration
1. Open the Tailscale client on your phone or laptop.
2. Select **Exit Nodes -> Choose Exit Node**.
3. Select **`vpn-bridge`**.

### Operational Behavior
* Client traffic encrypts across the Tailscale mesh to `vpn-bridge-tailscale`, traverses the internal container network namespace into `vpn-bridge-pia`, and exits through a high-bandwidth US WireGuard endpoint.
* Unlike standard exit nodes, your residential ISP connection is never exposed to public internet endpoints, and access to internal LAN resources (`192.168.0.0/24`) is preserved.

---

## 11. Atomic Hardlinking & Media Library Ergonomics

To avoid duplicating disk space and eliminate file copy delays when torrent downloads complete:

### Interactive Configuration
1. **Verify Unified Media Mounts**:
   In `media/compose.yml` and `torrent/compose.yml`, confirm all services mount the unified `${MEDIA_DIR}:/media` parent directory rather than isolated subfolder volumes.
2. **Enable Hardlinks in Radarr & Sonarr**:
   * In Radarr: Navigate to **Settings -> Media Management**. Under **Importing**, ensure **Use Hardlinks instead of Copy** is enabled.
   * In Sonarr: Navigate to **Settings -> Media Management**. Under **Importing**, ensure **Use Hardlinks instead of Copy** is enabled.
3. **Configure Media Paths**:
   * Set root movie folder in Radarr to `/media/movies`.
   * Set root series folder in Sonarr to `/media/tv`.
   * Completed qBittorrent downloads save to `/media/downloads`.

### Ergonomic Result
* When a download finishes, Radarr/Sonarr creates an atomic hardlink in `/media/movies` or `/media/tv` in less than one millisecond.
* No additional disk space is consumed, no mechanical disk read/write bandwidth is wasted copying gigabytes of data, and seeding continues undisturbed from `/media/downloads`.

---

## 12. Homepage Dashboard Personalization

The Homepage dashboard at `https://homepage.turing.home` provides a unified pane of glass for all homelab services, monitoring active streams, download rates, and system metrics.

### Interactive Configuration
1. Edit `.configs/homepage/services.yaml` to adjust service groups, display order, and custom icons.
2. Edit `.configs/homepage/widgets.yaml` to configure global header widgets (search providers, datetime, system hardware resources).
3. Verify API keys in `.env` (`RADARR_API_KEY`, `SONARR_API_KEY`, `JELLYFIN_API_KEY`, `HOMEPAGE_VAR_PIHOLE_KEY`) to activate real-time status counters on dashboard service cards.

---

# Part 3: Maintainability, Observability & Reliability

## 13. Container Log Rotation Invariants

Unconstrained container logs can grow indefinitely, consuming gigabytes of disk space and causing unnecessary journaling overhead.

### Configuration Standard
Ensure all newly authored or custom Compose stacks enforce the standard logging stanza:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```
This guarantees that no container log ever exceeds 30MB total on disk, preventing silent disk exhaustion.

---

## 14. Online Logical Database Staging & Backup Verification

Traditional container backup methods either stop containers (causing service downtime) or copy raw database files directly off disk (risking corruption if writes are mid-transaction).

### Operational Workflow
1. **Execute On-Demand Backup**:
   Run an online backup with a dedicated tag:
   ```bash
   sudo ./homelab.sh backup --tag initial-setup
   ```
   * Automation triggers zero-downtime logical dumps (`pg_dumpall` for PostgreSQL, SQLite `.backup` / WAL checkpoints for application databases) to `${DOCKER_DATA_DIR}/.backups`.
   * Restic deduplicates and encrypts snapshots into `${BACKUP_RESTIC_REPO}` (`/volume1/backups/homelab-docker`).
2. **Verify Scheduled Backup Automation**:
   Confirm the systemd daily backup timer is active:
   ```bash
   systemctl list-timers homelab-backup.timer
   ```
3. **Inspect Staged Snapshots**:
   ```bash
   sudo restic -r /volume1/backups/homelab-docker --insecure-no-password snapshots
   ```
4. **Perform a Granular Disaster Recovery Dry Run**:
   Verify restoration mechanics without impacting production data:
   ```bash
   # Dry-run or test restore of a specific service
   sudo ./homelab.sh restore latest jellyfin
   ```

---

## 15. Host Appliance OS Workaround Verification (`GODEBUG=tlskyber=0`)

On UGREEN NAS appliances running UGOS Pro (Linux kernel 5.15+), Go-based binaries (such as Tailscale and Cloudflare Tunnel) can encounter TLS handshake panics with Kyber quantum-resistant cipher negotiation.

### Verification & Remediation
Confirm the idempotent workaround is present:
* Check shell environment: `/etc/profile.d/go.sh` containing `export GODEBUG=tlskyber=0`.
* Check systemd daemon environment: `/etc/systemd/system.conf.d/godebug.conf` containing `DefaultEnvironment="GODEBUG=tlskyber=0"`.
* Re-running `./homelab.sh setup` automatically detects and restores these configurations if overwritten by host OS firmware updates.

---

## 16. Automated Smoke & Interconnect Verification

Whenever making host configuration adjustments, network edits, or stack updates, validate the entire environment in a single pass:

```bash
sudo ./homelab.sh test all
```

This automated smoke test suite verifies:
* Container runtime states and internal health probes across all 17 containers.
* Direct admin interfaces and emergency bypass ports (`8010:5001`).
* Client-impersonated virtual host routing over Caddy with automated TLS verification (`*.kamaka.tech`, `*.kamakakai.com`).
* Inter-container DNS resolution, database TCP sockets, REST API health, and WireGuard port synchronization.
* Security access control lists, external diagnostic endpoint blocking (`403 Forbidden`), and unauthenticated API rejections.
* Restic backup repository health and SemVer/CalVer tag auto-resolution.
