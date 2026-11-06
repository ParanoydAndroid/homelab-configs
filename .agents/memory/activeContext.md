# Active Context

## Current Focus
Resolved media acquisition & status discrepancies in Seerr:
1. Terminator (1, 2, 3) availability synchronization resolved.
2. 3 warning downloads resolved (imported QI XL S23E06, S23E08 into Sonarr, and South Park: Bigger, Longer & Uncut into Radarr; synced to Seerr).

## Recent Changes
- Diagnosed and resolved Dragon Ball Z Kai metadata/season conflict between Sonarr (TheTVDB 2-season schema) and Jellyfin (TMDb 7-season schema).
- Batch-mapped and imported all 45 orphaned files from `Season 6` and `Season 7` into Sonarr via API `ManualImport` (44 files to `S02E18`–`S02E61`, 1 file to Specials `S00E08`), achieving 100% completion in Sonarr.
- Executed `RenameFiles` in Sonarr to organize and standardize all files into `/media/shows/Dragon Ball Z Kai/Season 2/` and `/Specials/`. Purged orphaned duplicate `Season 5`, `Season 6`, and `Season 7` folders.
- Enabled TheTVDB metadata provider across Series, Seasons, and Episodes in Jellyfin's `Shows` library options, re-identified Dragon Ball Kai with TVDB `88031`, and triggered metadata refresh (Jellyfin now reflects the 2-season structure: S1=98, S2=61, Specials=1).
- Fixed ANSI C-quoting color escape codes in `manage.sh` and `.harness/lib/common.sh`.
- Added root privilege enforcement guard to `manage.sh snapshots`.

## Active Decisions
- Keep monitored downloads clean via API manual imports when safety regex or release title mismatches prevent automatic *arr import.

## Immediate Next Steps
- Await further user instruction.
