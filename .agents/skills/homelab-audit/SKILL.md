---
name: homelab-audit
description: >-
  Systematic drift detection and compliance auditing runbook for homelab infrastructure.
  Audits container runtimes, untracked containers, volume permissions (UID/GID and ACLs),
  Btrfs No-CoW flags, reverse proxy virtual host alignment, external security blocks,
  and scheduled backup timer health.
---

# Homelab Drift Detection & Infrastructure Audit Runbook

This skill provides a systematic diagnostic procedure to detect drift between tracked declarative configurations (`compose.yml`, `.env`, rules) and the live host runtime state.

---

## Audit Checklist & Procedures

### Audit Area 1: Container Runtime & Tracking Alignment
1. **Assert Tracked Container Health**:
   Run the automated container suite:
   ```bash
   ./homelab.sh test containers
   ```
2. **Detect Untracked / Orphaned Containers**:
   Compare running container names against declared services in `compose.yml` files:
   ```bash
   docker ps --format '{{.Names}}' | sort
   ```
   Investigate any running containers not managed by a stack in `${REPO_DIR}/*/compose.yml`.

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
   getfattr -d -m "system.ugacl_self" /volume2/docker/qbittorrentvpn/data/incomplete 2>/dev/null || true
   ```
   *Remediation*: If present, strip via `setfattr -x system.ugacl_self <path>` and re-apply `chmod 775`.
3. **Btrfs Copy-on-Write (No-CoW) Verification**:
   Verify that database and incomplete download directories carry the `+C` flag:
   ```bash
   lsattr -d /volume2/docker/postgres/data /volume2/docker/nginx/data /volume2/docker/qbittorrentvpn/data/incomplete
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

## Audit Output Report

Compile findings into a prioritized punchlist:
- **Clean**: All checks passed.
- **Warning**: Non-fatal drift (e.g. Btrfs `+C` missing on a directory, or snapshot > 24 hours old).
- **Critical**: Service outage, failed security hardening block, or permission denial blocking writes.
