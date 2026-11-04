# Engineering Implementation Plan: Cleanuparr Deployment & Queue Starvation Remediation

## 1. Executive Summary & Objective

### 1.1 The Problem
In our homelab environment, automated backlog searches (such as Sonarr searching for multi-season TV releases) regularly pull torrents from public indexers. Even with indexer `minimumSeeders = 3` enforced, public indexers routinely report stale or spoofed seeder counts. When qBittorrent grabs these releases, zero peers are connectable in the swarm, stranding them in the **`metaDL` (Downloading Metadata)** state.

Because of a known limitation in libtorrent, `metaDL` torrents are **not** treated as "slow torrents". When queue limits are active (`max_active_torrents: 50`), accumulating dead magnets eventually consume every active slot ($22\text{ metaDL} + 28\text{ stalledDL} = 50\text{ slots}$), causing **head-of-line queue starvation** that halts all subsequent healthy downloads. Conversely, turning queueing off entirely overwhelms qBittorrent's single-threaded WebAPI with 180+ simultaneous connections, resulting in connection drops and HTTP timeout errors in Sonarr, Radarr, and Bindery.

### 1.2 The Solution
Deploy **Cleanuparr** (`ghcr.io/cleanuparr/cleanuparr:latest`) as an automated queue monitor. Cleanuparr bridges qBittorrent, Sonarr, and Radarr by inspecting the queue on a regular interval (every 5 minutes), assigning strikes to torrents stuck in `metaDL` or stalled with zero speed, and—upon strike threshold expiration—cleanly deleting the dead torrent, blocklisting the release hash in Sonarr/Radarr, and automatically requesting a healthy replacement. This allows us to keep qBittorrent's queue safely bounded (`queueing_enabled: true`, `max_active_torrents: 50`) while permanently eliminating queue starvation.

---

## 2. Architectural Design & Topology

### 2.1 Component Interaction Diagram

```
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                         Docker homelab Bridge Network                       │
 │                                                                             │
 │   ┌───────────────┐     API Poll (5m)     ┌───────────────┐                 │
 │   │               │ ◄──────────────────── │               │                 │
 │   │  Sonarr /     │                       │  Cleanuparr   │                 │
 │   │  Radarr       │ ── Blocklist & Search │  (:11011)     │                 │
 │   │               │ ◄──────────────────── │               │                 │
 │   └───────┬───────┘                       └───────┬───────┘                 │
 │           │ Grab                                  │ Queue Inspect & Evict   │
 │           ▼                                       ▼                         │
 │   ┌───────────────────────────────────────────────────────┐                 │
 │   │ qBittorrent (qbittorrentvpn:8081 via wireguard-pia)   │                 │
 │   │ - queueing_enabled: true                              │                 │
 │   │ - max_active_torrents: 50                             │                 │
 │   │ - Scratch: /incomplete (NVMe /volume2)                │                 │
 │   └───────────────────────────────────────────────────────┘                 │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Container Specification (`torrent/compose.yml`)

Cleanuparr will be co-located in the `torrent` stack alongside qBittorrent and WireGuard PIA:

- **Service Name**: `cleanuparr`
- **Image**: `ghcr.io/cleanuparr/cleanuparr:latest`
- **Container Name**: `cleanuparr`
- **Hostname**: `cleanuparr`
- **User / Permissions**: `PUID: ${PUID}`, `PGID: ${PGID}` (1000:100)
- **Restart Policy**: `unless-stopped`
- **Networking**: `homelab` bridge network (Cleanuparr does **not** route through VPN; it communicates internally with local container APIs and externally to GitHub for updates).
- **Host Ports**: None exposed to host interface (adheres to zero-unnecessary-host-ports rule).
- **Volumes**:
  - `${DOCKER_DATA_DIR}/cleanuparr/data:/config` (Persistent SQLite DB and settings)
  - `${MEDIA_DIR:?See env.example for default.}:/media:ro` (Read-only access for optional orphaned file detection)
- **Reverse Proxy (Caddy)**:
  - Domain: `https://cleanuparr.kamaka.tech`
  - Internal upstream: `{{upstreams 11011}}`
  - TLS Profile: `cloudflare_tls`
- **Homepage Dashboard**:
  - Group: `Downloads`
  - Name: `Cleanuparr`
  - Icon: `cleanuparr` (or `si-shield`)
  - URL: `https://cleanuparr.kamaka.tech`

