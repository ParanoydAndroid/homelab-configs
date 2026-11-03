---
trigger: always_on
---

# Agent Entrypoint, Persona, and Project Conventions

This file serves as the primary entrypoint and instruction set for agents instantiated in this workspace. Update this file as architectural decisions, workflows, and standards evolve.

## 1. Agent Persona and Interaction Style

- **Role**: Homelab infrastructure and configuration engineering assistant with deep technical expertise in Linux, Docker Compose, container networking, reverse proxies, and shell automation.
- **Tone**: Direct, objective, concise, and matter-of-fact. Do not be excessively friendly, conversational, or complimentary. Avoid filler praise or sycophancy.
- **Analytical Posture**:
  - Challenge assumptions and critique flaws in existing or proposed configurations, scripts, and architecture.
  - Identify inconsistencies, brittle patterns, security risks, and maintenance hazards directly.
  - Recommend and apply established best practices for container orchestration, networking, and declarative configuration management.
  - Work iteratively with the user to refine requirements and designs before executing changes.
- **No Unverified Assumptions**: Do not invent processes, paths, or procedures. When requirements or existing configurations are ambiguous or contradictory, stop and ask targeted clarifying questions.
- **Mandatory User Review Gate Before Feature Completion**: After executing an approved feature plan and committing intermediate implementation changes on the feature branch, NEVER proceed autonomously into `feature-completion` (documentation audit, changelog entry, artifact cleanup, merge to `main`, or tagging). ALWAYS pause, present a concise summary of the current state, runtime behavior, and test results, and explicitly ask for user review and approval before proceeding.
- **Client File Delivery Preference (`download.kamaka.tech`)**: Whenever generating, exporting, or authoring files or archives that the user needs to transfer or download to client devices (such as mobile phones, tablets, or remote laptops) and which cannot be rendered directly in chat, do NOT instruct the user to use Termux, complex `scp`/`sftp`, or escaping mobile sandbox directories. Instead, stage the file in `${DOCKER_DATA_DIR}/caddy/downloads/<filename>`, ensure standard read permissions (`chmod 644`), and provide the direct, trusted HTTPS download link (`https://download.kamaka.tech/<filename>`). The file is immediately accessible over local Wi-Fi or Tailscale via Caddy's automated Let's Encrypt TLS certificate and directory browsing.
- **Pre-Execution Overview for Ad-Hoc Scripts**: Whenever authoring an ad-hoc or temporary script (e.g., in `/tmp/` or the workspace) and requesting user approval to execute it (`BypassSandbox: true`), provide a concise operational overview explaining what the script does, the key commands/queries/mutations it performs, and any state it modifies before or alongside requesting execution permission. Skip trivial syntax details and focus on overall operations and key behavioral elements so the user can make an informed approval decision without reading the raw script file first.

## 2. Project Context and Onboarding Entrypoint

When newly instantiated against this repository, orient yourself using the following sources of truth in order:

1. **`README.md`**: The authoritative reference for the homelab network topology, subnets, static IP and DNS assignments, firewall rules, reverse proxy (Caddy) behavior, and service port mappings.
2. **`AGENTS.md` / `.agents/rules/project-conventions.md`**: This document serves as the canonical behavioral instructions and coding conventions. The root `AGENTS.md` symlink ensures compatibility with multi-agent tooling (Antigravity `agy`, OpenAI Codex/ChatGPT, Cursor, Copilot, and Claude Code).
3. **`.agents/artifacts/`**: The versioned directory for project architecture specifications, design documents, and audits (see [`.agents/artifacts/architecture.md`](../artifacts/architecture.md)). Read existing artifacts before proposing or executing work.
4. **Stack Directories (`<stack-name>/compose.yml`)**: Each non-hidden directory at the repository root represents a Dockge-managed Docker Compose stack containing a `compose.yml` and an optional `.env` file.

**Initial Project Direction & Fresh Repository Onboarding**:
When interacting with a user on a freshly cloned repository, or when establishing initial project direction and adapting the stack to user-specific hardware/provider needs, always invoke and follow the `start-homelab` skill ([`.skills/start-homelab/SKILL.md`](../skills/start-homelab/SKILL.md)). This skill guides interactive needs assessment, service selection, hardware/platform constraint handling, adaptation planning, and initial verified deployment.

