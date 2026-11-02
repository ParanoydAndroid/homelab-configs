# Hardware & Appliance OS Adaptation Runbook

This reference provides platform-specific detection commands, quirks, and configuration adaptations when onboarding a homelab on different host hardware and appliance operating systems.

---

## 1. Host Platform Quirks & Remediations

### UGREEN NAS (UGOS Pro / Linux 5.15+ / 6.x)
- **Known Quirk 1: Go Kyber TLS Panics**:
  - *Symptom*: Go binaries (Tailscale, Cloudflare Tunnel, Restic) panic with TLS handshake errors.
  - *Remediation*: Comment out `export GODEBUG=tlskyber=0` in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`.
- **Known Quirk 2: Proprietary ACL Flag (`system.ugacl_self`)**:
  - *Symptom*: Non-root container processes (UID 1000) receive `Permission denied` on newly created folders via UGOS file manager, even if `chmod` is 777.
  - *Remediation*: Strip extended attribute inside container or host:
    ```bash
    setfattr -x system.ugacl_self /path/to/folder
    chmod 775 /path/to/folder
    ```
- **Known Quirk 3: Docker Root Location**:
  - By default UGOS sets Docker data-root to `/volume1/@docker`. If `/volume2` is an NVMe SSD array, relocate `data-root` to `/volume2/@docker` in `/etc/docker/daemon.json`.

### Synology DSM (DSM 7.x)
- **Known Quirk 1: TUN Device for Tailscale/VPN**:
  - *Symptom*: `/dev/net/tun` missing or permissions denied.
  - *Remediation*: Add scheduled startup script in Control Panel -> Task Scheduler:
    ```bash
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
    ```
- **Known Quirk 2: Port Conflicts**:
  - Synology DSM reserves ports 5000 and 5001. Dockge's emergency fallback mapping uses `8010:5001` on host, avoiding collision.

### Generic Linux (Debian, Ubuntu, Arch, unRAID)
- Standard systemd support.
- Verify `net.ipv4.ip_forward = 1` in `/etc/sysctl.d/99-homelab-forwarding.conf` for Tailscale subnet routing.
- Check render node permissions (`/dev/dri/renderD128`) and resolve host group ID:
  ```bash
  stat -c '%g' /dev/dri/renderD128
  ```
  Update `group_add: ["<gid>"]` in `jellyfin/compose.yml` to match host render group.

---

## 2. Storage Topologies

| Metric | Single Volume (`/volume1`) | Dual-Tier (`/volume2` SSD + `/volume1` HDD) |
| :--- | :--- | :--- |
| **`DOCKER_DATA_DIR`** | `/volume1/docker` | `/volume2/docker` (High IOPS, sub-ms latency) |
| **`MEDIA_DIR`** | `/volume1/media` | `/volume1/media` (High capacity, sequential streaming) |
| **Btrfs CoW Strategy** | Must apply `chattr +C` to databases and incomplete download directories. | Apply `chattr +C` to incomplete downloads and databases on SSD. |
| **Docker `data-root`** | `/volume1/@docker` | `/volume2/@docker` |

---

## 3. Hardware Transcoding & RAM Sizing

1. **GPU Acceleration**:
   - Intel QuickSync: Mount `/dev/dri/renderD128:/dev/dri/renderD128` with host render GID.
   - NVIDIA: Replace `devices` with `deploy.resources.reservations.devices` and driver `nvidia`.
   - CPU Fallback: If no hardware encoder exists, remove `/dev/dri` device mounts and `group_add` from `jellyfin/compose.yml`.
2. **RAM Sizing for `tmpfs`**:
   - Host >= 16GB RAM: Set Jellyfin transcode `tmpfs: [/transcode:size=4G,mode=1777]`.
   - Host 8GB RAM: Set `tmpfs: [/transcode:size=2G,mode=1777]`.
   - Host < 8GB RAM: Omit `tmpfs` and transcode to SSD cache directory on disk (`${DOCKER_DATA_DIR}/jellyfin/data/transcodes`).
