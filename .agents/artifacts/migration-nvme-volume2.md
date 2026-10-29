# Migration & Boot Resilience Plan: NVMe Volume 2, Service Autostart & Host OS Documentation

## Goal Description
1. **Permanent Antigravity Remote Control Service**: Ensure the Antigravity Remote Control daemon (`agy remote-control serve` under instance name `Aumaka`) reliably starts on boot without relying on interactive login or being blocked by UGOS Pro's asynchronous `/volume1/@home` mount timing.
2. **Deterministic Boot-Time Stack Orchestration**: Add a host-level boot hook (`homelab-startup.service` invoking a new `homelab.sh startup` subcommand) that brings up Docker networks, the Dockge orchestrator, and all application stacks in strict dependency order (waiting for PostgreSQL database socket readiness before launching dependent services like Tandoor).
3. **Docker Data Migration to NVMe (`/volume2/docker`)**: Relocate `${DOCKER_DATA_DIR}` from `/volume1/docker` to `/volume2/docker` (newly initialized on NVMe in M.2 Slot 1) preserving exact file ownerships (`1000:100`, postgres `70:70`, root `0:0`), update codebase defaults, and verify with `./homelab.sh test`.
4. **Host OS Configuration Documentation**: Add a dedicated, comprehensive Host OS section to `README.md` documenting host dependencies, systemd service configurations, reasoning for appliance workarounds (asynchronous `/volume1` mounting, Go 1.23+ `GODEBUG` fix), and installation instructions.

---

## User Review Required

> [!IMPORTANT]
> **Host Systemd Services Installation**:
> Installing the persistent boot services (`antigravity-remote-control.service` and `homelab-startup.service`) into `/etc/systemd/system/` requires standard root permissions (`sudo cp ... && sudo systemctl enable ...`). 
> 
> *Overview of system modifications*:
> 1. Write `/etc/systemd/system/antigravity-remote-control.service` (runs `/home/brandon/.gemini/bin/agy remote-control serve` as user `brandon` with retry logic).
> 2. Write `/etc/systemd/system/homelab-startup.service` (runs `/home/brandon/services/homelab.sh startup` after Docker and storage services are active).
> 3. Disable the redundant user-level unit (`systemctl --user disable antigravity-cli-daemon`) to prevent duplicate instances.

> [!WARNING]
> **Container Downtime During Data Copy**:
> Containers will be cleanly stopped during the `rsync` from `/volume1/docker/` to `/volume2/docker/` to prevent database writes during migration.

---

## Architectural Workflow

```mermaid
flowchart TD
    subgraph Boot Resilience Setup
        A1["1. Install /etc/systemd/system/antigravity-remote-control.service"] --> A2["2. Add 'homelab.sh startup' Subcommand with DB Readiness Check"]
        A2 --> A3["3. Install /etc/systemd/system/homelab-startup.service"]
    end
    
    subgraph Data Migration
        B1["4. Quiesce Stacks: './homelab.sh backup' & 'docker compose down'"] --> B2["5. Copy Data: 'rsync -aHAX' from /volume1/docker/ to /volume2/docker/"]
        B2 --> B3["6. Audit Permissions: 1000:100, postgres 70:70, root 0:0"]
    end

    subgraph Configuration & Launch
        C1["7. Codebase Update: Set DOCKER_DATA_DIR=/volume2/docker in .env & Compose"] --> C2["8. Deploy & Start: './homelab.sh setup'"]
        C2 --> C3["9. Smoke Verification: Run './homelab.sh test' & Validate UI"]
    end

    subgraph Documentation
        D1["10. Update README.md with Host OS Configuration Section"]
    end

    Boot Resilience Setup --> Data Migration
    Data Migration --> Configuration & Launch
    Configuration & Launch --> Documentation
```

---

## Proposed Changes

### Phase 1: Antigravity Remote Control Systemd Service

#### [NEW] `/etc/systemd/system/antigravity-remote-control.service`
Replaces the fragile user-session service with a robust system-level unit that retries if `/home/brandon` is still mounting:
```ini
[Unit]
Description=Antigravity Remote Control Daemon (Aumaka)
After=network-online.target storage_serv.service docker_serv.service
Wants=network-online.target

[Service]
Type=simple
User=brandon
Group=admin
Environment=HOME=/home/brandon
Environment=PATH=/home/brandon/.gemini/bin:/usr/local/bin:/usr/bin:/bin
ExecStartPre=/bin/sh -c 'while [ ! -f /home/brandon/.gemini/bin/agy ]; do sleep 2; done'
ExecStart=/home/brandon/.gemini/bin/agy remote-control serve
Restart=always
RestartSec=5s
RestartPreventExitStatus=3
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
```

---

### Phase 2: Homelab Startup Subcommand & Boot Hook

#### [MODIFY] `homelab.sh`
1. Add `startup` subcommand and CLI help entry.
2. Implement `startup_homelab()` function:
   * Waits for `${DOCKER_DATA_DIR}` to be mounted (up to 60s timeout).
   * Runs `ensure_networks` to guarantee `homelab` (`192.168.255.0/24`) and `external_npm` (`192.168.0.0/24`) exist.
   * Starts Dockge orchestrator.
   * Starts stacks in strict dependency order:
     * `postgres` $\rightarrow$ loops on `docker exec postgres pg_isready` (up to 15s) until database socket is responsive.
     * `nginx` (reverse proxy) $\rightarrow$ ready to route traffic.
     * `tailscale`, `homepage`, `jellyfin`, `qbittorrentvpn`, `sonarr-radarr`, `seerr`, `tandoor`.
   * Non-interactive execution (never blocks on user input during boot).

