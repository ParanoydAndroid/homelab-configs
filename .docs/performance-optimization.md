# Performance Optimization & Anti-Thrashing Best Practices

This guide outlines recommended architectural and operational best practices for maximizing container performance, eliminating disk thrashing, and reducing storage wear in homelab environments.

> **Design Philosophy & Scope**:
> These optimizations are **recommended best practices, not mandatory requirements**. The homelab stack, Compose definitions, and `homelab.sh` lifecycle automation are designed to be fully compatible with single-volume storage architectures (such as a single mechanical RAID array on `/volume1`). Apply these recommendations based on available hardware, drive topology, and performance requirements.

---

## 1. Storage Tiering & Volume Topology

### The Tiered Architecture (NVMe SSD + Mechanical RAID)
Where dual-volume hardware is available, separating high-IOPS random transactions from high-capacity sequential storage delivers the most responsive user experience:

| Tier | Typical Hardware | Target Workload | Workload Characteristics |
| :--- | :--- | :--- | :--- |
| **High-IOPS Tier** (`/volume2`) | PCIe NVMe or SATA SSD | Container state (`${DOCKER_DATA_DIR}`), SQLite databases, image thumbnails, cache directories. | Random 4KB reads/writes, high queue depths, sub-millisecond seek latency. |
| **Bulk Capacity Tier** (`/volume1`) | Multi-disk mechanical RAID 5/6 | Bulk media libraries (`${MEDIA_DIR}`), completed downloads, restic backup archives. | Large sequential streaming reads/writes, multi-gigabyte continuous file transfers. |

### Single-Volume Compatibility
If running a single RAID volume (e.g., all data residing on `/volume1`):
- All stacks remain completely functional by setting `DOCKER_DATA_DIR=/volume1/docker` and `MEDIA_DIR=/volume1/media` in the root `.env`.
- Storage tiering is an optimization rather than a hard dependency. On single-volume setups, prioritize the Btrfs No-CoW and virtual memory tuning steps below to minimize mechanical disk contention.

---

## 2. Docker Daemon Root (`data-root`) Placement

By default, Docker stores images, container writeable overlayfs layers, and local volumes under `/var/lib/docker` (or `/volume1/@docker` on UGREEN NAS). 

### Optimization
Directing Docker's `data-root` to solid-state storage (e.g. `/volume2/@docker`) ensures that:
1. Container image layer pulls, unpacks, and builds occur at NVMe bus speeds without mechanical drive head contention.
2. Writable overlayfs layers for active containers do not compete with bulk media streaming on the mechanical array.

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

## 3. BitTorrent I/O & Network Optimization (qBittorrent)

BitTorrent traffic downloads files non-sequentially in unaligned pieces (typically 16KB to 2MB). Unoptimized default settings can cause severe mechanical drive thrashing, extreme Btrfs fragmentation, and unnecessary network chatter. 

The following settings in `qBittorrent.conf` optimize I/O throughput and network behavior:

### 3.1 Incomplete Download Buffering on Solid-State Storage
Buffer active downloads on solid-state storage and transfer completed files to mechanical storage sequentially:

```yaml
volumes:
  # High-IOPS buffer for active peer writes
  - ${DOCKER_DATA_DIR:?See env.example for default.}/qbittorrentvpn/data/incomplete:/incomplete
  # Sequential storage for completed torrents
  - ${MEDIA_DIR:?See env.example for default.}/downloads:/media/downloads
```
* **Configuration**: In qBittorrent (**Options -> Downloads**), enable **"Keep incomplete torrents in:"** and set the path to `/incomplete` (`Session\TempPath=/incomplete` and `Session\TempPathEnabled=true`).
* **I/O Benefit**: Absorbs random unaligned chunk writes on SSD; completed payloads are written sequentially to the RAID array in a single continuous stream, minimizing mechanical head seeks.

### 3.2 RAM Write Cache (`Session\DiskQueueSize`)
Allows incoming network chunks to buffer in memory before being committed to physical storage:
* **Configuration (`qBittorrent.conf`)**:
  ```ini
  [BitTorrent]
  Session\DiskQueueSize=536870912
  ```
  *(In WebUI: **Options -> Advanced -> Disk queue size / Physical memory write cache** set to 512 MiB or higher).*
* **I/O Benefit**: Prevents synchronous disk writes on every packet receipt, coalescing fragmented blocks in RAM so the filesystem can write larger, contiguous extents.

### 3.3 Piece Extent Affinity (`Session\PieceExtentAffinity`)
Forces the libtorrent download engine to prioritize completing contiguous file regions (extents) rather than downloading scattered pieces across the entire file payload:
* **Configuration (`qBittorrent.conf`)**:
  ```ini
  [BitTorrent]
  Session\PieceExtentAffinity=true
  ```
* **I/O Benefit**: Significantly reduces file fragmentation on copy-on-write filesystems (Btrfs) and mechanical disks. Keeps active write heads constrained to localized disk sectors.

