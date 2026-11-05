---
name: homelab-audit
description: >-
  Systematic drift detection and compliance auditing runbook for homelab infrastructure.
  Audits container runtimes, service & image drift, untracked containers, environment
  variable skew, volume permissions (UID/GID and ACLs), Btrfs No-CoW flags, reverse
  proxy virtual host alignment, external security blocks, scheduled backup timer health,
  and host system service drift (systemd units, sysctl parameters, Docker daemon configs).
---

# Homelab Drift Detection & Infrastructure Audit Runbook

This skill provides a systematic diagnostic procedure to detect drift between tracked declarative configurations (`compose.yml`, `.env`, documentation, rules) and the live host runtime state.

---

## Audit Checklist & Procedures

### Audit Area 1: Service & Configuration Drift Detection

1. **Container Tracking Alignment**:
   Compare live running containers against declarative `compose.yml` service definitions:
   ```bash
   # Extract declared container names across all discovered stacks
   grep -rhE "^[[:space:]]*container_name:" */compose.yml | awk '{print $2}' | sort -u
   # Query running container names
   docker ps --format '{{.Names}}' | sort -u
   ```
   - **Untracked Containers**: Running containers not defined in any `compose.yml` stack.
   - **Missing/Stopped Services**: Declared containers that are missing from `docker ps`.

2. **Container Image & Tag Digest Drift**:
   Verify whether running containers have drifted from updated local images or declared tags:
   ```bash
   for c in $(docker ps --format '{{.Names}}'); do
     running_id="$(docker inspect -f '{{.Image}}' "${c}")"
     image_tag="$(docker inspect -f '{{.Config.Image}}' "${c}")"
     latest_id="$(docker image inspect -f '{{.Id}}' "${image_tag}" 2>/dev/null || echo "unknown")"
     if [[ "${latest_id}" != "unknown" && "${running_id}" != "${latest_id}" ]]; then
       echo "IMAGE DRIFT: Container '${c}' is running outdated image digest (recreate required)"
     fi
   done
   ```

3. **Environment Variable & Secret Skew**:
   - Check that all variables in `<stack>/.env.example` exist in `<stack>/.env`.
   - Verify that root global variables (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `PUID`, `PGID`, `TZ`) are synchronized identically across all `<stack>/.env` files:
     ```bash
     for env_file in */.env; do
       echo "--- ${env_file} ---"
       grep -E "^(DOCKER_DATA_DIR|MEDIA_DIR|PUID|PGID|TZ)=" "${env_file}" || true
     done
     ```
   - Identify any blank required secrets (`KEY=`) or unexpanded variable templates.

4. **Volume Mount & Read-Only Flag Drift**:
   - Verify that container volume destinations match declarations in `compose.yml`.
   - Audit read-only enforcement on consuming services:
     ```bash
     # Verify Jellyfin media volume is strictly read-only
     docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data/media"}}{{.ReadOnly}}{{end}}{{end}}' jellyfin
     ```
     Output must be `true`.

5. **Host Port Exposure Drift**:
   - Verify that no unintended host ports are bound:
     ```bash
     docker ps --format 'table {{.Names}}\t{{.Ports}}'
     ```
   - In accordance with the homelab port exposure model, only `dockge` (`8010:5001`) and `jellyfin` (`8022:7359/udp`) may bind host ports. All other services must route exclusively over the `homelab` bridge network.

6. **Documentation & Service Catalog Drift**:
   - Cross-reference `.docs/service-catalog.md` against discovered stacks in `STACKS`:
     - Are any stacks present in the filesystem that are missing from `.docs/service-catalog.md`?
     - Do volume mount paths in `.docs/service-catalog.md` match live `compose.yml` mounts?

---

### Audit Area 2: Storage Permissions & Extended ACL Attributes
1. **Non-Root Ownership (`1000:100`)**:
   Verify non-root service data directories adhere to `1000:100`:
   ```bash
   find /volume2/docker -maxdepth 2 -not -user 1000 -not -user root -not -user 70
   ```
2. **UGOS Proprietary ACL Inspection (`system.ugacl_self`)**:
   Check if host filesystem manipulation attached proprietary extended attributes that mask permissions:
   ```bash
   getfattr -d -m "system.ugacl_self" /volume2/docker/qbittorrent/data/incomplete 2>/dev/null || true
   ```
   *Remediation*: If present, strip via `setfattr -x system.ugacl_self <path>` and re-apply `chmod 775`.
3. **Btrfs Copy-on-Write (No-CoW) Verification**:
   Verify that database and incomplete download directories carry the `+C` flag:
   ```bash
   lsattr -d /volume2/docker/postgres/data /volume2/docker/nginx/data /volume2/docker/qbittorrent/data/incomplete
   ```
   Output must show `---------------C----`.

---

### Audit Area 3: Reverse Proxy & Ingress Virtual Hosts
1. **Run Full Routing Suite**:
   ```bash
   ./homelab.sh test routing
   ```
2. **Verify SSL Expiration**:
   Check expiration date on local root certificate:
   ```bash
   openssl x509 -enddate -noout -in .configs/nginx/turing.crt
   ```
3. **External Endpoint Hardening**:
   Ensure external domains reject diagnostic endpoints:
   ```bash
   ./homelab.sh test security
   ```

---

### Audit Area 4: WireGuard VPN & Ingress Daemons
1. **Port Sync Check**:
   Confirm PIA port forward lease matches qBittorrent listen port:
   ```bash
   docker exec wireguard-pia cat /pia-shared/port.dat
   ```