---

## 3. Comprehensive Settings Audit & Recommendation Matrix

Cleanuparr offers extensive customization. Below is an audit of each major functional group, explaining what the settings mean, their operational impact, technical recommendations tailored to our homelab, and open decisions.

### Category 1: Queue Cleaner Execution & Scope

| Setting | Description | Homelab Operational Impact | Recommendation & Justification | Decision Required |
| :--- | :--- | :--- | :--- | :--- |
| **`Execution Interval`** | How often Cleanuparr scans queues (e.g. 5m, 10m, 15m). | Shorter intervals detect dead magnets faster; longer intervals reduce API polling overhead. | **5 Minutes (Default)**: Negligible API overhead on local Docker bridge; allows dead magnets to be evicted in ~15 mins. | **[ ] Agree** with 5m interval, or adjust? |
| **`Process Unmapped Downloads`** | Whether to process torrents not linked to any *Arr item (e.g. manual downloads). | If enabled, manual downloads could be deleted if stalled, but *no replacement search can be triggered*. | **Disabled (False)**: Protect manual grabs from accidental deletion. Only manage automated *Arr items. | **[ ] Agree** (ignore unmapped) or enable? |

---

### Category 2: Stalled & Metadata Downloads (The Core Fix)

| Setting | Description | Homelab Operational Impact | Recommendation & Justification | Decision Required |
| :--- | :--- | :--- | :--- | :--- |
| **`Stalled Strikes Threshold`** | Number of consecutive failed checks before taking action. | At 5-min intervals: 3 strikes = 15m; 4 strikes = 20m; 6 strikes = 30m. | **3 Strikes (15 Minutes)**: Fast enough to prevent dead magnets from filling 50 slots, but gives swarms 15 minutes to find DHT peers. | **[ ] 3 Strikes (15m)**, **4 Strikes (20m)**, or other? |
| **`Check Metadata Downloads (metaDL)`** | Explicitly targets torrents in qBittorrent's "Downloading Metadata" state. | Directly remediates the libtorrent bug where magnets sit at 0% without counting as slow torrents. | **Enabled (True)**: Mandatory for solving our exact freeze mechanism. | **[ ] Confirm Enabled** |
| **`Delete Files on Eviction`** | Whether to delete partial files in `/incomplete` when evicting stalled torrents. | Keeps NVMe scratch storage clean and removes corrupt partial blocks (like zero-filled headers). | **Enabled (True)**: Keeps `/volume2` NVMe scratch clear of dead torrent remnants. | **[ ] Confirm Enabled** |
| **`Blocklist Release in Sonarr/Radarr`** | Adds release hash to *Arr blocklist upon eviction. | Prevents Sonarr/Radarr from immediately grabbing the exact same dead release in the next RSS cycle. | **Enabled (True)**: Mandatory to avoid infinite download-fail loops. | **[ ] Confirm Enabled** |
| **`Trigger Search for Replacement`** | Automatically orders Sonarr/Radarr to search for an alternative release. | Guarantees media eventually downloads without manual operator intervention. | **Enabled (True)**: Core automation objective. | **[ ] Confirm Enabled** |

---

### Category 3: Slow Download Management

| Setting | Description | Homelab Operational Impact | Recommendation & Justification | Decision Required |
| :--- | :--- | :--- | :--- | :--- |
| **`Slow Downloads Cleaner`** | Evicts downloads that are progressing, but below a minimum speed or above maximum ETA. | Helpful for weeding out 15 KB/s leech swarms, but risks aborting rare/niche downloads that have few seeds. | **Disabled Initially (or conservative: ETA > 14 days)**: We want to catch dead downloads, but not kill slow, rare Brandon Sanderson books or older seasons. | **[ ] Disabled** (focus strictly on dead/stalled), or **Conservative ETA cap**? |
| **`Slow Speed Threshold`** | Minimum speed below which a download is flagged as slow (e.g. < 50 KiB/s). | If set too high, throttled or rare torrents get prematurely killed. | **20 KiB/s with 6 Strikes (30m)** (if enabled): Ensures only truly crawling downloads are flagged. | **[ ] Defer to disabled**, or enable with threshold? |

---

### Category 4: Failed Imports Management