```bash
# ------------------------------------------------------------------------------
# Function: startup_homelab
# Description:
#   Brings up Docker networks, orchestrators, and stacks in strict dependency
#   order during boot or headless recovery without interactive prompts.
# ------------------------------------------------------------------------------
startup_homelab() {
  local timeout=60
  while [[ ! -d "${DOCKER_DATA_DIR}" ]] && (( timeout > 0 )); do
    sleep 1
    (( timeout-- )) || true
  done

  ensure_networks

  # Start Dockge
  if [[ -f "${DOCKGE_DIR}/compose.yml" ]]; then
    docker compose -f "${DOCKGE_DIR}/compose.yml" --env-file "${DOCKGE_DIR}/.env" up -d
  fi

  # Start stacks in dependency order
  for stack in "${STACKS[@]}"; do
    if [[ -f "${REPO_DIR}/${stack}/compose.yml" ]]; then
      log_info "Bootstrapping stack '${stack}'..."
      (
        cd "${REPO_DIR}/${stack}"
        docker compose up -d
      )

      # When postgres starts, wait for socket readiness before launching dependents
      if [[ "${stack}" == "postgres" ]]; then
        local pg_wait=15
        while ! docker exec postgres pg_isready -q 2>/dev/null && (( pg_wait > 0 )); do
          sleep 1
          (( pg_wait-- )) || true
        done
      fi
    fi
  done
}
```

#### [NEW] `/etc/systemd/system/homelab-startup.service`
Invokes the non-interactive startup orchestration once Docker and storage services are live:
```ini
[Unit]
Description=Homelab Docker Stacks Startup and Orchestration
After=docker.service storage_serv.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=brandon
Group=admin
Environment=HOME=/home/brandon
WorkingDirectory=/home/brandon/services
ExecStart=/home/brandon/services/homelab.sh startup
TimeoutStartSec=300s

[Install]
WantedBy=multi-user.target
```

---

### Phase 3: Docker Data Migration to `/volume2/docker`

1. **Stop all stacks**:
   ```bash
   ./homelab.sh backup -m "Pre-NVMe migration configuration checkpoint"
   docker compose -f /opt/brandon/dockge/compose.yml --env-file /opt/brandon/dockge/.env down
   for stack in sonarr-radarr qbittorrentvpn jellyfin seerr tandoor postgres homepage nginx tailscale; do
     docker compose -f "$HOME/services/${stack}/compose.yml" down
   done
   ```
2. **Rsync data with archive preservation**:
   ```bash
   sudo mkdir -p /volume2/docker
   sudo rsync -aHX --info=progress2 /volume1/docker/ /volume2/docker/
   ```
3. **Verify permissions on `/volume2/docker`**:
   * `1000:100` on Jellyfin, Arr stack, Seerr, Tandoor, qBittorrent, Tailscale.
   * `70:70` on `postgres/data`.
   * `0:0` on `nginx`, `homepage`, `dockge`.

---

### Phase 4: Codebase & Environment Updates

#### [MODIFY] `.env` & `.env.example`
Set `DOCKER_DATA_DIR=/volume2/docker`.

#### [MODIFY] `homelab.sh`
Update default fallback from `/volume1/docker` to `/volume2/docker`.

#### [MODIFY] Stack Compose Files (10 files)
Update `${DOCKER_DATA_DIR:-/volume1/docker}` fallback to `${DOCKER_DATA_DIR:-/volume2/docker}` across all stacks.

#### [MODIFY] `README.md`
1. Update Table of Contents with new section: **7. Host OS Configuration, Services & Appliance Engineering**.
2. Update all paths and references from `/volume1/docker` to `/volume2/docker`.
3. Add Section 7 covering:
   * **Host Packages & Dependencies**: `sqlite3`, `rsync`, `zstd`, `curl`, `jq`.
   * **Systemd Services**: `antigravity-remote-control.service` and `homelab-startup.service` (definitions, installation commands, reasoning).
   * **Asynchronous Mount Architecture**: Technical explanation of UGOS Pro `/volume1/@home` mount lifecycle and why system-level units with retry loops are required.
   * **UGREEN Appliance Workarounds**: Preserving the `GODEBUG=tlskyber=0` documentation and storage layout architecture.

#### [MODIFY] `.agents/artifacts/architecture.md`
Update architectural specification and storage paths.

---

## Verification Plan

### Automated Tests
1. **Host Smoke Tests**:
   ```bash
   ./homelab.sh test
   ```
   Verifies container health (all 12 containers), reverse-proxy routing over `homelab` bridge, HTTPS virtual hosts, database sockets, and VPN port sync.
2. **Service Autostart & Hook Testing**:
   * Verify systemd service status:
     ```bash
     sudo systemctl status antigravity-remote-control.service
     sudo systemctl status homelab-startup.service
     ```
   * Dry-run `/home/brandon/services/homelab.sh startup` to ensure zero errors and clean output.

### Manual Verification
1. **Antigravity Remote Control**: Confirm Aumaka remains "Online" in the Remote Control interface.
2. **Jellyfin**:
   * Inspect mount: `docker inspect jellyfin | grep -A 2 -B 2 "/config"`
   * Verify instantaneous library grid and thumbnail loads.
   * Confirm watch history and resume state changes commit properly.
3. **PostgreSQL**:
   * Verify `docker exec postgres pg_isready` reports acceptance of connections.
