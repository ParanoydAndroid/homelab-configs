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

### [BACKLOG-003] E-Book & Web Serial Automation Stack (`books/compose.yml`)
* **Priority**: Medium
* **Category**: Service Stacks / Media & Productivity
* **Component**: `books/compose.yml`
* **Trigger**: On demand when provisioning reading automation for Kindle and Boox hardware.

#### Description
Design and deploy a dedicated, modular Dockge stack (`books/compose.yml`) providing an e-book catalog, commercial book acquisition, wireless e-ink delivery (Amazon Kindle and Onyx Boox), and automated background compiling and chapter updates for ongoing Royal Road web serials.

#### Architectural Decisions & Component Selection
1. **Core Catalog & Reader Portal**:
   - **Service**: Calibre-Web (`lscr.io/linuxserver/calibre-web:latest`).
   - **Role**: Lightweight web UI, metadata editor, in-browser reader, and OPDS server. Integrated with Calibre's CLI tools for format conversions (EPUB/MOBI/AZW3).
   - **Wireless Delivery**: Native "Send to Kindle" integration using outbound SMTP (via stack `.env` credentials) to deliver EPUBs wirelessly over Amazon Whispernet Wi-Fi.
2. **Commercial Book Acquisition**:
   - **Service**: Readarr (`lscr.io/linuxserver/readarr:develop`).
   - **Role**: *arr pipeline for author monitoring, automated book search via Prowlarr indexers, and download delegation to `qbittorrentvpn`.
   - **Storage Mechanics**: Uses atomic hardlinks across `/volume1/media` from `/media/downloads/books` to `/media/books/library`, eliminating redundant disk copies.
3. **Royal Road Web Serial Automation**:
   - **Service**: Scheduled FanFicFare worker container (`royalroad-sync`).
   - **Role**: Mature, battle-tested Python CLI engine (maintained since 2011) tracking a declarative list of story URLs (`stories.txt`).
   - **Cadence**: Automatically checks for newly published chapters every 4–6 hours.
   - **Mechanics**: Incrementally fetches new chapters, appends them to existing EPUBs in-place without re-downloading prior content, updates the table of contents and cover art, and drops completed EPUBs into the library auto-import directory (`/media/books/import`).
4. **Device Sync & Reading Progress Integration**:
   - **Amazon Kindle**: Wireless push delivery via Calibre-Web Send-to-Kindle SMTP; Whispersync manages position tracking across Kindle devices and apps.
   - **Onyx Boox (Android E-Ink)**: Connects directly to Calibre-Web's authenticated OPDS feed (`https://books.kamaka.tech/opds`) in KOReader or native NeoReader over local Wi-Fi or Tailscale. Cross-device reading position sync is managed via Kosync (community server or self-hosted micro-daemon).

#### Storage Tiering & Volume Architecture
- **NVMe Storage (`${DOCKER_DATA_DIR}` / `/volume2/docker`)**:
  - `${DOCKER_DATA_DIR}/calibre-web/data`: Application settings, user accounts, and `app.db`.
  - `${DOCKER_DATA_DIR}/readarr/data`: Application databases (`readarr.db`), logs, and indexer caches.
  - `${DOCKER_DATA_DIR}/royalroad/data`: `stories.txt` URL list and FanFicFare `personal.ini` configuration.
- **Mechanical RAID Storage (`${MEDIA_DIR}` / `/volume1/media`)**:
  - `${MEDIA_DIR}/books/library`: Canonical Calibre library containing organized author/book directories and `metadata.db`.
  - `${MEDIA_DIR}/books/import`: Auto-add drop directory watched by Calibre-Web for newly built Royal Road EPUBs.
  - `${MEDIA_DIR}/downloads/books`: Staging directory for qBittorrent downloads enabling zero-copy atomic hardlinks into `library`.

#### Ingress & Network Architecture
- Backend containers run on the isolated `homelab` Docker bridge network (`192.168.255.0/24`).
- Reverse proxy routing declared via Caddy Docker Proxy labels on the `homelab` bridge:
  - `https://books.kamaka.tech`: Calibre-Web frontend and OPDS feed, secured with Let's Encrypt wildcard TLS and `lan_only` access control.
  - `https://readarr.kamaka.tech`: Readarr administration dashboard, secured with Let's Encrypt wildcard TLS and `lan_only` access control.
- Dashboard integration via Homepage widget labels (`homepage.group=Media`, `homepage.name=Books`).

#### Verification Criteria
1. `books/compose.yml` strictly adheres to project standards (canonical key ordering, non-root `PUID:PGID`, `${VAR:?}` assertion syntax, logging capped at 10m/3 files).
2. Calibre-Web deploys with an initialized `metadata.db` and exposes a valid, authenticated OPDS feed accessible by e-ink reader apps.
3. Test delivery to Kindle via Send-to-Kindle SMTP sends formatted EPUBs that render properly on Kindle hardware.
4. FanFicFare background runner successfully parses `stories.txt`, fetches a multi-chapter Royal Road fiction, builds a valid EPUB with metadata/covers, and drops it into `import/`.
5. Readarr successfully communicates with Prowlarr (`http://prowlarr:9696`) and qBittorrent (`http://qbittorrentvpn:8081`).
6. Automated smoke test assertions added to `homelab.sh test` verifying container runtimes, Caddy virtual host routing, and inter-container API endpoints.