2. **Tailscale & Exit Node Backend State**:
   Confirm both Tailscale containers are in `BackendState: Running`:
   ```bash
   docker exec tailscale tailscale status --json | grep '"BackendState"'
   docker exec vpn-bridge-tailscale tailscale status --json | grep '"BackendState"'
   ```

---

### Audit Area 5: Backup Automation & Snapshot Currency
1. **Systemd Backup Timer**:
   Verify the nightly backup timer is active:
   ```bash
   systemctl list-timers homelab-backup.timer
   ```
2. **Latest Snapshot Age**:
   Confirm the latest Restic snapshot is younger than 24 hours:
   ```bash
   sudo restic -r /volume1/backups/homelab-docker --insecure-no-password snapshots --latest 1
   ```

---

### Audit Area 6: Host System Services & Daemon Drift Detection

1. **Systemd Unit File & Template Drift**:
   Compare installed systemd unit files in `/etc/systemd/system/` against repository source templates in `.configs/systemd/`:
   ```bash
   for unit in homelab-startup.service homelab-backup.service homelab-backup.timer; do
     if [[ -f "/etc/systemd/system/${unit}" ]]; then
       diff -u "${REPO_DIR}/.configs/systemd/${unit}" "/etc/systemd/system/${unit}" || echo "DRIFT DETECTED: /etc/systemd/system/${unit} differs from repository template"
     else
       echo "MISSING UNIT: /etc/systemd/system/${unit} is not installed"
     fi
   done
   ```
   - Verify that `WorkingDirectory` and `ExecStart` inside `homelab-startup.service` point to the current repository directory.

2. **System Service Enablement & Timer Scheduling**:
   - Check service and timer enablement:
     ```bash
     systemctl is-enabled homelab-startup.service
     systemctl is-enabled homelab-backup.timer
     ```
   - Check timer active state and next scheduled trigger:
     ```bash
     systemctl list-timers homelab-backup.timer
     ```
     Flag if the timer is inactive, stopped, or missing from the active timer list.

3. **Docker Daemon Configuration Drift (`/etc/docker/daemon.json`)**:
   - Validate live daemon configuration against recommended storage and logging parameters:
     ```bash
     cat /etc/docker/daemon.json
     ```
   - Assert:
     - `"data-root"` matches high-IOPS storage (e.g. `"/volume2/@docker"`).
     - `"log-driver": "json-file"` is declared.
     - `"log-opts": {"max-size": "10m", "max-file": "3"}` is enforced.
   - Detect if host OS firmware updates reverted or wiped `daemon.json`.

4. **Kernel Parameters & Sysctl Drift (`/etc/sysctl.d/` vs Live `/proc/sys/`)**:
   - Verify that dirty memory thresholds match recommended anti-thrashing values:
     ```bash
     bg_ratio="$(cat /proc/sys/vm/dirty_background_ratio)"
     dirty_ratio="$(cat /proc/sys/vm/dirty_ratio)"
     echo "Live dirty_background_ratio: ${bg_ratio} (expected: 5)"
     echo "Live dirty_ratio: ${dirty_ratio} (expected: 10)"
     ```
   - Verify IPv4 transit forwarding is enabled for Tailscale routing:
     ```bash
     cat /proc/sys/net/ipv4/ip_forward
     ```
     Output must be `1`.

5. **Appliance OS Firmware Workarounds**:
   - On UGREEN NAS appliances, verify that firmware updates have not reinjected the Kyber TLS defect:
     ```bash
     grep -qE '^[[:space:]]*export GODEBUG=tlskyber=0' /etc/profile.d/go.sh && echo "DRIFT: Kyber defect reinjected into /etc/profile.d/go.sh"
     grep -qE '^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"' /etc/systemd/system.conf && echo "DRIFT: Kyber defect reinjected into /etc/systemd/system.conf"
     ```

6. **Host Convenience Symlink Integrity**:
   - Verify that `/home/${USER}/services` exists and points to the repository root:
     ```bash
     target="$(readlink -f "${HOME}/services" 2>/dev/null || echo "missing")"
     echo "services symlink target: ${target} (expected: ${REPO_DIR})"
     ```
   - Verify that Dockge orchestrator compose file `${DOCKGE_DIR}/compose.yml` matches `.configs/dockge/compose.yml`.

---

## Audit Output Report

Compile findings into a prioritized punchlist categorized by operational severity:
- **Clean**: All declarative declarations match live runtime state with zero drift across both containers and host system services.
- **Service & System Drift Warning**:
  - Image digest skew (container running older digest than local image tag).
  - Environment variable skew across stack `.env` files.
  - Snapshot currency > 24 hours or missing Btrfs `+C` flag on active database directory.
  - Missing service catalog documentation for newly deployed stack.
  - Systemd unit file differences between `.configs/systemd/` and `/etc/systemd/system/`.
  - Reverted Linux kernel sysctl parameters (`vm.dirty_background_ratio` != 5 or `vm.dirty_ratio` != 10).
  - Broken convenience symlinks (`~/services`).
- **Critical / Security Hazard**:
  - Untracked or orphaned containers running on host.
  - Unauthorized host port mappings exposing backend services to LAN/WAN.
  - Service container outage or failed container health probe.
  - Broken reverse proxy routing or failed security hardening block (`403 Forbidden`).
  - Storage permission denial or UGOS proprietary ACL flags (`system.ugacl_self`) blocking container writes.
  - Disabled or inactive daily backup timer (`homelab-backup.timer`).
  - Reinjected appliance OS defects (`GODEBUG=tlskyber=0`).
