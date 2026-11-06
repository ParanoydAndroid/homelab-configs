# Changelog

All notable changes to the homelab infrastructure, service stacks, automation scripts, and documentation are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Major releases are paired with their semantic version and chronological (CalVer) git tag.

---

## [3.5.0] / [2026.11.6] - Tiered Subagents, Completion Audit & Harness Governance (2026-11-06)

### Added
* Model-tiered subagent prompt contracts in `.agents/subagents/`: `principal-reviewer` (`pro`) for architecture and codebase audits, `grep-worker` (`flash_lite`) for fast pattern discovery, and `diff-worker` (`flash_lite`) for structural delta analysis.
* Interactive code and architecture audit step in `feature-completion` runbook (`./manage.sh audit`, diff review, 4-pillar evaluation).
* Agile Trunk governance, cadence invariants, and Pre-Tagging Proposal Packet in `semver-calver-guidelines.md`.

### Changed
* Replaced artificial question caps in `feature-initiation` ("grill-me") with unconstrained substantive inquiry across multiple rounds until trade-offs are settled.
* Hardened `manage.sh` git hooks to run the complete test suite (`./manage.sh test all`) before committing or pushing to `main`.
* Adopted Golden Path & Happy Path priority across project conventions.

### Fixed
* Converted ANSI color codes in `manage.sh` and `.harness/lib/common.sh` to ANSI C-quoting (`$'\033[...'`) to prevent escape sequences from rendering literally in terminal environments like Termux.
* Added root privilege enforcement guard to `./manage.sh snapshots`.

---

## [3.4.0] / [2026.11.5] - Declarative Backups & Storage Architecture (2026-11-05)

### Added
* Implemented declarative `homelab.backup.sqlite` and `homelab.backup.exclude` container labels for dynamic database checkpoint staging and Restic snapshot path exclusions.
* Added declarative decade stack ordering (`homelab.stack.priority=10, 20...`) with unlabelled fallbacks in startup orchestration.
* Added declarative Btrfs storage policies via `homelab.storage.btrfs` container label, applying No-CoW flags (`chattr +C`) and group write permissions before container startup.
* Consolidated versioning utilities (`bump_semver`, `resolve_chronological_tag`) into `.scripts/common.sh` and decoupled git commits from volume backup runs.
* Added automated unit test coverage in `.tests/suites/test_backup.sh` for declarative discovery and isolated priority resolution.

### Changed
* Standardized BitTorrent naming across all Compose files, host storage paths, configurations, and connecting client databases on `qbittorrent`, eliminating legacy `qbittorrentvpn` references.
* Parameterized high-friction host paths (`DOCKER_SOCK`, `DRI_RENDER_DEV`, `TORRENT_INCOMPLETE_DIR`) in environment templates.
* Modernized `start-homelab` service catalog and selection profiles to match active 7-stack topology and dual-homed Caddy ingress architecture.
* Simplified qBittorrent WebUI authentication with stack-standard credentials (`admin` / `password`) and subnet bypass for LAN (`192.168.0.0/16`) and Tailscale (`100.64.0.0/10`).

### Fixed
* Eliminated unprompted host attribute mutations by gating Btrfs No-CoW operations strictly to explicit service labels.
* Decoupled stack startup order testing from live container runtimes using isolated mock container tests.

---

## [3.3.0] / [2026.11.4.1] - Cleanuparr Queue Garbage Collection & VPN Mesh Resilience (2026-11-04)

### Added
* Deployed Cleanuparr queue management service (`https://cleanuparr.kamaka.tech`) in the `torrent` stack to collect dead magnets and stalled downloads.
* Implemented automated replacement searches: Sonarr and Radarr automatically search for alternate releases when stalled downloads reach strike limits.
* Added automated smoke, reverse proxy routing, and interconnect test coverage for Cleanuparr in `.tests/suites/`.
* Integrated `cleanuparr.db` into the automated Restic online SQLite snapshot staging list in `.scripts/backup.sh`.

### Changed
* Configured Cleanuparr reverse proxy ingress on Caddy with local subnet authentication bypass and trusted proxy headers.
* Added Homepage dashboard service widget for Cleanuparr under the Downloads group.

