# Changelog

All notable changes to the homelab infrastructure, service stacks, automation scripts, and documentation are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Major releases are paired with their semantic version and chronological (CalVer) git tag.

---

## [2.7.0] / [2026.11.2.1] - Project Administration Skills Suite, Dynamic Stack Discovery & Adaptive Testing (2026-11-02)

### Added
* Comprehensive suite of homelab administration and onboarding agent skills under `.agents/skills/` (and `.skills/`):
  - `start-homelab`: Interactive onboarding wizard for new repository instantiations guiding service needs assessment (keep, defer, prune), hardware/platform constraint handling (UGOS, Synology DSM, Generic Linux, QuickSync `/dev/dri`, RAM sizing for tmpfs), provider adaptation (PIA, ProtonVPN, Mullvad, AirVPN, Cloudflare Tunnel, Tailscale), adaptation plan generation (`plan_<name>.md`), secret provisioning, and verified deployment. Includes 3 reference guides: `service-matrix.md`, `hardware-platforms.md`, and `provider-adapters.md`.
  - `stack-lifecycle`: Standardized operational runbook for adding or decommissioning services across all 6 homelab architectural touchpoints (Compose specification, environment templates, reverse proxy virtual hosts, dashboard widgets, backup policies, and automated smoke test assertions).
  - `tls-certificates`: Local TLS certificate management, internal root CA generation, wildcard `*.home` certificate provisioning, NPM and UGOS import, and client OS trust distribution across macOS, Windows, Linux, iOS, Android, and Firefox.
  - `disaster-recovery-drill`: Operational runbook for zero-downtime disaster recovery drills; restores Restic snapshots into an isolated sandbox staging directory (`/tmp/dr-drill`), verifies PostgreSQL logical cluster dumps and SQLite databases via `PRAGMA integrity_check`, without interrupting production services.
  - `homelab-audit`: Systematic drift detection and compliance auditing runbook across container runtimes/health, service and image tag skew, environment variable drift, untracked containers, volume permissions (`1000:100`), UGOS ACLs (`system.ugacl_self`), Btrfs No-CoW flags (`+C`), reverse proxy virtual hosts, backup timers, and host system services/daemons (systemd unit diffs, Docker daemon configs, dirty memory sysctls, Go Kyber defect re-injection checks, and convenience symlinks).
* Dynamic stack discovery engine (`discover_stacks`, `is_stack_enabled`) in `.scripts/common.sh`, scanning root directories for `compose.yml` and ignoring `.disabled` markers.
* Adaptive test skipping (`exit 77` / `[SKIP]`) across all `.tests/suites/*.sh` test suites when stacks are disabled or omitted, maintaining 100% clean test runs regardless of enabled service configuration.
* Dynamic probe container fallback in routing and security test suites, ensuring reverse proxy client impersonation tests execute reliably even when specific media indexers are deferred.
* Initial project direction guidance in `.agents/rules/project-conventions.md` directing newly instantiated agents on fresh clones to invoke `start-homelab`.
* Tracked backlog item `[BACKLOG-002]` in `BACKLOG.md` for deferred volume-tiering skill.

### Changed
* Refactored `homelab.sh` setup, startup, backup, and test orchestration to consume dynamic stack discovery from `.scripts/common.sh` in place of brittle static stack arrays.
* Updated `README.md` Section 5 with the full project administration and operational skills catalog.
* Updated `.docs/project-organization.md` repository tree documenting `.agents/` and `.skills/` organizational conventions.

### Fixed
* Enhanced PostgreSQL readiness probe in `homelab.sh` to check both `postgresql` and `postgres` container names.

---

## [2.6.0] / [2026.11.2] - Post-Setup Optimization Runbook, Storage Performance Hardening & qBittorrent Resilience (2026-11-02)

### Added
* Comprehensive *Post-Setup Optimization, Ergonomics & Maintenance Guide* (`.docs/performance-optimization.md`) documenting 16 post-setup tuning areas across storage tiering, Btrfs No-CoW (`+C`), Linux virtual memory dirty page smoothing, in-memory transcoding caches, Cloudflare edge bypass, and Tailscale split-DNS.
* Automated anti-thrashing preferences injected directly into qBittorrent via `set-qbt-port.sh` (512MB RAM write cache, piece extent affinity, suggest mode, and WireGuard `wg0` interface binding).
* Automated non-root volume write permission and torrent error health regression tests (`test_interconnect_qbittorrent_volume_write_permissions`, `test_interconnect_qbittorrent_torrent_error_status`) in `.tests/suites/test_interconnect.sh`.
* 4GB in-memory transcoding scratch space (`tmpfs`) mounted on `/transcode` in `jellyfin/compose.yml` and configured in `encoding.xml`, eliminating physical disk wear during live video transcoding.
* Automated convenience symlink provisioning (`${TARGET_HOME}/services -> ${REPO_DIR}`) codified into `homelab.sh setup`.

