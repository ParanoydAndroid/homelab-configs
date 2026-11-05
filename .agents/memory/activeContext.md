# Active Context

## Current Focus
Completing Phase 3 & 4 of Agentic Harness Modernization: Host systemd service unit update and full decommissioning of `homelab.sh`.

## Recent Changes
- Scaffolded 3-file memory bank (`activeContext.md`, `systemPatterns.md`, `progress.md`).
- Authored subagent specifications (`architect-critic.md`, `code-auditor.md`).
- Authored modular rules (`containers-and-env.md`, `shell-scripting.md`).
- Authored canonical root `AGENTS.md` and established ecosystem symlinks (`agent.md`, `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.agents/rules/project-conventions.md`).
- Migrated `.tests/` to `.harness/` with new `conventions` suite (10 assertions).
- Decommissioned `.tests` compatibility symlink; confirmed zero dead links across repository.
- Authored unified `manage.sh` operational CLI supporting all homelab lifecycle subcommands.
- Authored GitHub Actions CI workflow (`.github/workflows/ci.yml`).
- Installed git hooks protecting `main` branch (`manage.sh hook install`).
- Verified 100% test pass (79/79 assertions passed across all 7 suites).
- Conducted exhaustive documentation and link audit across all 43 markdown files (129 links verified, 0 broken).
- Updated tracked systemd units in `.configs/systemd/` to reference `manage.sh`.

## Active Decisions
- All repository documentation and scripts now exclusively reference `manage.sh` and `.harness/`.
- Decommissioning `homelab.sh` requires updating `/etc/systemd/system/` units on the host (`homelab-startup.service` and `homelab-backup.service`).

## Immediate Next Steps
1. Request user to deploy tracked systemd units to `/etc/systemd/system/` via sudo and reload daemon.
2. Remove `homelab.sh` to complete full decommissioning.
3. Commit implementation changes to `feature/agentic-harness-update`.
4. Present current state to user for approval at the mandatory review gate before feature completion.