### Fixed
* Eliminated head-of-line BitTorrent queue starvation in qBittorrent where stalled metadata downloads (`metaDL`) deadlocked the active queue limit.
* Resolved silent WireGuard tunnel drops on `vpn-bridge-pia` by enabling persistent keepalive (`KEEPALIVE: 25`), automatic reconnect (`RECONNECT: 1`), and active health checks to maintain uninterrupted Tailscale exit node availability.

---

## [3.2.0] / [2026.11.3.2] - Bindery Book Engine, Calibre Auto-Ingest & BitTorrent Queue Resilience (2026-11-03)

### Added
* Replaced retired Readarr service with Bindery book acquisition engine (`https://bindery.kamaka.tech`), maintaining `https://readarr.kamaka.tech` as an active reverse proxy alias.
* Automated Calibre-Web periodic library ingestion via an S6 container init hook (`calibredb add` cron worker) to continuously catalogue scraped EPUBs into the library.
* Codified TRaSH Guides architectural adherence as the baseline standard across media management and download client configurations in project conventions.

### Changed
* Configured qBittorrent queue concurrency with slow torrent exemptions (`queueing_enabled: true`, `max_active_downloads: 15`, `max_active_torrents: 50`) in `.configs/qbittorrentvpn/set-qbt-port.sh`.
* Enforced `minimumSeeders = 3` across all Prowlarr-backed indexers in Sonarr and Radarr to block dead magnet links from entering download queues.

### Fixed
* Resolved qBittorrent queue starvation caused by unseeded magnet links accumulating in `metaDL` status.
* Populated 201 dead releases in Sonarr's blocklist and 22 dead releases in Radarr's blocklist to prevent repeated grab attempts.

---

## [3.1.0] / [2026.11.3.1] - E-Book Automation Stack & Multi-Domain Media Routing (2026-11-03)

### Added
* Deployed dedicated `books` stack featuring Calibre-Web, Readarr, and FanFicFare background worker.
* Calibre-Web e-book catalog (`https://books.kamaka.tech`) with `universal-calibre` format converters, authenticated OPDS feed for Onyx Boox and mobile e-ink readers, and Send-to-Kindle outbound email delivery.
* Readarr automated book acquisition (`https://readarr.kamaka.tech`) integrated with Prowlarr indexers and qBittorrent client over atomic media hardlinks.
* FanFicFare background web serial sync (`royalroad-sync`) with FlareSolverr anti-bot resolution, polling `stories.txt` and compiling EPUB updates into the auto-import library.
* Multi-domain reverse proxy routing for Jellyfin streaming on `media.kamaka.tech` (internal) and `media.kamakakai.com` (public Cloudflare tunnel).
* Automated smoke, routing, interconnect, and security test assertions for all books services and endpoints.

### Changed
* Configured FlareSolverr proxy routing and polite rate-limiting for FanFicFare to bypass Cloudflare bot challenges on Royal Road web serials.
* Auto-seeded FlareSolverr proxy defaults in FanFicFare entrypoint for declarative deployments.

---

## [3.0.0] / [2026.11.3] - Ingress Inversion to Caddy, Mealie Deployment & Stack Modernization (2026-11-03)

### Added
* Replaced Nginx Proxy Manager with Caddy Docker Proxy, introducing declarative container label routing and automated Let's Encrypt DNS-01 wildcard certificates (`*.kamaka.tech`).
* Implemented dual-domain routing: private internal homelab services on `*.kamaka.tech` via Pi-hole wildcard DNS, and public services on `*.kamakakai.com` via Cloudflare Zero Trust Tunnel.
* Deployed Mealie recipe manager (`recipes.kamaka.tech`, `recipes.kamakakai.com`, `mom.kamakakai.com`) with embedded SQLite storage, replacing Tandoor.
* Added client file delivery service (`https://download.kamaka.tech/`) with directory browsing for direct downloads to client devices.
* Applied Caddy ingress hardening: global security headers, sensitive dotfile blocking, diagnostic path blocking, and subnet isolation on administrative services.

### Changed
* Routed UGREEN NAS host portal through Caddy via HTTP (`192.168.255.1:9999`) with Caddy terminating TLS, eliminating self-signed certificate warnings.
* Integrated Mealie database staging into automated Restic volume backups.

