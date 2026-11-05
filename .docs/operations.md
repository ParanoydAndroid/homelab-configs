# Operations and Appliance Engineering

This document provides operational runbooks, automation procedures, host systemd service definitions, and appliance-level engineering documentation for the homelab environment.

---

## 1. Automation CLI Reference (`manage.sh`)

`manage.sh` is the central operational tool anchoring repository definitions to live host state:

```text
Usage: manage.sh <subcommand> [options]
```

### Subcommands

* **`setup`** (`sudo ./manage.sh setup`):
  Complete host and service convergence workflow. Remediates host OS Go 1.23+ bugs, initializes `.env` files, syncs root global variables into stack `.env` files, audits for blank secrets, provisions `homelab` and `external_npm` networks, deploys Dockge orchestrator compose, starts Dockge, and brings up all Compose stacks in dependency order.
* **`startup`** (`./manage.sh startup`):
  Non-interactive boot hook designed for systemd execution on host startup. Waits for storage volume mounts (up to 60s), ensures Docker networks exist, and launches Dockge and all stacks in dependency order.
* **`backup`** (`sudo ./manage.sh backup [-t <type|name>] [-m <message>]`):
  Stages zero-downtime database dumps (SQLite `.backup` / WAL checkpoints), creates untracked `.env` secret archives, and streams incremental deduplicated snapshots of `${DOCKER_DATA_DIR}` to `${BACKUP_RESTIC_REPO}` via native Restic (`--insecure-no-password`) with 30-day retention pruning. If requested, automatically commits repository changes, applies repeatable SemVer, CalVer, and custom git tags, pushes commits and tags to remote `origin`, and forwards the tags into Restic.
* **`snapshots`** (`./manage.sh snapshots`):
  Displays all historical Restic backup snapshots, timestamps, snapshot IDs, tags, and summary metrics.
* **`restore`** (`sudo ./manage.sh restore [snapshot_id] [service_name] [-f]`):
  Restores persistent volume state from a designated Restic snapshot (defaults to `latest`). Supports restoring the full volume or isolating a single service (e.g. `jellyfin`). Validates that containers mounting the volume are stopped before overwriting data, ensuring database coherence.
* **`test`** (`./manage.sh test [suite] [name]`):
  Modular smoke, regression, and conventions test suite verifying repository invariants, container runtimes, direct admin interfaces, client-impersonated virtual host routing over Caddy, internal service-to-service interconnections, negative security/isolation blocks, and restic backup automation.
* **`audit`** (`./manage.sh audit`):
  Runs baseline permissions, broken symlinks, environment template alignment, and container port exposure audits.
* **`hook`** (`./manage.sh hook [install|uninstall]`):
  Manages git hooks guarding the `main` branch during commits and pushes.

---

## 2. Common Operational Runbooks

### 2.1 Performing Volume Backups & Tagging Releases
```bash
cd ~/services

# Run standard volume backup (no git commit or tags created):
sudo ./manage.sh backup

# Snapshot volumes and auto-tag git and Restic with today's CalVer tag (e.g. 2026.11.1):
sudo ./manage.sh backup --tag

# Automatically bump SemVer patch, add CalVer tag, add custom tag, commit, and push:
sudo ./manage.sh backup -m "Release updates" -t semver-patch -t calver -t prod-ready

# Major / Minor version releases:
sudo ./manage.sh backup -m "Major architectural release" -t semver-major
sudo ./manage.sh backup -m "Feature release" -t semver-minor

# List all available snapshots and tags:
./manage.sh snapshots
```

### 2.2 Restoring from Backup (Disaster Recovery or Rollback)
To restore persistent volume data from the latest snapshot:
```bash
cd ~/services

# Stop running containers first to prevent database corruption during overwrite
docker compose stop

# Restore full volume from latest snapshot
sudo ./manage.sh restore latest

# Or restore an individual service only (e.g. mealie or jellyfin)
sudo ./manage.sh restore latest mealie

# Restart stacks
sudo ./manage.sh setup
```

### 2.3 Automated Nightly Backups (Systemd Timer)
Nightly backups are managed via `homelab-backup.timer`:
```bash
# Enable and start the nightly backup timer (runs at 03:00 daily)
sudo cp .configs/systemd/homelab-backup.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer

# Check timer status and next scheduled run
systemctl list-timers homelab-backup.timer
```

### 2.4 Restoring Secrets on a Fresh Host
To restore all `.env` secret files on a freshly provisioned host:
```bash
cd ~/services
tar -xzf "${DOCKER_DATA_DIR}/backup/homelab/latest_env_secrets.tar.gz" -C ~/services
sudo ./manage.sh setup
```

---

## 3. Host OS Configuration & Appliance Engineering

