# Active Context

## Current Focus
Completed release `2026.11.6` integrating model-tiered subagents, interactive completion audit, CalVer-first release governance, and hook automation.

## Recent Changes
- Completed release `2026.11.6`.
- Adopted model-tiered subagents (`principal-reviewer` on `pro`, `grep-worker` and `diff-worker` on `flash_lite`) replacing `architect-critic` and `code-auditor`.
- Transitioned repository versioning policy to CalVer-first (`YYYY.M.D[.N]`), retiring SemVer minor/patch and reserving SemVer major exclusively for breaking changes.
- Embedded mandatory Pre-Tagging Proposal Packet human gate into `feature-completion/SKILL.md`.
- Added `test_git_hooks_installed` assertion to `.harness/suites/test_conventions.sh` (80/80 tests passing).
- Added `HOMELAB_SKIP_HOOK_TESTS=1` bypass to `manage.sh` git hooks for storage array maintenance.
- Adopted unconstrained substantive inquiry in `feature-initiation` skill and reference docs.
- Fixed ANSI C-quoting color escape codes in `manage.sh` and `.harness/lib/common.sh`.
- Added root privilege enforcement guard to `manage.sh snapshots`.

## Active Decisions
- Primary release tag is CalVer (`YYYY.M.D[.N]`), applied strictly where at least a SemVer minor was previously used (feature completions). SemVer (`vX.0.0`) is strictly reserved for breaking major releases.
- Routine patches, bug fixes, micro-commits, and documentation edits remain untagged commits on `main`.
- Keep monitored downloads clean via API manual imports when safety regex or release title mismatches prevent automatic *arr import.

## Immediate Next Steps
- Await further user instruction.