### Removed
* Decommissioned Nginx Proxy Manager and associated manual certificate generation scripts.
* Decommissioned PostgreSQL database container and host boot readiness probes.
* Decommissioned Tandoor Recipes stack.

---

## [2.9.0] / [2026.11.2.3] - Service-First Discovery Engine & Orchestration Refactor (2026-11-02)

### Added
* Implemented service-first discovery engine, dynamically indexing enabled services and container names directly from `compose.yml` manifests.

### Changed
* Streamlined stack discovery so stack state is derived automatically from enabled services rather than manual `.disabled` directory markers.
* Modernized automated smoke test suites with unified service assertion helpers.
* Updated startup orchestration and secret handling to automatically adapt to dynamic service enablement.

---

## [2.8.0] / [2026.11.2.2] - Homelab Stack Consolidation & Semantic Rebalancing (2026-11-02)

### Changed
* Consolidated 11 granular Compose stacks into 6 domain-aligned stacks: `ingress`, `mesh`, `media`, `torrent`, `productivity`, and `dashboard`.
* Isolated VPN environments between the remote privacy exit node (`mesh`) and torrent acquisition client (`torrent`).
* Standardized deterministic startup sequence and adapted test suites to the consolidated stack topology.

### Fixed
* Corrected media acquisition SQLite database paths in backup automation to ensure persistent volume staging.

---

## [2.7.0] / [2026.11.2.1] - Homelab Administration Skills Suite & Dynamic Discovery (2026-11-02)

### Added
* Modular homelab administration and onboarding skills under `.skills/` (`start-homelab`, `stack-lifecycle`, `tls-certificates`, `disaster-recovery-drill`, `homelab-audit`).
* Dynamic stack discovery engine allowing runtime stack enablement without hardcoded stack lists.
* Adaptive test execution automatically skipping tests for omitted or disabled services.

---

## [2.6.0] / [2026.11.2] - Performance Tuning Runbook & Storage Anti-Thrashing (2026-11-02)

### Added
* Comprehensive post-setup performance and maintenance guide (`.docs/performance-optimization.md`).
* Automated anti-thrashing and memory write-caching preferences for qBittorrent via `set-qbt-port.sh`.
* In-memory transcoding scratch space (`tmpfs`) for Jellyfin, eliminating mechanical disk wear during stream transcoding.
* Automated write permission and torrent queue health verification in test suite.

### Changed
* Aligned VPN upstream DNS resolvers to Quad9 for privacy and malware blocking.
* Idempotent permission enforcement on download buffers in `homelab.sh setup`.

---

## [2.5.0] / [2026.11.1.2] - Modular Agent Skills Architecture & Documentation Hygiene (2026-11-01)

### Added
* Modular agent skills architecture under `.skills/` covering feature lifecycles, stack authoring, volume backups, network diagnostics, and test authoring.

### Changed
* Streamlined project conventions and delegated procedural workflows to modular skills.
* Reconciled documentation references and standardized systemd background backup timers.

---

## [2.4.0] / [2026.11.1.1] - Dedicated Tailscale PIA VPN Bridge & Environment Variable Standardization (2026-11-01)

### Added
* Dedicated `vpn-bridge` stack pairing Tailscale with Private Internet Access (WireGuard) to provide a private egress exit node for remote client devices.
* Policy routing rules allowing Tailscale control plane traffic over WireGuard without tripping VPN kill switches.

### Changed
* Standardized environment variable defaults to a Single Source of Truth in `.env.example` templates, enforcing strict variable assertions in Compose files.
* Inlined immutable architectural invariants directly into `compose.yml`.

### Security
* Isolated mobile and remote client internet traffic through encrypted VPN exit nodes while preserving private homelab routing.

---

## [2.3.0] / [2026.11.1] - Restic Backup Engine & Storage IOPS Hardening (2026-11-01)

### Added
* Restic-powered volume backup engine (`homelab.sh backup`) with 30-day retention pruning and scheduled nightly automation.
* Online zero-downtime database staging and untracked secret bundle archiving.
* Dedicated solid-state scratch directory for incomplete downloads to reduce storage contention.

