# Operations and Appliance Engineering

This document provides operational runbooks, automation procedures, host systemd service definitions, and appliance-level engineering documentation for the homelab environment.

---

## 1. Automation CLI Reference (`homelab.sh`)

`homelab.sh` is the central operational tool anchoring repository definitions to live host state:

```text
Usage: homelab.sh <subcommand> [options]
```

### Subcommands

* **`setup`** (`sudo ./homelab.sh setup [-O | -K]`):
  Complete host and service convergence workflow. Remediates host OS Go 1.23+ bugs, initializes `.env` files, syncs root global variables into stack `.env` files, audits for blank secrets, provisions `homelab` and `external_npm` networks, deploys tracked configurations, starts Dockge, and brings up all Compose stacks in dependency order.
* **`startup`** (`./homelab.sh startup`):
  Non-interactive boot hook designed for systemd execution on host startup. Waits for storage volume mounts (up to 60s), ensures Docker networks exist, and launches Dockge and all stacks in strict dependency order with PostgreSQL database readiness verification.
* **`deploy-configs`** (`./homelab.sh deploy-configs [-O | -K]`):
  Synchronizes tracked configuration files from `.configs/` to live host volumes (`${DOCKER_DATA_DIR}/...`). Compares files using byte-level checks (`cmp -s`), displays unified diffs (`diff -u`) on conflict, validates referenced SSL certificates before installing NPM `.conf` files, and gracefully reloads Nginx upon change.
* **`pull-configs`** (`./homelab.sh pull-configs`):
  Extracts live configuration changes made through Web UIs (Homepage YAML, NPM SQLite routing tables, generated Nginx `.conf` files, and `set-qbt-port.sh`) back into `.configs/` for git review and version control.
* **`backup`** (`./homelab.sh backup [-t [tag_name]] [-m <message>]`):
  Pulls live service configurations, stages and commits tracked repository changes, optionally applies a chronological PEP 440 / CalVer tag (`YYYY.M.D[.N]`) or semantic tag, and creates an archive of all live untracked `.env` secret files in `${DOCKER_DATA_DIR}/backup/homelab/`.
* **`test`** (`./homelab.sh test [suite] [name]`):
  Modular smoke and regression test suite verifying container runtimes, direct admin interfaces, client-impersonated virtual host routing over NPM, internal service-to-service interconnections, and negative security/isolation blocks.

---

## 2. Common Operational Runbooks

### 2.1 Editing Proxy Hosts in NPM & Versioning in Git
1. Configure proxy hosts in the NPM Admin UI at `https://proxy.turing.home` (or `http://192.168.0.4:81`).
2. Pull the updated SQLite dump and generated `.conf` files back into the repository:
   ```bash
   cd ~/services
   ./homelab.sh pull-configs
   git diff .configs/nginx/
   git add .configs/nginx/
   git commit -m "Update NPM proxy host configuration"
   ```

### 2.2 Updating Homepage Dashboard YAML
1. Edit [.configs/homepage/services.yaml](file:///home/brandon/services/.configs/homepage/services.yaml) or [.configs/homepage/settings.yaml](file:///home/brandon/services/.configs/homepage/settings.yaml).
2. Deploy the changes to the live volume:
   ```bash
   ./homelab.sh deploy-configs
   ```

### 2.3 Creating Backups and Tagging Releases
```bash
cd ~/services

# Run full backup with automatic chronological tag (e.g., 2026.10.30):
./homelab.sh backup --tag

# Run backup with custom commit message and semantic tag:
./homelab.sh backup -m "Release 2.3.0: Storage optimizations" --tag 2.3.0

# Push history and tags to GitHub:
git push && git push --tags
```

### 2.4 Restoring Secrets on a Fresh Host
To restore all `.env` secret files on a freshly provisioned host:
```bash
cd ~/services
tar -xzf "${DOCKER_DATA_DIR:-/volume2/docker}/backup/homelab/latest_env_secrets.tar.gz" -C ~/services
sudo ./homelab.sh setup
```

---

## 3. Host OS Configuration & Appliance Engineering

### 3.1 Host Packages & Prerequisites
The Debian 12 / UGOS Pro host operating system requires the following standard packages:
* **`sqlite3`**: Used by `pull-configs` and `backup` for non-sensitive SQL table dumps.
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
sudo loginctl enable-linger brandon
```

---

## 4. Systemd Boot Services

Tracked unit definitions are maintained in `.configs/systemd/` and deployed to `/etc/systemd/system/`.

### 4.1 Antigravity Remote Control Daemon (`antigravity-remote-control.service`)
* **Unit File**: `/etc/systemd/system/antigravity-remote-control.service`
* **Tracked Template**: [.configs/systemd/antigravity-remote-control.service](file:///home/brandon/services/.configs/systemd/antigravity-remote-control.service)
* **Purpose**: Keeps the Google Antigravity Remote Control daemon (`Aumaka`) persistently online across system reboots.
* **Operational Behavior**:
  Runs `/home/brandon/.gemini/bin/agy remote-control serve` as user `brandon`. Includes an `ExecStartPre` polling loop that waits until the binary exists on disk before attempting startup, and sets `Restart=always` with `RestartSec=5s` so the daemon recovers instantly once user files are accessible.

To install or reload:
```bash
sudo cp ~/services/.configs/systemd/antigravity-remote-control.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now antigravity-remote-control.service
```

### 4.2 Homelab Startup Orchestrator (`homelab-startup.service`)
* **Unit File**: `/etc/systemd/system/homelab-startup.service`
* **Tracked Template**: [.configs/systemd/homelab-startup.service](file:///home/brandon/services/.configs/systemd/homelab-startup.service)
* **Purpose**: Automatically initializes Docker networks, Dockge, and all application stacks in strict dependency order on host boot.
* **Operational Behavior**:
  Executes `/home/brandon/services/homelab.sh startup` after `docker.service` and `storage_serv.service` reach readiness.

To install or reload:
```bash
sudo cp ~/services/.configs/systemd/homelab-startup.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable homelab-startup.service
```

---

## 5. Asynchronous Storage Mounts & OS Workarounds

### Asynchronous Storage Mount Handling in UGOS Pro
On UGREEN NAS OS, user home directories (`/home/<user>`) and secondary storage pools (`/volume2`) are mounted **asynchronously** by UGREEN's internal storage daemon (`storage_serv`) well after systemd's early boot phase.

* **Why Standard User Units (`systemd --user`) Fail**:
  When systemd launches `user@1000.service`, `/home/brandon` is not yet mounted. As a result, `systemd --user` processes an empty directory, misses user unit files in `~/.config/systemd/user/`, and reaches `default.target` prematurely without starting user daemons.
* **Architectural Remediation**:
  Critical background services (like Antigravity Remote Control and Homelab Stack Orchestration) are placed in `/etc/systemd/system/` under `multi-user.target`, bound to `User=brandon`, and equipped with startup polling loops.

### Appliance OS Workaround (Go 1.23+ GODEBUG Fix)
UGREEN NAS OS injects `GODEBUG=tlskyber=0` into `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`. Because Go 1.23 removed the legacy `tlskyber` setting, Go 1.23+ binaries (including developer tools, telemetry agents, and remote servers) panic on startup.

`sudo ./homelab.sh setup` automatically remediates this idempotently on every run. To apply manually:
```bash
sudo sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
sudo sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
sudo systemctl unset-environment GODEBUG
systemctl --user unset-environment GODEBUG || true
sudo systemctl daemon-reexec
```
