# Phase 2: Documentation Modularization and Lifecycle Plan

## Executive Summary
The current `README.md` is **730 lines** long and attempts to serve simultaneously as an onboarding guide, cloud dependency registry, environment variable dictionary, network specification, service catalog, port map, hardening runbook, and host OS engineering manual. This monolithic structure overwhelms LLM context windows, slows retrieval, and makes incremental documentation maintenance difficult.

This plan details **Phase 2**:
1. Decomposing `README.md` into focused, cohesive documents located under `.docs/` (preserving 100% Dockge stack compatibility).
2. Adding a dedicated **Project Organization** document (`.docs/project-organization.md`) detailing the repository structure, Dockge compatibility, storage tiering, and git lifecycle.
3. Creating a standardized **Service Catalog** (`.docs/service-catalog.md`) where every service has a uniform metadata table and structured text block (modeled after cloud provider entries), reflecting only true active port bindings and eliminating misleading historical port forwarding references.
4. Creating a dedicated **Environment Reference & Cheat Sheet** (`.docs/env-reference.md`) consolidating root and per-stack variables, defaults, secrets, and cross-links.
5. Creating dedicated **Networking & Security** (`.docs/networking.md`) and **Operations** (`.docs/operations.md`) guides.
6. Establishing root **`CHANGELOG.md`** (associating each major release with both semantic and CalVer tags, a descriptive headline, and categorized change sections) and **`BACKLOG.md`** (with one medium-priority item).
7. Codifying an automated changelog maintenance rule in `.agents/rules/project-conventions.md`.
8. Reducing `README.md` to a concise, high-impact landing page (~120–150 lines) with architecture topology, quickstart, and a comprehensive table of contents linking to all modular guides.

---

## 1. Documentation Architecture & Directory Structure

To ensure Dockge never misidentifies documentation folders as Compose stacks, all modular documentation will be organized under `.docs/`:

```text
.
├── README.md                   # Lean landing page: topology, quickstart, CLI summary, doc navigation (~120-150 lines)
├── CHANGELOG.md                # Official release changelog (paired SemVer + CalVer tags, headlines, categorized bullets)
├── BACKLOG.md                  # Project backlog (initialized with 1 medium-priority item)
└── .docs/
    ├── project-organization.md # Repository layout, Dockge compatibility, storage tiers, and git lifecycle
    ├── service-catalog.md      # Uniform service entries: metadata tables + capability/configuration text blocks (true ports only)
    ├── env-reference.md        # Two-tier .env dictionary, defaults, secrets, and Homepage widget keys
    ├── networking.md           # Dual-ingress topology, subnets, macvlan, IP tables, TLS certs & security blocks
    └── operations.md           # CLI workflows (homelab.sh), systemd services, storage tiering & host engineering
```

---

## 2. Modular Document Specifications

### 2.1 `README.md` (Target: ~120–150 lines)
* **Purpose**: Primary repository entrypoint and quick-reference portal.
* **Sections**:
  1. **Overview & High-Level Topology**: ASCII dual-ingress diagram (Cloudflare vs Tailscale) and repository role.
  2. **Quickstart**: Fresh host provisioning (1-2-3 steps) and routine update command.
  3. **Automation Summary**: Table of `homelab.sh` subcommands (`setup`, `startup`, `deploy-configs`, `pull-configs`, `backup`, `test`).
  4. **Documentation Index**: Structured table of contents linking directly to `.docs/project-organization.md`, `.docs/service-catalog.md`, `.docs/env-reference.md`, `.docs/networking.md`, `.docs/operations.md`, `CHANGELOG.md`, and `BACKLOG.md`.

### 2.2 `.docs/project-organization.md` (Project Organization & Architecture)
* **Purpose**: Explains how the repository is structured, managed, and deployed.
* **Sections**:
  1. **Repository Layout**: Explanation of stack directories vs hidden infrastructure folders (`.configs/`, `.scripts/`, `.tests/`, `.docs/`, `.agents/`).
  2. **Dockge Compatibility Rules**: Working directory constraints, root stack isolation, and why Dockge itself lives one level above in `${DOCKGE_DIR}/compose.yml`.
  3. **Storage Tiering Architecture**: Physical NVMe SSD (`/volume2/docker`) for high random 4K IOPS vs RAID 5 HDD mechanical array (`/volume1/media`) for sequential throughput.
  4. **Configuration & Git Lifecycle**: How tracked configurations in `.configs/` map to live host data volumes, bidirectional sync model, and backup archiving.