### Changed
* Migrated Docker daemon root storage (`data-root`) to PCIe NVMe SSD, eliminating overlayfs I/O contention.
* Upgraded host `restic` binary to v0.19.1.

---

## [2.2.1] / [2026.10.30] - Modular Architecture & Documentation Overhaul (2026-10-30)

### Added
* Modular smoke and regression test suite under `.tests/` with categorized modules, skip support, and negative security assertions.
* Modular automation library under `.scripts/` eliminating duplicate orchestration logic.
* In-depth documentation under `.docs/` covering project organization, services, environment variables, networking, and operations.

### Changed
* Refactored `homelab.sh` to delegate specialized routines to `.scripts/` and test execution to `.tests/run.sh`.
* Streamlined root `README.md` as an executive overview and quickstart guide.

---

## [2.2.0] / [2026.10.29] - Tailscale Mesh Overlay & Subnet Routing (2026-10-29)

### Added
* Tailscale subnet router service (`tailscale/compose.yml`) dual-homed across `external_npm` macvlan (`192.168.0.5`) and `homelab` Docker bridge (`192.168.255.0/24`).
* Advertised `192.168.0.0/24` subnet route with SNAT masquerading to allow remote Tailnet peers to access LAN devices.
* Standardized split DNS routing directing Tailscale `.home` queries to local Pi-hole (`192.168.0.2`).
* Reverse proxy route `https://nas.turing.home` forwarding across Docker bridge to host OS portal (`https://192.168.255.1:9443`).

### Security
* Enforced subnet access control lists on internal virtual hosts in reverse proxy.

---

## [2.1.0] / [2026.10.29] - NVMe Storage Tiering & Seerr Integration (2026-10-29)

### Added
* Seerr media request management stack (`seerr/compose.yml`) integrated on `https://seerr.turing.home`.
* Standardized dual-volume storage architecture moving high-IOPS container data (`DOCKER_DATA_DIR`) to PCIe NVMe SSD (`/volume2/docker`) while retaining bulk media on RAID 5 HDD storage (`/volume1/media`).

### Changed
* Standardized deterministic service API keys (`*_API_KEY`) across Radarr, Sonarr, Prowlarr, and Seerr.
* Synchronized PIA WireGuard dynamic port forwarding callback script (`set-qbt-port.sh`) to automatically update qBittorrent listening port via WebUI API.

---

## [2.0.3] / [2026.10.28.3] - Cloudflare Tunnel Egress & Domain Verification (2026-10-28)

### Added
* Cloudflare Zero Trust tunnel stack (`cloudflared/compose.yml`) routing public wildcard traffic down an outbound tunnel.
* Public ingress endpoints for external streaming and recipe sharing.

### Security
* Hardened external media proxy hosts with blocks on `/metrics`, `/swagger`, and `/api-docs`.
* Configured Cloudflare cache bypass rule to prevent video stream buffering.

---

## [2.0.2] / [2026.10.28.2] - Homepage Widget API & Jellyfin Proxy Subnets (2026-10-28)

### Fixed
* Corrected Homepage widget API version mapping for Jellyfin streams.
* Resolved Jellyfin reverse proxy subnet filtering by registering `192.168.255.0/24` as trusted proxies.
* Cleaned up redundant host port reservations across Compose stacks.

---

## [2.0.1] / [2026.10.28.1] - Tandoor Allowed Hosts & Smoke Test Suite (2026-10-28)

### Added
* Automated smoke test suite in `homelab.sh test` covering container states, direct ports, and reverse proxy virtual host routing via client impersonation.

### Fixed
* Configured `ALLOWED_HOSTS` in Tandoor Recipes to permit incoming requests from domain hosts.
* Provisioned missing reverse proxy hosts for backend services.

---

## [2.0.0] / [2026.10.28] - Declarative Homelab Architecture Release (2026-10-28)

### Added
* Initial standardized homelab architecture managing 15 containerized services with Dockge.
* Dual-ingress networking separating public web ingress (`external_npm` macvlan) and backend traffic (`homelab` bridge).
* Two-tier environment architecture (`.env.example` templates with global inheritance).
* Comprehensive management and configuration deployment script `homelab.sh`.
