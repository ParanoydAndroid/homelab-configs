# Project Progress & Milestones

## Completed Capabilities
- [x] Baseline homelab infrastructure operational: 20 active container services managed via Dockge.
- [x] Dual-homed Caddy reverse proxy on `external_npm` macvlan (`192.168.0.4`) with automated TLS (`*.kamaka.tech`).
- [x] Zero-downtime Restic backup automation with online database staging and retention pruning.
- [x] Automated smoke, routing, interconnect, direct admin, and security test suites.
- [x] Dual-tagging release model (SemVer + CalVer) and changelog governance.
- [x] Modern multi-agent harness aligned with `ParanoydAndroid/coding-agent`.
  - [x] Architectural plan drafted, executed, and archived.
  - [x] Session memory bank established (`.agents/memory/`).
  - [x] Invocable subagents authored and tiered (`principal-reviewer` on `pro`, `grep-worker` and `diff-worker` on `flash_lite`).
  - [x] Modular scoped rules authored (`.agents/rules/`).
  - [x] Canonical root `AGENTS.md` and ecosystem symlinks converged.
  - [x] Test harness migrated to `.harness/` with new `conventions` suite.
  - [x] Unified `manage.sh` master entrypoint implemented.
  - [x] GitHub Actions CI workflow authored (`.github/workflows/ci.yml`).
  - [x] Git hooks guarding `main` installed and hardened with `test all`.
  - [x] Legacy `.tests/` directory and symlink decommissioned.
  - [x] Comprehensive repository-wide documentation and link audit completed (129/129 valid).
  - [x] Tracked and host systemd unit files updated to `manage.sh`.
  - [x] Legacy `homelab.sh` fully decommissioned.
  - [x] User review gate approved for minor release `3.5.0` / `2026.11.6`.

## Verification Status
- Automated test suite: 79/79 passing (`./manage.sh test all`).
- Codebase & infrastructure audit: Clean, zero issues (`./manage.sh audit`).
- Markdown link audit: 129/129 links valid across 43 files.
- Active containers: 20/20 running and healthy.
- Active release: `3.5.0` / `2026.11.6`.

## Recent Fixes
- [x] Corrected ANSI C-quoting escape sequences (`$'\033[...m'`) in `manage.sh` and `.harness/lib/common.sh` so help heredocs render colors across terminals (including mobile Termux/SSH).
- [x] Added root privilege check to `manage.sh snapshots` to properly inform non-root users when repository keys require elevated permissions.

## Known Issues / Backlog
- None.