### 2.3 `.docs/service-catalog.md` (Service Catalog & True Port Map)
* **True Port Information**: Completely removes legacy/historical port mappings (e.g. `8020/8021`, `8040`, `8050`). Accurately documents that only Dockge (`8010:5001`), Jellyfin Discovery (`8022:7359/udp`), and the macvlan IPs (`192.168.0.4` NPM, `192.168.0.5` Tailscale) have external bindings, while all other services are bridge-isolated.
* **Standardized Format**: Each of the 15 services (and host OS portal) follows a uniform layout:
  1. **Metadata Table**:
     | Service | Stack Directory | Container Name | Host / Network Binding | Container Port | Ingress & Routing | Persistent Data Path | Secrets / Keys |
     | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
  2. **Structured Text Block**:
     - **Role & Capabilities**: What the service does in the homelab.
     - **Network & Access**: Internal URL (`*.turing.home`) and external URL (`*.kamaka.tech`), if applicable.
     - **Storage & Volume Mappings**: Host paths mapped to container volumes.
     - **Dependencies & Interconnections**: What other containers or databases it connects to.
* **Summary Port Table**: Clean, accurate matrix of active ports and listeners across the homelab.

### 2.4 `.docs/env-reference.md` (Environment Cheat Sheet)
* **Purpose**: Comprehensive, single-pane dictionary of every environment variable in the project.
* **Sections**:
  1. **Global Root Variables (`.env.example`)**: `DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`, `TAILSCALE_IPV4_ADDRESS`.
  2. **Per-Service Stack Variables & Secrets**: Grouped by stack directory (`cloudflared`, `tailscale`, `qbittorrentvpn`, `jellyfin`, `sonarr-radarr`, `seerr`, `tandoor`, `homepage`, `postgres`, `nginx`).
  3. **Homepage Dashboard Variables**: Detailed explanation of Docker container label interpolation vs static `HOMEPAGE_VAR_*` substitution.
  4. **Cross-Reference Links**: Anchors linking variable definitions to the corresponding service entries in `service-catalog.md`.

### 2.5 `.docs/networking.md` (Dual-Ingress, Routing & Security)
* **Sections**:
  1. **Pillar 1: Public Web Ingress**: Cloudflare Zero Trust tunnel, outbound QUIC connection, wildcard `*.kamaka.tech` routing.
  2. **Pillar 2: Private Admin Ingress**: Tailscale mesh, subnet routing (`192.168.0.0/24`), dual-homing on `external_npm` (`192.168.0.5`), and `nas.turing.home` host isolation bypass.
  3. **Subnets and Static IP Assignments**: Table of LAN devices (`192.168.0.1`–`192.168.0.5`), `homelab` bridge (`192.168.255.0/24`), and Pi-hole split DNS.
  4. **TLS & Certificate Management**: Step-by-step for the combined local wildcard cert (`generate-local-cert.sh`) and Cloudflare Let's Encrypt wildcard cert.
  5. **Security Hardening**: Jellyfin metric/swagger blocks, Cloudflare video cache bypass, and reverse proxy access lists (`192.168.0.0/16`).

### 2.5 `.docs/operations.md` (Operations & Appliance Engineering)
* **Sections**:
  1. **`homelab.sh` Operational Runbooks**: Step-by-step procedures for deploying configs, pulling live configs, creating CalVer/semantic backups, and restoring secrets on fresh hosts.
  2. **Systemd Services**: Unit definitions and deployment for `antigravity-remote-control.service` and `homelab-startup.service`.
  3. **Appliance Workarounds**: Asynchronous volume mount handling in UGOS Pro, user lingering (`loginctl enable-linger`), and Go 1.23+ `GODEBUG=tlskyber=0` fix.

---

## 3. Project Governance, Changelog & Backlog

### 3.1 `CHANGELOG.md`
* Format: Semantic version header with headline name, paired CalVer release tag, release date, and categorized change sections (`Added`, `Changed`, `Fixed`, `Security`).
* Seeded historical releases:
  - `## [2.2.0] / [2026.10.29] - Tailscale Mesh Overlay & Subnet Routing (2026-10-29)`
  - `## [2.1.0] / [2026.10.29] - NVMe Storage Tiering & Seerr Integration (2026-10-29)`
  - `## [2.0.3] / [2026.10.28.3] - Cloudflare Tunnel Egress & Domain Verification (2026-10-28)`
  - `## [2.0.2] / [2026.10.28.2] - Homepage Widget API & Jellyfin Proxy Subnets (2026-10-28)`
  - `## [2.0.1] / [2026.10.28.1] - Tandoor Allowed Hosts & Smoke Test Suite (2026-10-28)`
  - `## [2.0.0] / [2026.10.28] - Declarative Homelab Architecture Release (2026-10-28)`