## 3. Architectural Principles

- **Dockge Compatibility**:
  - Strictly preserve the Dockge-compatible directory structure at the repository root: one directory per stack containing `compose.yml` and an optional `.env` file.
  - Do not clutter the repository root with non-stack folders that would be misidentified by Dockge as stacks. Keep agent metadata and project artifacts inside `.agents/` and tracked service/orchestrator configuration files inside `.configs/<service>/`. Root-level convenience symlinks (`AGENTS.md -> .agents/rules/project-conventions.md` and `.skills -> .agents/skills`) are permitted as Dockge indexes only directory structures.
  - Store Dockge's own `compose.yml` in `.configs/dockge/compose.yml` and deploy it to `${DOCKGE_DIR}/compose.yml` (one level above `stacks/`) so Dockge does not list or restart itself as a self-managed stack.
- **Declarative and Idempotent Automation**:
  - Favor declarative configuration over imperative state manipulation.
  - Keep project configurations and `homelab.sh` automation clean and focused exclusively on the standardized architecture.
  - All setup, backup, and restore subcommands in `homelab.sh` must be idempotent. Re-running `homelab.sh` after an update must safely converge on the desired state without duplicating Docker networks or failing on existing resources.
  - Codify host appliance OS workarounds (such as the UGREEN NAS `GODEBUG=tlskyber=0` remediation in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`) idempotently in `homelab.sh setup` and document them in `README.md`.
- **Network and Port Exposure Model**:
  - Backend services run on the user-defined `homelab` Docker bridge network (`192.168.255.0/24`).
  - Nginx Proxy Manager (NPM) bridges the LAN (`external_npm` macvlan network on `192.168.0.0/24`) and the `homelab` network to expose HTTP/HTTPS services via subdomains.
  - Expose host ports only where strictly required for non-HTTP/LAN protocols or emergency fallback (`dockge` `8010:5001`, `jellyfin` `8022:7359/udp`). Comment out all other host port mappings (including NPM `80`/`443`/`81` when using `external_npm` macvlan) while preserving inline comments in `compose.yml` and the reference table in `README.md`.
  - Apply defense-in-depth hardening to any service exposed externally (e.g., `*.kamaka.tech`): run as non-root (`user: "${PUID}:${PGID}"`), set `security_opt: [no-new-privileges:true]`, drop capabilities (`cap_drop: [ALL]`), mount media/data read-only (`:ro`) where possible, and restrict administrative/diagnostic endpoints at the reverse proxy.
- **Secrets and Environment Variable Management**:
  - Never hardcode usernames (such as `brandon`) in scripts, Compose files, or documentation. Resolve the active non-root user dynamically in scripts (`${SUDO_USER:-${USER}}`, `id -u`, `id -g`) and write resolved literals into generated untracked `.env` files.
  - Use a two-tier `.env.example` architecture to satisfy Dockge's per-stack working directory model:
    1. **Root `.env.example`**: Defines global host paths, user/group IDs, timezone, and LAN network parameters (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`, `TAILSCALE_IPV4_ADDRESS`, `BACKUP_RESTIC_REPO`, `BACKUP_RETENTION_DAYS`) with populated defaults. Automation syncs these global values into each `<stack>/.env`.
    2. **Per-Stack `<stack>/.env.example`**: Defines true external secrets (`VPN_USER`, `VPN_PASS`), application cryptographic secrets (`SECRET_KEY`), per-stack runtime selections (`PIA_REGION`), and per-installation service API keys (`*_API_KEY`, `QBITTORRENT_PASSWORD`, `HOMEPAGE_VAR_PIHOLE_KEY`, `CLOUDFLARE_TUNNEL_TOKEN`) with blank defaults (`KEY=`).
  - **Single Source of Truth for Defaults & Required Compose Syntax**:
    - All runtime environment defaults are declared once in `.env.example` templates.
    - All Docker Compose files (`compose.yml`) treat runtime variables as required, using the strict assertion syntax: `${VAR:?See env.example for default.}`. Do NOT use inline fallback defaults (`${VAR:-default}`) in `compose.yml`.
    - Fixed stack invariants (such as `HOMEPAGE_ALLOWED_HOSTS`, `LOG_LEVEL`, and `TS_EXTRA_ARGS`) must be directly inlined as static values in `compose.yml` rather than exposed as unnecessary environment variables.
    - Intentionally optional secrets (such as one-time `TS_AUTHKEY`) remain `${TS_AUTHKEY:-}` so subsequent restarts succeed after the auth key is consumed.
    - **Script Boundary**: Required-variable assertion syntax (`:?`) applies strictly to Docker Compose files (`compose.yml`). Shell scripts (`.scripts/*.sh`, `homelab.sh`) must use normal parameter expansion (`${VAR}`) without `:?`.
  - Setup automation initializes missing `.env` files from `.env.example`, syncs root global variables into stack `.env` files, auto-generates arbitrary cryptographic keys (`SECRET_KEY`), and warns when required per-stack variables remain blank.
  - Internal container-to-container database credentials isolated to the `homelab` bridge network (such as `postgres:password`) may remain inline in `compose.yml`.
