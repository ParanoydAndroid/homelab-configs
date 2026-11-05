# Architectural Plan: Agentic Harness Modernization & Alignment

## 1. Problem Statement & Scope

### 1.1 Objective
Modernize and restructure the agentic infrastructure of `homelab-configs` by adapting and adopting the universal multi-agent architecture established in the user's `coding-agent` framework (`ParanoydAndroid/coding-agent`).

### 1.2 Current State Deficiencies
1. **Monolithic Rules**: All behavioral instructions, Docker Compose standards, networking rules, backup procedures, and shell guidelines are combined in a single file (`.agents/rules/project-conventions.md`).
2. **Inverted Entrypoint Symlink**: Currently, root `AGENTS.md` is a symlink pointing into `.agents/rules/project-conventions.md`. The target standard dictates that root `AGENTS.md` is the canonical file, with multi-agent ecosystem symlinks (`agent.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, and `.agents/rules/project-conventions.md`) pointing to it.
3. **Missing Memory Bank**: No persistent session state store (`.agents/memory/`) exists to maintain `activeContext.md`, `systemPatterns.md`, and `progress.md` across context boundaries.
4. **Missing Invocable Subagents**: Dedicated prompt contracts (`.agents/subagents/architect-critic.md` and `code-auditor.md`) are absent.
5. **Divergent Entrypoint and Harness Architecture**:
   - `coding-agent` uses `./manage.sh` (`setup`, `test`, `audit`, `hook`, `help`) and `.harness/test-runner.sh`.
   - `homelab-configs` uses `./homelab.sh` and `.tests/run.sh`.
6. **No Mainline Protection Hooks or CI**: Missing git hooks guarding `main` branch merges/commits and missing GitHub Actions CI workflow (`.github/workflows/ci.yml`).

### 1.3 Out of Scope
- Modifying live container stack workloads or altering Docker Compose service definitions (e.g. `jellyfin`, `caddy`, `servarr`, `arr-scripts`).
- Changing active networking subnets, IP assignments, or Caddy virtual host configurations.
- Changing persistent volume locations or modifying Restic backup repositories.

---

## 2. Target Architecture & Component Mapping

### 2.1 File & Symlink Topology (Final Target Post-Decommissioning)
```
/opt/brandon/dockge/stacks/
├── AGENTS.md                          # Canonical root agent instruction file
├── agent.md -> AGENTS.md              # Symlink
├── CLAUDE.md -> AGENTS.md             # Symlink
├── GEMINI.md -> AGENTS.md             # Symlink
├── .cursorrules -> AGENTS.md          # Symlink
├── .skills -> .agents/skills          # Symlink
├── manage.sh                          # Universal operational entrypoint (executable)
├── .harness/
│   ├── test-runner.sh                 # Master test harness (TAP/xUnit summary)
│   ├── lib/common.sh                  # Assertion library and ingress helpers
│   └── suites/                        # Test suites (conventions + homelab suites)
│       ├── test_conventions.sh        # Harness structural invariants
│       ├── test_containers.sh         # Docker container runtimes & health
│       ├── test_direct_admin.sh       # Direct administrative ports
│       ├── test_routing.sh            # Reverse proxy virtual hosts
│       ├── test_interconnect.sh       # DNS, database sockets, VPN port sync
│       ├── test_negative_security.sh  # Macvlan isolation, headers, auth
│       └── test_backup.sh             # Restic snapshots & automation
├── .github/
│   └── workflows/
│       └── ci.yml                     # Continuous integration workflow
├── .agents/
│   ├── memory/
│   │   ├── activeContext.md           # Active task focus and immediate next steps
│   │   ├── systemPatterns.md          # Architectural invariants and patterns
│   │   └── progress.md                # Completed milestones and test status
│   ├── subagents/
│   │   ├── architect-critic.md        # Principal Architect & Systems Critic ("Grill-Me")
│   │   └── code-auditor.md            # Compliance & Drift Detection Auditor
│   ├── rules/
│   │   ├── project-conventions.md -> ../../AGENTS.md # Symlink
│   │   ├── shell-scripting.md         # Glob-scoped (*.sh) bash conventions
│   │   └── containers-and-env.md      # Glob-scoped (*compose*.yml, .env*) standards
│   ├── artifacts/                     # Versioned architecture specs & plans
│   │   ├── architecture.md
│   │   └── README.md
│   └── skills/                        # Operational skills runbooks
│       ├── backup-recovery/
│       ├── disaster-recovery-drill/
│       ├── feature-completion/
│       ├── feature-initiation/
│       ├── homelab-audit/
│       ├── network-diagnostics/
│       ├── stack-authoring/
│       ├── stack-lifecycle/
│       ├── start-homelab/
│       └── test-authoring/
└── .scripts/                          # Host & operational subroutines
    ├── common.sh
    ├── env-tools.sh
    ├── system.sh
    └── backup.sh
```

### 2.2 Preserving Dockge Compatibility
- **Inviolable Invariant**: Dockge scans the repository root directory and indexes any subfolder as a Compose stack.
- Non-stack directories at root must be hidden (prefixed with `.` like `.agents/`, `.harness/`, `.scripts/`, `.configs/`, `.github/`).
- Convenience symlinks at the repository root (`AGENTS.md`, `agent.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.skills`, `manage.sh`) are files/symlinks, NOT directories, so Dockge ignores them completely.

---

## 3. Detailed Guidance Restructuring Matrix

| Topic / Policy | Original Location | Target Location in New Harness | Notes / Audit Changes |
| :--- | :--- | :--- | :--- |
| **Agent Persona & Tone** | `project-conventions.md` §1 | `AGENTS.md` §1 | Retain homelab infra engineering focus; add negative constraints (*No Phantom Refactoring*, *Preserve Documentation Integrity*, *Strict Dependency Gate*, *Tool & Token Economy*, *No Grandiose Prose*). |
| **Mandatory User Review Gate** | `project-conventions.md` §1 | `AGENTS.md` §1 | Retained verbatim. |
| **Client File Delivery** | `project-conventions.md` §1 | `AGENTS.md` §1 | Stage in `${DOCKER_DATA_DIR}/caddy/downloads/<file>`, serve via `https://download.kamaka.tech/<file>`. Retained. |
| **Ad-Hoc Script Pre-Execution** | `project-conventions.md` §1 | `AGENTS.md` §1 | Operational overview requirement. Retained. |
| **Memory Bank Discipline** | *New from coding-agent* | `AGENTS.md` §1, `.agents/memory/` | Enforce Session Start read, Task Initiation update, Task Completion sync. |
| **Project Orientation Order** | `project-conventions.md` §2 | `AGENTS.md` §2 | Updated to include `.agents/memory/`, `.agents/rules/`, and `start-homelab`. |
| **Dockge Compatibility** | `project-conventions.md` §3 | `AGENTS.md` §3 & `containers-and-env.md` | Strict root folder discipline, `.configs/dockge/compose.yml` deployment. |
| **Declarative Automation** | `project-conventions.md` §3 | `AGENTS.md` §3 & `manage.sh` | Idempotent state convergence, UGREEN NAS OS fixes. |
| **Network & Port Exposure** | `project-conventions.md` §3 | `AGENTS.md` §3 & `containers-and-env.md` | `homelab` bridge, Caddy on `external_npm` macvlan `192.168.0.4`, closed host ports. |
| **Two-Tier .env Model** | `project-conventions.md` §3 | `AGENTS.md` §3 & `containers-and-env.md` | Root `.env.example` syncs globals; per-stack `.env.example` has blank defaults. |
| **`${VAR:?}` Assertion Syntax** | `project-conventions.md` §3 | `.agents/rules/containers-and-env.md` | Required variables must assert `:?`. No inline defaults in Compose. Shell scripts use `${VAR}`. |
| **Host Volume Standardization** | `project-conventions.md` §3 | `AGENTS.md` §3 | `${DOCKER_DATA_DIR}/<service>/data/...`, Restic backups, 1000:100 ownership. |
| **TRaSH Guides Adherence** | `project-conventions.md` §3 | `AGENTS.md` §3 | Media management baseline, NVMe scratch, Btrfs No-CoW flags, anti-starvation queues. |
| **Docker Compose Conventions** | `project-conventions.md` §4 | `.agents/rules/containers-and-env.md` | Canonical key ordering, omit `version`/`name`, non-root execution (`user: "${PUID}:${PGID}"` vs `PUID`/`PGID` env). |
| **Shell Scripting Conventions** | `project-conventions.md` §4 | `.agents/rules/shell-scripting.md` | `set -euo pipefail`, header blocks, function docstrings, explanatory inline comments, idempotency. |
| **Documentation & Changelog** | `project-conventions.md` §4 | `AGENTS.md` §4 | Roll-up overview, SemVer minor/major gating, deployer/maintainer perspective, factual modesty. |
| **Testing Standards & Harness** | `project-conventions.md` §5 | `AGENTS.md` §5 & `.harness/` | Mandatory tests with features, regression testing, RAID transition avoidance, fast smoke execution. |
| **Skill Sitemaps** | `project-conventions.md` §6 | `AGENTS.md` §6 | Full catalog of on-demand homelab skills. |

---

## 4. Phased Execution Roadmap

### Phase 1: Core Harness Scaffolding & Initial Unification
1. **Memory Bank Scaffolding**: Create `.agents/memory/{activeContext.md, systemPatterns.md, progress.md}`.
2. **Subagents Scaffolding**: Create `.agents/subagents/{architect-critic.md, code-auditor.md}`.
3. **Modular Rules Authoring**:
   - Create `.agents/rules/containers-and-env.md` with Docker Compose, assertion syntax, and least-privilege standards.
   - Create `.agents/rules/shell-scripting.md` with Bash standards, header/docstring requirements, and idempotency rules.
4. **Canonical Entrypoint Authoring**:
   - Write canonical `AGENTS.md` at repository root consolidating modern persona, memory discipline, negative constraints, homelab principles, and skill sitemap.
   - Re-link `.agents/rules/project-conventions.md -> ../../AGENTS.md`.
   - Create root ecosystem symlinks: `agent.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`.
5. **Test Harness Convergence (`.harness/`)**:
   - Migrate `.tests/` contents to `.harness/`.
   - Scaffold `.harness/suites/test_conventions.sh` asserting harness structure, symlinks, memory bank population, and secrets hygiene.
   - Implement `.harness/test-runner.sh` supporting `conventions` and all existing homelab suites (`containers`, `direct`, `routing`, `interconnect`, `security`, `backup`).
   - Create temporary backwards-compatibility symlink: `.tests -> .harness`.
6. **Master CLI Authoring (`manage.sh`)**:
   - Author unified `manage.sh` implementing `setup`, `startup`, `backup`, `snapshots`, `restore`, `test`, `audit`, `hook`, `help`.
   - Audit includes both file hygiene (permissions, symlinks, env skew) and homelab drift checks.
   - Create temporary backwards-compatibility symlink: `homelab.sh -> manage.sh`.
7. **CI Workflow Authoring**:
   - Create `.github/workflows/ci.yml` executing `manage.sh test conventions` and `manage.sh audit`.
8. **Git Hook Installation**:
   - Install main-guarding hooks via `./manage.sh hook install`.

### Phase 2: Functional Verification of Phase 1
1. Run `./manage.sh audit` and ensure 0 issues detected.
2. Run `./manage.sh test conventions` and verify all structural assertions pass.
3. Run `./manage.sh test all` and verify all homelab runtime, direct admin, routing, interconnect, and security suites pass.

### Phase 3: Host System Services Migration
1. Inspect host systemd services referencing `homelab.sh` (e.g. `/etc/systemd/system/homelab-startup.service` or `/etc/systemd/system/homelab-backup.timer`).
2. Update unit files to reference `/opt/brandon/dockge/stacks/manage.sh startup` (or relevant subcommands).
3. Reload systemd daemon (`systemctl daemon-reload`) and verify unit file status.

### Phase 4: Full Decommissioning of Legacy Artifacts & Symlinks
1. Audit the repository for any remaining references to `homelab.sh` or `.tests/`.
2. Remove temporary backward-compatibility symlink `homelab.sh`.
3. Remove temporary backward-compatibility symlink `.tests`.
4. Re-run `./manage.sh test conventions` and `./manage.sh audit` to confirm clean operation without legacy shims.

### Phase 5: Comprehensive Documentation & Link Audit
1. Audit all files across the repository:
   - `README.md`
   - `.docs/*.md`
   - `.agents/skills/**/*.md`
   - `.agents/artifacts/*.md`
   - Script headers and docstrings (`manage.sh`, `.harness/**/*.sh`, `.scripts/*.sh`)
2. Verify:
   - All file paths and Markdown links resolve to real files (zero dead links).
   - All CLI invocation examples use `./manage.sh` instead of `homelab.sh`.
   - All test suite references use `.harness/` instead of `.tests/`.
   - Terminology, parameters, and paths are completely current.

### Phase 6: Mandatory User Review Gate
1. Present full verification results, test output, and diff summary to the user.
2. Await explicit user approval before proceeding to release completion or merging.