### Changed
* Aligned qBittorrent WireGuard VPN upstream resolver (`VPNDNS`) to Quad9 (`9.9.9.9`, `149.112.112.112`) for malware blocking, DNSSEC validation, and Swiss GDPR privacy compliance, matching `vpn-bridge`.
* Standardized systemd unit paths in `.configs/systemd/homelab-startup.service` to `/opt/brandon/dockge/stacks`.
* Expanded `.docs/env-reference.md` with Section 3 documenting inlined architectural invariants and audited global variables.
* Reconciled service catalog entries in `.docs/service-catalog.md` and volume paths across all 11 stacks.
* Relocated Cloudflare CDN cache bypass guidance from security hardening to the performance optimization guide and cloud ingress documentation.

### Fixed
* Remediated qBittorrent download failures and torrent freeze (`state: error`) caused by UGOS proprietary extended attribute (`system.ugacl_self`) and POSIX mode `0000` masking on `/incomplete`.
* Enforced `chmod 775` permissions on the qBittorrent incomplete download buffer idempotently inside `homelab.sh setup`.

---

## [2.5.0] / [2026.11.1.2] - Modular Agent Skills Architecture & Documentation Hygiene (2026-11-01)

### Added
* Modular agent skills architecture under `.agents/skills/` (mirrored via `.skills/`) employing progressive disclosure and structured prompt algorithms:
  - `feature-initiation`: Mainline sync, branch checkout, plan drafting, and adversarial "grill-me" design review cycle.
  - `feature-completion`: Test suite verification, stop-on-failure, roll-up SemVer/CalVer changelog synthesis, merge, and dual tagging.
  - `stack-authoring`: Compose authoring guidelines, canonical key ordering, variable assertion syntax (`${VAR:?See env.example for default.}`), non-root user model, and network attachment.
  - `backup-recovery`: Restic volume snapshot management, online database staging, snapshot inspection, and full/granular disaster recovery.
  - `network-diagnostics`: Diagnostic triage flowchart for reverse proxy virtual hosts, container DNS, WireGuard killswitches, and Tailscale routing.
  - `test-authoring`: Systematic recipe for authoring automated smoke, interconnect, and negative security tests in `.tests/suites/`.
* Supporting reference documentation for each skill under `.agents/skills/<name>/references/` (SemVer/CalVer tier guidelines, Compose specification, restore runbooks, routing topologies, and test suite catalogs).

### Changed
* Streamlined `.agents/rules/project-conventions.md` to focus strictly on invariant guardrails, persona/tone, and security boundaries, delegating procedural workflows to on-demand skills.
* Removed all hardcoded `file:///` URIs across documentation, replacing them with standard Markdown relative links.
* Audited and updated stale documentation references in `.docs/networking.md`, `.docs/env-reference.md`, and `.agents/artifacts/architecture.md` left over from the Restic backup migration.
* Added Section 4.3 to `.docs/operations.md` tracking systemd nightly backup service and timer unit definitions.
* Pruned leftover untracked directories (`.configs/nginx/nginx/`) to maintain repository hygiene.

---

## [2.4.0] / [2026.11.1.1] - Dedicated Tailscale PIA VPN Bridge & Environment Variable Standardization (2026-11-01)

### Added
* Dedicated `vpn-bridge` stack (`vpn-bridge/compose.yml`) pairing a Private Internet Access (PIA) WireGuard container (`vpn-bridge-pia`) with a Tailscale container (`vpn-bridge-tailscale`) advertising itself as an exit node (`--advertise-exit-node`).
* Kernel policy routing rule (`priority 5200`) directing Tailscale daemon traffic (`fwmark 0x80000`) into WireGuard table `51820`, enabling seamless DERP/control plane connectivity over WireGuard without tripping PIA's LAN kill switch.
* Automated container health and egress assertions in test suite (`test_docker_up_vpn_bridge_*`, `test_interconnect_vpn_bridge_pia_egress`, `test_interconnect_vpn_bridge_tailscale_backend_state`).
* Standardized feature completion runbook and skill (`.agents/skills/feature-completion/SKILL.md`) with strict stop-on-failure verification, changelog roll-up synthesis, and dual SemVer/CalVer tagging.

### Changed
* Overhauled repository-wide environment variable defaults to enforce a Single Source of Truth: all defaults are declared strictly in `.env.example` templates, while all Compose files use required assertion syntax `${VAR:?See env.example for default.}`.
* Inlined immutable stack invariants (`HOMEPAGE_ALLOWED_HOSTS`, `LOG_LEVEL`, `TS_EXTRA_ARGS`, and `CAPTCHA_SOLVER`) directly into `compose.yml` rather than exposing them as environment variables.
* Automated generation of 50-character cryptographic tokens for Django `SECRET_KEY` inside `.scripts/env-tools.sh` during `homelab.sh setup` if unpopulated.
* Switched `vpn-bridge` upstream resolver (`VPNDNS`) to Quad9 (`9.9.9.9`, `149.112.112.112`) for Swiss GDPR-compliant, privacy-audited, malware-blocking DNS with DNSSEC validation.
* Removed Tailscale CGNAT subnet (`100.64.0.0/10`) from `LOCAL_NETWORK` to eliminate routing conflicts with the Linux Forwarding Information Base.

### Security
* Complete isolation of exit node WAN traffic through domestic US PIA endpoints (Chicago / East Coast), masking mobile and remote client ISP addresses while preserving split-LAN access to private homelab services (`*.turing.home`).

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