| Setting | Description | Homelab Operational Impact | Recommendation & Justification | Decision Required |
| :--- | :--- | :--- | :--- | :--- |
| **`Failed Import Strikes`** | Max strikes for items reporting "Unable to import" in Sonarr/Radarr queue. | Prevents broken files (e.g., corrupt EBML headers like *Law & Order S25E11*) from clogging the queue forever. | **3 Strikes (Minimum allowed)**: Gives Sonarr time to complete file moves, but cleans out unreadable files after 15m. | **[ ] Agree** with 3 strikes, or adjust? |
| **`Ignore Recently Aired`** | Exemption window (in minutes) for episodes that just aired on TV. | Fresh releases often have temporary packer/indexer delays where Sonarr retries import before the file settles. | **120 Minutes**: Standard practice to prevent killing brand-new releases during active unpacking. | **[ ] Agree** (120 min window)? |

---

### Category 5: Orphaned Data & Seeding Rules

| Setting | Description | Homelab Operational Impact | Recommendation & Justification | Decision Required |
| :--- | :--- | :--- | :--- | :--- |
| **`Orphaned Data Cleaner`** | Scans storage for files on disk that belong to no active torrent or *Arr item. | Reclaims disk space, but dangerous if path mappings have minor discrepancies (could delete wanted files). | **Disabled (or Dry Run Only)**: Do not allow automated deletion of unlinked files until manual audit is conducted. | **[ ] Disabled** (Recommended)? |
| **`Seeding Management Cleaner`** | Automatically deletes torrents after hitting ratio or seed time goals. | We already manage share ratio limits in qBittorrent configuration (`max_ratio_act`, `max_ratio = 1.0`). | **Disabled**: Redundant with native qBittorrent share limits. Keep single source of truth in qBittorrent. | **[ ] Disabled** (Recommended)? |

---

## 4. Implementation Steps

1. **Feature Branching**:
   - Working on branch `feature/cleanuparr` (created from clean `main`).
2. **Configuration Scaffolding**:
   - Create `${DOCKER_DATA_DIR}/cleanuparr/data` with ownership `1000:100`.
   - Update `torrent/compose.yml` to define `cleanuparr` service with healthcheck and Caddy labels.
   - Update `torrent/.env.example` if any new credentials/tokens are required.
3. **qBittorrent Configuration Alignment**:
   - Keep `queueing_enabled: true` in `.configs/qbittorrentvpn/set-qbt-port.sh` with balanced limits (`max_active_downloads: 15`, `max_active_torrents: 50`).
   - Cleanuparr will maintain the queue below the 50-torrent watermark dynamically.
4. **Service Integration Setup**:
   - Configure Cleanuparr WebUI with:
     - qBittorrent: `http://qbittorrentvpn:8081` (credentials from `torrent/.env`).
     - Sonarr: `http://sonarr:8989` (API key from `media/.env`).
     - Radarr: `http://radarr:7878` (API key from `media/.env`).
5. **Automated Smoke Test Integration**:
   - Add `test_docker_up_cleanuparr` in `.tests/suites/test_containers.sh`.
   - Add `test_vhost_cleanuparr_internal` in `.tests/suites/test_vhost_routing.sh`.
   - Add `test_interconnect_cleanuparr_api` in `.tests/suites/test_interconnect.sh`.
6. **Verification Protocol**:
   - Run `./homelab.sh test all` to verify all 64+ test assertions pass.
   - Verify Cleanuparr WebUI loads cleanly over HTTPS via Caddy (`https://cleanuparr.kamaka.tech`).
   - Trigger a simulated stalled magnet to verify strikes, eviction, and Sonarr replacement search.

---

## 5. Review Gate & Open Questions

Before implementation begins, please review the recommended settings:

1. **Stalled & Metadata Eviction Timing**: Do you approve **3 strikes at 5-minute intervals (15 minutes total)** before evicting dead magnets and searching for a replacement?
2. **Slow Downloads**: Do you prefer **disabling** the slow download cleaner initially (focusing strictly on 0-speed/dead magnets), or would you prefer a conservative threshold (e.g., ETA > 14 days)?
3. **Failed Imports**: Do you approve **3 strikes (15 mins)** with a **120-minute exemption for newly aired episodes**?
4. **Scope Safety**: Do you confirm keeping **Orphaned Data Cleaner** and **Seeding Cleaner** disabled so Cleanuparr only manages active queue health?
