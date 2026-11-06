# Active Context

## Current Focus
Completed release `3.5.0` / `2026.11.6` integrating model-tiered subagents, interactive completion audit, and agile trunk harness governance. Ready for upcoming tasks.

## Recent Changes
- Completed release `3.5.0` / `2026.11.6`.
- Adopted model-tiered subagents (`principal-reviewer` on `pro`, `grep-worker` and `diff-worker` on `flash_lite`) replacing `architect-critic` and `code-auditor`.
- Updated `feature-completion` to incorporate mandatory audit and 4-pillar review.
- Adopted unconstrained substantive inquiry in `feature-initiation` skill and reference docs.
- Formalized Agile Trunk governance and Tagging Proposal Packet in `semver-calver-guidelines.md`.
- Expanded git hooks in `manage.sh` to enforce `test all` on `main`.
- Fixed ANSI C-quoting color escape codes in `manage.sh` and `.harness/lib/common.sh`.
- Added root privilege enforcement guard to `manage.sh snapshots`.

## Active Decisions
- Keep monitored downloads clean via API manual imports when safety regex or release title mismatches prevent automatic *arr import.

## Immediate Next Steps
- Await further user instruction.
