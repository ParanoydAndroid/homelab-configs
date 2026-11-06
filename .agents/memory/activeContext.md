# Active Context

## Current Focus
Assimilating upstream agentic harness improvements from `ParanoydAndroid/coding-agent` (release `2026.11.6.1` and intermediate refinements):
1. Model-tiered subagents (`principal-reviewer` on `pro`, `grep-worker` and `diff-worker` on `flash_lite`).
2. Interactive architect code audit step in `feature-completion` runbook.
3. Golden Path & Happy Path priority and grounded tone alignment across conventions.
4. Conventions test suite update to assert the new tiered subagent files.
5. Unconstrained "Grill-Me" inquiry in feature initiation (removing artificial question caps).
6. Pre-Tagging Proposal Packet & Approval Gate in SemVer/CalVer release guidelines.
7. Pre-push and pre-commit hook scope expansion to run `./manage.sh test all` before touching `main`.

## Recent Changes
- Branch `feature/harness-subagent-tiering` checked out from `main`.
- Adopted model-tiered subagents (`principal-reviewer`, `grep-worker`, `diff-worker`) replacing `architect-critic` and `code-auditor`.
- Updated `feature-completion` to incorporate mandatory audit and 4-pillar review.
- Adopted unconstrained substantive inquiry in `feature-initiation` skill and reference docs.
- Formalized Agile Trunk governance and Tagging Proposal Packet in `semver-calver-guidelines.md`.
- Expanded git hooks in `manage.sh` to enforce `test all` on `main`.
- Fixed ANSI C-quoting color escape codes in `manage.sh` and `.harness/lib/common.sh`.
- Added root privilege enforcement guard to `manage.sh snapshots`.

## Active Decisions
- Keep monitored downloads clean via API manual imports when safety regex or release title mismatches prevent automatic *arr import.

## Immediate Next Steps
- Commit intermediate refinements to `feature/harness-subagent-tiering`.
- Run audit and full regression test suite.
- Present summary to user for review before feature completion.
