# Changelog

All notable changes to the homelab infrastructure, service stacks, automation scripts, and documentation are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Major releases are paired with their semantic version and chronological (CalVer) git tag.

---

## [2.3.0] / [2026.11.1] - Restic Backup Engine & Storage IOPS Hardening (2026-11-01)

### Added
* Unified Restic backup engine (`.scripts/backup.sh`) snapshotting persistent volume state (`/volume2/docker`) to `/volume1/backups/homelab-docker` with 30-day retention pruning.
* Zero-downtime database staging (`pg_dumpall` for PostgreSQL, SQLite `.backup` for NPM, Jellyfin, Sonarr, Radarr, Prowlarr) and encrypted/sanitized `.env` secret bundle archiving.
* Systemd background backup timer (`homelab-backup.timer`) and service (`homelab-backup.service`) executing scheduled nightly backups at 03:00.
* Declarative NVMe incomplete torrents directory mount (`/volume2/docker/qbittorrentvpn/data/incomplete`) isolating random write thrashing during active downloads.
* Automated backup and disaster recovery test suite (`.tests/suites/test_backup.sh`) integrated into `homelab.sh test`.

### Changed
* Deprecated legacy bidirectional `pull-configs` and `deploy-configs` scripts in favor of native Restic snapshot management and disaster recovery (`./homelab.sh restore`).
* Migrated Docker daemon root storage (`data-root`) from RAID 5 HDD (`/volume1/@docker`) to PCIe NVMe SSD (`/volume2/@docker`), eliminating container overlayfs I/O contention.
* Hardened qBittorrent disk queueing, piece extent affinity, and POSIX asynchronous I/O (`pread`/`pwrite`), dropping mechanical array utilization from 100% to under 5%.
* Upgraded host `restic` binary to v0.19.1 with repository format v2.

### Fixed
* Purged unlinked duplicate and orphaned download clutter in `/volume1/media/downloads/` while preserving library hardlinks.
* Restored active automated Tailscale subnet router backend health verification (`test_interconnect_tailscale_backend_state`) in test suite.

---

## [2.2.1] / [2026.10.30] - Modular Architecture & Documentation Overhaul (2026-10-30)

### Added
* Modular smoke and regression test suite under `.tests/` with 5 category suites, explicit `test_*` naming, exit-code 77 skip support, and 7 negative security & isolation assertions.
* Modular automation library under `.scripts/` (`common.sh`, `env-tools.sh`, `system.sh`, `configs.sh`, `backup.sh`) eliminating ~225 lines of duplicate boilerplate.
* Deep topic documentation under `.docs/` (`project-organization.md`, `service-catalog.md`, `env-reference.md`, `networking.md`, `operations.md`).
* Project technical backlog (`BACKLOG.md`) tracking pending optimizations.

### Changed
* Refactored `homelab.sh` from 1,092 lines to 243 lines, delegating specialized routines to `.scripts/` and test execution to `.tests/run.sh`.
* Streamlined root `README.md` from 730 lines down to 82 lines as an executive portal and quickstart guide.
* Updated service catalog to reflect true active network bindings and standardized LAN/WAN addresses.

---

## [2.2.0] / [2026.10.29] - Tailscale Mesh Overlay & Subnet Routing (2026-10-29)

### Added
* Tailscale subnet router service (`tailscale/compose.yml`) dual-homed across `external_npm` macvlan (`192.168.0.5`) and `homelab` Docker bridge (`192.168.255.0/24`).
* Advertised `192.168.0.0/24` subnet route with SNAT masquerading to allow remote Tailnet peers to access LAN devices.
* Standardized split DNS guidance directing Tailscale `.home` queries to local Pi-hole (`192.168.0.2`).
* Reverse proxy route `https://nas.turing.home` forwarding across Docker bridge to host OS portal (`https://192.168.255.1:9443`), bypassing Linux kernel macvlan host-drop restrictions.
* Automated smoke test check in `homelab.sh test` verifying Tailscale subnet router daemon authentication and `Running` backend state.

### Security
* Enforced subnet access control lists (`allow 192.168.0.0/16; allow 127.0.0.1; deny all;`) on all internal `*.turing.home` virtual hosts in Nginx Proxy Manager.

---

## [2.1.0] / [2026.10.29] - NVMe Storage Tiering & Seerr Integration (2026-10-29)

### Added
* Seerr media request management stack (`seerr/compose.yml`) integrated on `https://seerr.turing.home`.
* Inter-container REST API probes in `homelab.sh test` verifying communication between Jellyfin and Seerr.
* Standardized dual-volume storage architecture moving high-IOPS container data (`DOCKER_DATA_DIR`) to PCIe NVMe SSD (`/volume2/docker`) while retaining bulk media on RAID 5 HDD storage (`/volume1/media`).

### Changed
* Standardized deterministic service API keys (`*_API_KEY`) across Radarr, Sonarr, Prowlarr, and Seerr.
* Synchronized PIA WireGuard dynamic port forwarding callback script (`set-qbt-port.sh`) to automatically update qBittorrent listening port via WebUI API.

---

## [2.0.3] / [2026.10.28.3] - Cloudflare Tunnel Egress & Domain Verification (2026-10-28)

### Added
* Cloudflare Zero Trust tunnel stack (`cloudflared/compose.yml`) routing public wildcard `*.kamaka.tech` traffic down an outbound tunnel to Nginx Proxy Manager.
* Public ingress endpoints for external Jellyfin streaming (`jellyfin.kamaka.tech`) and recipe sharing (`recipes.kamaka.tech`).

### Security
* Hardened external Jellyfin proxy host with reverse proxy blocks returning HTTP 403 on `/metrics`, `/swagger`, and `/api-docs`.
* Configured Cloudflare cache bypass rule for `jellyfin.kamaka.tech` to prevent video stream buffering.

---

## [2.0.2] / [2026.10.28.2] - Homepage Widget API & Jellyfin Proxy Subnets (2026-10-28)

### Fixed
* Corrected Homepage widget API version mapping for Jellyfin streams.
* Resolved Jellyfin reverse proxy subnet filtering by registering `192.168.255.0/24` as trusted proxies.
* Cleaned up redundant host port reservations across Compose stacks.

---

## [2.0.1] / [2026.10.28.1] - Tandoor Allowed Hosts & Smoke Test Suite (2026-10-28)

### Added
* Fast automated smoke test suite in `homelab.sh test` covering container states, direct ports, and NPM virtual host routing via client impersonation.

### Fixed
* Configured `ALLOWED_HOSTS` in Tandoor Recipes to permit incoming requests from `recipes.turing.home` and `recipes.kamaka.tech`.
* Provisioned missing Nginx Proxy Manager proxy hosts for backend services.

---

## [2.0.0] / [2026.10.28] - Declarative Homelab Architecture Release (2026-10-28)

### Added
* Initial standardized homelab architecture managing 15 containerized services with Dockge.
* Dual-ingress networking separating public web ingress (`external_npm` macvlan) and backend traffic (`homelab` bridge).
* Two-tier environment architecture (`.env.example` templates with global inheritance).
* Comprehensive management and configuration deployment script `homelab.sh`.