### 3.1 Host Packages & Prerequisites
The Debian 12 / UGOS Pro host operating system requires the following standard packages:
* **`restic`** (v0.19+): Used for incremental, deduplicated persistent volume snapshots and restores.
* **`sqlite3`**: Used for safe online SQLite database backups.
* **`rsync`**: Used for archive-grade data synchronization.
* **`tar` & `zstd`**: Used for compressed `.env` secret archives and volume backups.
* **`curl` & `jq`**: Used by test suites and health probes.

To install on Debian/UGOS Pro:
```bash
sudo apt update && sudo apt install -y sqlite3 rsync zstd curl jq
```

**User Lingering**:
Allows background user processes and systemd managers to persist when no interactive SSH session is active:
```bash
sudo loginctl enable-linger "${USER}"
```

---

## 4. Systemd Boot Services

Tracked unit definitions are maintained in `.configs/systemd/` and deployed to `/etc/systemd/system/`.

### 4.1 Antigravity Remote Control Daemon (`antigravity-remote-control.service`)
* **Unit File**: `/etc/systemd/system/antigravity-remote-control.service`
* **Tracked Template**: [.configs/systemd/antigravity-remote-control.service](../.configs/systemd/antigravity-remote-control.service)
* **Purpose**: Keeps the Google Antigravity Remote Control daemon (`Aumaka`) persistently online across system reboots.
* **Operational Behavior**:
  Runs `${HOME}/.gemini/bin/agy remote-control serve` as user `${USER}`. Includes an `ExecStartPre` polling loop that waits until the binary exists on disk before attempting startup, and sets `Restart=always` with `RestartSec=5s` so the daemon recovers instantly once user files are accessible.

To install or reload:
```bash
sudo cp ~/services/.configs/systemd/antigravity-remote-control.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now antigravity-remote-control.service
```

### 4.2 Homelab Startup Orchestrator (`homelab-startup.service`)
* **Unit File**: `/etc/systemd/system/homelab-startup.service`
* **Tracked Template**: [.configs/systemd/homelab-startup.service](../.configs/systemd/homelab-startup.service)
* **Purpose**: Automatically initializes Docker networks, Dockge, and all application stacks in strict dependency order on host boot.
* **Operational Behavior**:
  Executes `${HOME}/services/manage.sh startup` after `docker.service` and `storage_serv.service` reach readiness.

To install or reload:
```bash
sudo cp ~/services/.configs/systemd/homelab-startup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable homelab-startup.service
```

### 4.3 Automated Nightly Backup Units (`homelab-backup.service` & `homelab-backup.timer`)
* **Unit Files**: `/etc/systemd/system/homelab-backup.service`, `/etc/systemd/system/homelab-backup.timer`
* **Tracked Templates**:
  - [.configs/systemd/homelab-backup.service](../.configs/systemd/homelab-backup.service)
  - [.configs/systemd/homelab-backup.timer](../.configs/systemd/homelab-backup.timer)
* **Purpose**: Orchestrates non-disruptive nightly Restic snapshots of persistent volume state to `/volume1/backups/homelab-docker` with 30-day retention pruning.
* **Operational Behavior**:
  The systemd timer fires at 03:00 daily, triggering `homelab-backup.service` which executes `manage.sh backup` (or with automated flags such as `-t calver -m "chore(backup): scheduled volume snapshot"`).

To install or reload:
```bash
sudo cp ~/services/.configs/systemd/homelab-backup.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer
```

---

## 5. Asynchronous Storage Mounts & OS Workarounds

### Asynchronous Storage Mount Handling in UGOS Pro
On UGREEN NAS OS, user home directories (`${HOME}`) and secondary storage pools (`/volume2`) are mounted **asynchronously** by UGREEN's internal storage daemon (`storage_serv`) well after systemd's early boot phase.

* **Why Standard User Units (`systemd --user`) Fail**:
  When systemd launches `user@1000.service`, `${HOME}` is not yet mounted. As a result, `systemd --user` processes an empty directory, misses user unit files in `~/.config/systemd/user/`, and reaches `default.target` prematurely without starting user daemons.
* **Architectural Remediation**:
  Critical background services (like Antigravity Remote Control and Homelab Stack Orchestration) are placed in `/etc/systemd/system/` under `multi-user.target`, bound to `User=${USER}`, and equipped with startup polling loops.

### Appliance OS Workaround (Go 1.23+ GODEBUG Fix)
UGREEN NAS OS injects `GODEBUG=tlskyber=0` into `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`. Because Go 1.23 removed the legacy `tlskyber` setting, Go 1.23+ binaries (including developer tools, telemetry agents, and remote servers) panic on startup.

`sudo ./manage.sh setup` automatically remediates this idempotently on every run. To apply manually:
```bash
sudo sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
sudo sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
sudo systemctl unset-environment GODEBUG
systemctl --user unset-environment GODEBUG || true
sudo systemctl daemon-reexec
```

---

## 6. Host & Storage Performance Tuning

For post-setup best practices and interactive configurations across performance optimization, anti-thrashing, client ergonomics, and maintainability, see the dedicated [Post-Setup Optimization, Ergonomics & Maintenance Guide](./performance-optimization.md).
