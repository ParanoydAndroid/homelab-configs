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

### [BACKLOG-003] E-Book & Web Serial Automation Stack (Kindle, Boox, Calibre-Web & Royal Road)
* **Priority**: Medium
* **Category**: Service Stacks / Media & Productivity
* **Component**: `books/compose.yml` (or `media/compose.yml`)
* **Trigger**: On demand when architecting wireless reading workflows for Kindle and Android-based e-ink (Boox) devices.

#### Description
Design and deploy a containerized e-book management, metadata enrichment, and wireless distribution stack supporting automated syncing to e-ink hardware (Amazon Kindle and Onyx Boox) alongside automated chapter tracking and compilation for web serials (Royal Road).

#### Motivation & Context
Current homelab media automation covers video (Jellyfin, *arr suite) and audio, but lacks dedicated handling for digital books and ongoing serialized literature. Reading workflows require seamless wireless delivery without physical tethering:
- **Amazon Kindle Delivery**: Requires Send-to-Kindle email integration (via authenticated outbound SMTP) to push EPUB documents directly to Amazon Whispernet over Wi-Fi.
- **Onyx Boox / Android E-Ink Sync**: Runs full Android and modern readers (e.g., KOReader, Moon+ Reader, NeoReader), enabling direct OPDS catalog browsing over local LAN/Tailscale, bidirectional reading progress sync (Kosync), and optional Syncthing folder synchronization.
- **Royal Road / Web Serial Automation**: Ongoing serials publish incremental chapters. Tracking and building EPUBs manually is tedious; an automated background worker (such as FanFicFare CLI or a containerized serial downloader) is required to periodically poll Royal Road, append new chapters to existing EPUBs, update metadata/covers, and trigger library re-scans and wireless delivery.

#### Architecture & Candidate Components
1. **Catalog, Metadata & Library Management**:
   - **Calibre-Web**: Lightweight web frontend consuming a central Calibre database (`metadata.db`). Provides rich metadata editing, OPDS catalog feeds, user access controls, in-browser reader, and native "Send to Kindle" SMTP dispatch.
   - **Readarr** *(Optional)*: *arr-style book monitoring, search, and acquisition aggregator interfacing with Prowlarr indexers and qBittorrent.
2. **Web Serial Ingestion**:
   - **FanFicFare**: Open-source scraper and EPUB compiler supporting Royal Road, AO3, and other web serial platforms. Capable of incremental updates (appending only newly published chapters).
   - Can run as a scheduled cron service or automated watcher container placing compiled EPUBs into Calibre's auto-add directory (`/media/books/import`).
3. **Network & Ingress Integration**:
   - Ingress via Caddy Docker Proxy labels on `homelab` bridge (`books.kamaka.tech` with wildcard TLS and LAN/Tailscale restriction).
   - OPDS endpoint accessible over Tailscale for remote Boox syncing away from home.
   - Outbound SMTP credentials provisioned via stack `.env` for Send-to-Kindle forwarding.

#### Verification Criteria
1. Compose definition for the book stack adheres to project conventions (non-root `PUID:PGID`, explicit network attachment, Caddy labels, resource logging limits).
2. Calibre-Web serves an authenticated OPDS feed verified via curl and reader clients.
3. Test delivery to Kindle via Send-to-Kindle SMTP successfully receives and renders formatted EPUBs.
4. FanFicFare or equivalent automated runner successfully downloads and updates a multi-chapter Royal Road story into the library with valid cover and table of contents.
5. Persistent book library storage resides cleanly on mechanical RAID (`${MEDIA_DIR}/books`) with application metadata on NVMe (`${DOCKER_DATA_DIR}/calibre-web`).
6. Automated smoke test assertions added to `homelab.sh test`.