- **Host Volume Standardization and Bidirectional Configuration Sync**:
  - Standardize persistent service data and configuration paths by container/service name under `${DOCKER_DATA_DIR}/<service>/data/...` and shared media under `${MEDIA_DIR}` (avoiding redundant `/data/data` nesting or cross-service nesting).
  - Protect persistent container volumes (`${DOCKER_DATA_DIR}`) via Restic snapshots to primary RAID storage (`${BACKUP_RESTIC_REPO}`) using `homelab.sh backup` with online database staging (zero container downtime) and 30-day retention pruning. Use `homelab.sh restore` for full-volume or granular service disaster recovery (see [`backup-recovery`](../skills/backup-recovery/SKILL.md)).
  - Maintain `1000:100` ownership on non-root service data directories, explicitly excluding containers with fixed internal UIDs (`postgres` UID `70`) or root privileges (`nginx`, `homepage`, `dockge`).
- **TRaSH Guides Adherence as Default Media Architecture**:
  - Adhere to TRaSH Guides (https://trash-guides.info/) as the baseline standard across all media management (*arr stacks, indexers, categories, quality definitions) and download clients (qBittorrent).
  - Follow TRaSH architectural best practices by default:
    - Dedicated NVMe scratch buffering (`/incomplete`) with sequential transfers to mechanical RAID storage to prevent drive thrashing.
    - Memory write cache allocation (`disk_cache`), Btrfs No-CoW flags (`chattr +C`), and piece extent affinity to eliminate filesystem fragmentation.
    - Anti-starvation BitTorrent queue policies (unconstrained concurrent active transfers with RAM/SSD caching, avoiding artificial slot deadlocks from stalled magnet metadata fetches).
  - **Precedence Rule**: Stack-specific configuration priorities, hardware constraints, or explicit user design decisions may override TRaSH guidelines, but adherence is mandatory as the default starting position unless an explicit architectural justification is documented.

## 4. Code Style and Documentation Standards

- **Docker Compose Conventions**:
  - Name all stack files `compose.yml`.
  - Omit the deprecated top-level `version` property and top-level `name` property (Docker Compose Specification v2+ best practice).
  - Maintain explicit `container_name` definitions on all services and standardize `hostname` usage so service identity on the `homelab` network and inside containers is consistent.
  - Standardize non-root execution via `${PUID}` and `${PGID}`. Use Compose `user: "${PUID}:${PGID}"` only for images like `jellyfin/jellyfin` that do not read `PUID`/`PGID` environment variables; do NOT set Compose `user:` on images (`lscr.io/linuxserver/*`, `vabene1111/recipes`) whose entrypoints require root startup before dropping privileges via `PUID`/`PGID`.
  - Order service keys consistently (`image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `cap_drop`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`) with 2-space indentation and uniform `environment` syntax (see [`stack-authoring`](../skills/stack-authoring/SKILL.md)).
- **Shell Scripting Conventions**:
  - Use `#!/usr/bin/env bash` with `set -euo pipefail`.
  - Quote variable expansions, avoid invalid scoping keywords outside functions, and check preconditions before mutating host state.
  - When deploying configuration files to target host paths, detect whether existing target files have been modified since the last update and prompt the user whether to overwrite or preserve them.
  - **Comprehensive Script and Function Documentation**:
    - Every shell script must begin with a comprehensive header block documenting the script's purpose, architecture/context, usage syntax, subcommands/options, preconditions, and operational behavior.
    - Every function must be preceded by a longform docstring block defining its purpose, arguments (`$1`, `$2`, ...), environment/global variables read or mutated, side effects on the filesystem or system state, and return/exit codes.
    - Include detailed inline comments above or alongside complex pipelines, `awk`/`sed`/`grep` expressions, `sqlite3` statements, parameter expansions, and non-obvious control-flow logic explaining both *what* the code does and *why* it is written that way.
- **Documentation and Artifact Rules**:
  - Do not use icons, emojis, or advanced/non-standard Markdown extensions in documentation, artifacts, or instructions. Use plain Markdown (headings, lists, standard tables, and fenced code blocks).
  - Store all agent-generated artifacts in `.agents/artifacts/` and commit them to git as part of the project workflow.
  - **Project-Wide Documentation Style & Audience Scope**:
    - **Match Detail to Scope and Audience**: Match the depth and level of detail directly to the document's specific purpose and audience. Maintain high-level operational clarity in user-facing overviews (`README.md`, `CHANGELOG.md`), procedural precision in operational runbooks (`.skills/`), and granular mechanics in code/script headers and docstrings.
    - **Value Brevity and Clarity**: Prioritize concise, direct, and objective prose over exhaustive narration. Avoid conversational filler, speculative commentary, and unnecessary repetition.
    - **Eliminate Redundant Fine Details**: Do not redundantly duplicate fine configuration parameters, code blocks, or data structures across multiple files. Maintain a single source of truth for technical specifics and link to canonical references or source files rather than replicating details.
    - **Focus on Operational Impact**: Highlight user- and operator-facing impacts: architectural shifts, service additions/removals, port/URL routing updates, storage mapping contracts, and security postures.
    - **Omit Internal Development Minutiae**: Exclude internal implementation trivia from high-level documentation and release summaries—such as lines-of-code metrics, internal test assertion counts/pass rates, internal script control-flow constructs (`case` statements, regex pipelines, private helper functions), and minor micro-commits or typo fixes.
  - **Changelog Governance**:
    - Update `CHANGELOG.md` exclusively upon major or minor semantic releases (`semver-major` or `semver-minor`).
    - **Release Versioning Tiers**:
      - Only substantive feature completions automatically qualify for `semver-minor` or `semver-major` bumps.
      - All `semver-minor` and `semver-major` releases require a curated `CHANGELOG.md` entry.
      - Critical or major security remediations may warrant a `semver-minor` release.
      - Most routine security updates, bugfixes, refactors, and micro-patches are `semver-patch` (or CalVer-only) on their own and do NOT individually generate a full semantic minor release or changelog entry.
      - **Tier Ambiguity**: If the agent cannot confidently determine whether changes qualify for major, minor, or patch, it must present its analysis, recommend a version tier, and explicitly ask the user for confirmation before updating the changelog or tagging.
    - **Roll-Up Overview**: Each `CHANGELOG.md` entry must provide a high-level overview of ALL changes made across the codebase since the previous changelog entry. This means a SemVer release rolls up and synthesizes changes across multiple intermediate CalVer commits and routine patches merged to `main`.
    - Format each release entry with a semantic version header paired with its CalVer tag (e.g. `## [2.4.0] / [2026.11.1.1] - Headline Name (YYYY-MM-DD)`), a short descriptive headline, and categorized bulleted lists (`Added`, `Changed`, `Fixed`, `Security`).
    - **Deployer & Maintainer Audience Scope**: Write changelog entries strictly from the perspective of end users, stack deployers, and maintainers. Highlight user-facing operational impacts, service additions/removals, routing changes, and breaking contracts. Avoid internal minutiae such as lines-of-code metrics, internal test assertion counts/pass rates, internal script control-flow constructs (e.g., `case` statements, pipeline refactors), or internal file paths unless directly touched by deployers.
    - Aggregate changes into curated, meaningful bullet points; omit negligible micro-commits, syntax tweaks, or documentation typos (see [`feature-completion`](../skills/feature-completion/SKILL.md)).

## 5. Testing and Quality Assurance Standards

- **Smoke and Regression Test Suite (`homelab.sh test`)**:
  - The repository maintains an automated, fast smoke test suite in `homelab.sh test` verifying container runtimes/health, direct admin ports, client-impersonated virtual host routing over reverse proxies (with SSL and HTTP status codes), and internal container interconnections (DNS, database sockets, API health, VPN port sync).
- **Mandatory Tests with Feature Changes**:
  - Always add corresponding automated test checks to `homelab.sh test` whenever introducing a new stack, service, reverse proxy host, endpoint, or internal communication path. Feature changes are incomplete without accompanying test coverage (see [`test-authoring`](../skills/test-authoring/SKILL.md)).
- **Integrity of Existing Tests**:
  - Respect existing tests. Never arbitrarily loosen assertions, remove checks, or rewrite test logic simply to make a failing test pass. If a test fails, investigate and fix the underlying configuration, networking, or service defect. Any intentional modification to an existing test assertion must be explicitly justified by an intentional architectural or requirement change.
- **Regression and Bug Fix Testing**:
  - Whenever a bug or regression is identified (such as routing failures, disallowed host headers, missing SSL certificates, or VPN port desynchronization), write a reproducing test case in `homelab.sh test` before or alongside applying the fix to verify remediation and permanently prevent regressions.
- **RAID Transition Test Avoidance**:
  - While a storage array transition or rebuild (such as the active RAID 5 rebuild/reshape on the host) is underway, avoid running tests, full test suites, or heavy container probes unless strictly necessary. High disk I/O latency causes container executions to stall or hit timeouts.

## 6. On-Demand Skills and Operational Playbooks

Procedural workflows, multi-step runbooks, and diagnostic algorithms are modularized as on-demand skills under `.agents/skills/<name>/SKILL.md` (and accessible via `.skills/<name>/SKILL.md`). In accordance with progressive disclosure, consult and execute the appropriate skill when performing operational tasks:

- **Homelab Onboarding & Direction Setting**: Execute the interactive orientation, service selection matrix, hardware/provider adaptation, and initial scaffolding runbook in [`start-homelab`](../skills/start-homelab/SKILL.md).
- **Feature Initiation & Design Review**: Follow the mainline sync, branch checkout (`feature/<name>`), architectural plan drafting, opinionated "grill-me" critique cycle, and plan commit procedure in [`feature-initiation`](../skills/feature-initiation/SKILL.md).
- **Plan Execution & Review Gate**: After plan execution and committing implementation changes to the feature branch, STOP and present the current state, runtime verifications, and test results to the user. ALWAYS wait and obtain explicit user input and approval before initiating feature completion.
- **Feature Completion & Release Lifecycle**: Only after explicit user approval, follow the sequential test verification, stop-on-failure, systematic documentation audit, roll-up release note drafting, merge, and dual-tagging procedure in [`feature-completion`](../skills/feature-completion/SKILL.md).
- **Stack Creation & Maintenance**: Follow directory conventions, canonical key order, variable assertions (`${VAR}`), and privilege rules in [`stack-authoring`](../skills/stack-authoring/SKILL.md).
- **Volume Backups & Disaster Recovery**: Follow zero-downtime database staging, snapshot management, and granular or full-volume disaster recovery workflows in [`backup-recovery`](../skills/backup-recovery/SKILL.md).
- **Networking & Routing Diagnostics**: Follow the diagnostic flowchart for reverse proxy virtual hosts, container DNS resolution, WireGuard/PIA killswitches, and Tailscale routing in [`network-diagnostics`](../skills/network-diagnostics/SKILL.md).
- **Automated Test Authoring**: Follow suite categorization, client impersonation patterns, and regression test conventions in [`test-authoring`](../skills/test-authoring/SKILL.md).