### 3.2 `BACKLOG.md`
* Formatted cleanly with item ID, title, priority, impact, description, and execution criteria.
* Seeded with the single medium-priority backlog item:
  - **Item #1 (Medium)**: *Tailscale tmpfs Socket Optimization*
    - **Description**: Add `tmpfs: [/tmp]` to `tailscale/compose.yml` so that Tailscale's UNIX domain socket (`/tmp/tailscaled.sock`) is held in RAM rather than the container overlayfs.
    - **Motivation**: Eliminates disk write contention and latency during heavy host disk I/O, preventing daemon startup timeouts and ensuring no stale socket artifacts persist across restarts.
    - **Trigger**: Execute after the host RAID 5 rebuild completes.

### 3.3 Rule Addition in `.agents/rules/project-conventions.md`
Add a dedicated rule under Section 4:
* **Changelog Maintenance**:
  - Update `CHANGELOG.md` exclusively upon major, semantically tagged releases (e.g. via `./homelab.sh backup --tag <semver>`).
  - Format each major entry with a semantic version header, paired CalVer tag, descriptive headline, release date, and categorized bulleted lists (`Added`, `Changed`, `Fixed`, `Security`).
  - Aggregate changes between releases into curated, meaningful bullet points; omit negligible micro-commits, syntax tweaks, or documentation typos.

---

## 4. Execution Sequence

1. **Rule Codification**: Update `.agents/rules/project-conventions.md` with the changelog update rule.
2. **Backlog & Changelog Creation**: Create `BACKLOG.md` and `CHANGELOG.md` at the repository root.
3. **Modular Documents Extraction**:
   - Create `.docs/project-organization.md`.
   - Create `.docs/service-catalog.md` with true port information and uniform entries.
   - Create `.docs/env-reference.md` with complete variable dictionary and cross-links.
   - Create `.docs/networking.md`.
   - Create `.docs/operations.md`.
4. **Refactor Root `README.md`**:
   - Rewrite `README.md` to be lean (~120–150 lines), containing high-level topology, quickstart, CLI summary, and comprehensive document navigation links.
5. **Content Completeness & Integrity Verification**:
   - Conduct a comprehensive line-by-line / section-by-section audit against the original 730-line `README.md` to ensure zero critical information is lost:
     - Cloud dependencies & credentials (Cloudflare, Tailscale, PIA, GitHub) -> accounted for in `.docs/service-catalog.md` and `.docs/networking.md`.
     - Environmental host assumptions (CGNAT, gateway, Pi-hole, Debian/UGOS) -> accounted for in `.docs/project-organization.md` and `.docs/networking.md`.
     - All 28 environment variables, defaults, and descriptions -> accounted for in `.docs/env-reference.md`.
     - Homepage label and `HOMEPAGE_VAR_*` mechanisms -> accounted for in `.docs/env-reference.md`.
     - Operational guides (NPM proxy git sync, Homepage YAML deploy, backup & secret restore) -> accounted for in `.docs/operations.md`.
     - Dual-ingress network topology, macvlan routing, and IP tables -> accounted for in `.docs/networking.md`.
     - All 15 services + host OS portal entries -> accounted for in `.docs/service-catalog.md`.
     - TLS certificate procedures (local wildcard script & Cloudflare DNS challenge) -> accounted for in `.docs/networking.md`.
     - Security hardening procedures (Jellyfin reverse-proxy blocks, Cloudflare video cache bypass, user lockout) -> accounted for in `.docs/networking.md` and `.docs/service-catalog.md`.
     - Storage tiering (NVMe vs RAID 5 HDD), packages, systemd unit templates, and GODEBUG fix -> accounted for in `.docs/project-organization.md` and `.docs/operations.md`.
   - Validate all internal markdown links and cross-references to confirm zero broken links.
6. **Commit Phase 2**:
   - Commit all documentation modularization changes to `refactor/modular-test-suite`.
