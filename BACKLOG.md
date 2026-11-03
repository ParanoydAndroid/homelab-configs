# Project Backlog

This backlog tracks pending architectural improvements, infrastructure tasks, and technical debt items for the homelab environment.

---

## Active Backlog Items

### [BACKLOG-001] Tailscale tmpfs Socket Optimization
* **Priority**: Medium
* **Category**: Infrastructure / Reliability
* **Component**: `tailscale/compose.yml`
* **Trigger**: Execute after the host RAID 5 rebuild / reshape finishes.

#### Description
Add a `tmpfs: [/tmp]` mount to the Tailscale subnet router service definition in `tailscale/compose.yml`.

#### Motivation & Context
Under heavy disk I/O (such as host storage array rebuilds or parity reshapes), filesystem write operations within the container's overlayfs layer experience severe latency. Because Tailscale's `containerboot` entrypoint polls for `/tmp/tailscaled.sock` during daemon initialization, disk latency can cause initialization to exceed startup timeouts (`timed out waiting for tailscaled socket`). Additionally, persisting container sockets on disk can cause benign `[warning] failed to symlink socket: file exists` messages across restarts.

Mounting a `tmpfs` on `/tmp` keeps the UNIX domain socket entirely in host memory (RAM), eliminating disk contention and guaranteeing no stale socket files survive container recreation.

#### Verification Criteria
1. `tailscale/compose.yml` defines `tmpfs: [/tmp]`.
2. Tailscale container starts cleanly without socket startup delays.
3. `docker exec tailscale tailscale status --json` reports `BackendState: "Running"`.
4. `./homelab.sh test interconnect` passes with `test_interconnect_tailscale_backend_state` active.

---

### [BACKLOG-002] Volume-Tiering Skill: Single-Volume to Dual-Tier Storage Migration Runbook
* **Priority**: Low
* **Category**: Agent Skills / Storage Architecture
* **Component**: `.agents/skills/volume-tiering/SKILL.md`
* **Trigger**: On demand when users upgrade from single-pool storage to fast NVMe SSD (`DOCKER_DATA_DIR`) + bulk HDD array (`MEDIA_DIR`).

#### Description
Author a procedural operational runbook skill (`volume-tiering`) providing step-by-step guidance, validation commands, and automated data migration for separating container application data from bulk media storage.

#### Motivation & Context
Many initial homelab installations start with a single filesystem pool (e.g., `/volume1/docker` and `/volume1/media` on the same drive array). As users scale, migrating persistent container metadata, databases (PostgreSQL, SQLite), and caches to high-IOPS NVMe SSD storage while retaining multi-terabyte media libraries on bulk HDD RAID pools significantly boosts performance and reduces head thrashing. This skill will provide declarative guidance for updating root `.env` / stack `.env` variables, performing live or offline `rsync` transfers with ownership (`1000:100`) preservation, updating Restic snapshot configurations, and verifying database socket integrity post-migration.

#### Verification Criteria
1. Author `.agents/skills/volume-tiering/SKILL.md` adhering to skill format standards.
2. Include pre-flight storage capacity checks (`df -h`).
3. Detail safe `rsync -avhHAX --numeric-ids` staging commands with container stop/start sequences.
4. Include database post-migration integrity verification.

---

---

## Completed Backlog Items

### [BACKLOG-003] E-Book & Web Serial Automation Stack (`books/compose.yml`)
* **Completed**: 2026-11-03
* **Category**: Service Stacks / Media & Productivity
* **Component**: `books/compose.yml`

#### Summary of Implementation
- Deployed Calibre-Web (`lscr.io/linuxserver/calibre-web:latest`) with `universal-calibre` format converters, authenticated OPDS endpoint for Boox e-ink readers (`https://books.kamaka.tech/opds`), and Send-to-Kindle integration.
- Deployed Readarr (`lscr.io/linuxserver/readarr:develop`) integrated with Prowlarr indexers, qBittorrent download client, and zero-copy atomic hardlinks on `${MEDIA_DIR}`.
- Deployed FanFicFare background scraping worker (`royalroad-sync`) with FlareSolverr anti-bot integration, automated chapter updates, and direct EPUB output to `/volume1/media/books/import/`.
- Configured Caddy reverse proxy routing with Let's Encrypt TLS certificates on `books.kamaka.tech` and `readarr.kamaka.tech`.
- Added 7 automated tests covering container health, virtual host routing, OPDS catalog feeds, Prowlarr/qBittorrent interconnections, and unauthenticated API rejection.