### 3.4 Suggest Mode & Peer Advertising (`Session\SuggestMode`)
Enables BEP 54 (libtorrent suggest mode), which allows the client to suggest preferred contiguous pieces to connected peers:
* **Configuration (`qBittorrent.conf`)**:
  ```ini
  [BitTorrent]
  Session\SuggestMode=true
  ```
* **Network & I/O Benefit**: Encourages swarm peers to upload pieces that align with the client's contiguous allocation extents, reducing random block distribution.

### 3.5 Interface Affinity & UPnP Disabling
Secures network routing and disables redundant router discovery:
* **Interface Binding**: Bind qBittorrent strictly to the WireGuard tunnel interface (`wg0`):
  ```ini
  [BitTorrent]
  Session\Interface=wg0
  Session\InterfaceName=wg0
  ```
  *Provides defense-in-depth binding libtorrent sockets directly to the VPN interface, preventing socket creation on host interfaces if container namespaces change.*
* **Disable UPnP / NAT-PMP Advertising**:
  ```ini
  [Network]
  PortForwardingEnabled=false
  [WebUI]
  UseUPnP=false
  ```
  *Since qBittorrent runs behind a WireGuard VPN tunnel, router-level UPnP and NAT-PMP requests are ineffective and generate useless LAN discovery traffic. Dynamic port forwarding is handled exclusively by the PIA forwarding script (`set-qbt-port.sh`).*

---

## 4. Btrfs Copy-on-Write (No-CoW) Optimization

On Btrfs filesystems, the Copy-on-Write (CoW) feature causes severe file fragmentation and write amplification when modifying databases (PostgreSQL, SQLite) or updating downloading torrent files in-place.

### Optimization
Disable Copy-on-Write on active database and temporary download directories before populating data:

```bash
# Disable CoW on newly created directories
sudo chattr +C /volume2/docker/postgres/data
sudo chattr +C /volume2/docker/nginx/data
sudo chattr +C /volume2/docker/qbittorrentvpn/data/incomplete
```

### Verification
```bash
lsattr -d /volume2/docker/postgres/data
# Output should show 'C' flag: ---------------C------
```
*Note: This optimization is especially valuable on single mechanical RAID Btrfs arrays, where CoW fragmentation degrades read performance significantly over time.*

---

## 5. Linux Virtual Memory Dirty Ratio Smoothing

Default Linux kernel settings allow up to 20% of total system memory to accumulate unwritten "dirty" pages before forcing flushes to disk. On high-RAM systems with mechanical storage arrays, this can trigger periodic 10–30 second system-wide I/O lockups when gigabytes of buffered writes flush simultaneously.

### Optimization
Smooth out disk write patterns by lowering dirty memory flush thresholds in `/etc/sysctl.d/99-homelab-io.conf`:

```ini
# Start background flushing earlier in small, continuous batches
vm.dirty_background_ratio = 5

# Cap maximum dirty memory to prevent large blocking flush spikes
vm.dirty_ratio = 10
```

Apply immediately:
```bash
sudo sysctl --system
```

---

## 6. In-Memory Transcoding Caches (`tmpfs`)

Media servers like Jellyfin transcode incompatible video streams on the fly, writing temporary HLS video segments every 2 to 6 seconds. Writing transcode segments to physical disks generates continuous disk activity and unnecessary write cycles.

### Optimization
Mount an in-memory `tmpfs` volume for transcode scratch space:

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    tmpfs:
      - /transcode:size=4G,mode=1777
```
* Point Jellyfin's transcode path to `/transcode` under **Dashboard -> Playback -> Transcoding**.
* Temporary video segments exist strictly in RAM and evaporate upon stream completion.

---

## 7. Container Log Rotation Invariants

Unconstrained container logs can grow indefinitely, consuming gigabytes of disk space and causing unnecessary journaling overhead.

### Optimization
Enforce standard log rotation limits across every service block in `compose.yml`:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```
This guarantees that no container log ever exceeds 30MB total on disk.

---

## 8. Read-Only Media Mount Enforcement (`:ro`)

Services that only consume media (e.g. Jellyfin for playback, Seerr for requests) should never mount media storage with write permissions.

### Optimization
Append `:ro` to volume mappings for read-only consumers:

```yaml
volumes:
  - ${MEDIA_DIR:?See env.example for default.}:/data:ro
```
This prevents accidental modification, avoids acquiring unnecessary directory write locks on the host filesystem, and strengthens container defense-in-depth.

---

## 9. Online Logical Database Staging

Traditional container backup methods either stop containers (causing service downtime) or copy raw database files directly off disk (risking corruption if writes are mid-transaction).

### Optimization
Use logical dump utilities (`pg_dumpall` for PostgreSQL, SQLite `.backup` / WAL checkpoints for application databases) to stage hot, consistent database backups to `${DOCKER_DATA_DIR}/.backups` before snapshotting. This is automated by `./homelab.sh backup`, ensuring zero container downtime and zero transactional locking.
