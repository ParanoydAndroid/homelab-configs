# CalVer and SemVer Release Guidelines (Agile Trunk Governance)

## 1. Versioning Model Overview

The homelab orchestrator repository tracks releases using a **CalVer-First** versioning model tailored for **Agile Trunk-Based Development**:

1. **Calendar Versioning (CalVer) — Feature Releases Only**: `YYYY.M.D[.N]` (e.g. `2026.11.6`, `2026.11.6.1`)
   - Applied strictly where at least a SemVer minor would previously have been used (feature completions and substantive capabilities).
   - Every completed feature branch merging to `main` receives an annotated CalVer tag and a curated `CHANGELOG.md` entry.
   - **No Tagging of Routine Patches**: Routine bug fixes, configuration adjustments, micro-patches, and documentation updates do NOT receive CalVer tags; they remain untagged commits on `main`.
   - Adheres to PEP 440 format: no leading zeros in month or day (`2026.11.6`, not `2026.11.06`). The `.N` sequence suffix is used for monotonic same-day release increments after the base tag.
2. **Semantic Versioning (SemVer) — Breaking Major Releases Only**: `vMAJOR.0.0` (e.g. `v4.0.0`)
   - Strictly reserved for major breaking architectural shifts, schema resets, breaking interface contracts, or updates requiring manual data/configuration migration.
   - Always prefixed with a lower-case `v` (e.g. `v4.0.0`).
   - **Retired**: SemVer minor (`vX.Y.0`) and patch (`vX.Y.Z`) tags are retired in favor of direct CalVer tracking.

---

## 2. Tagging Cadence in Agile Trunk Development

In agile trunk-based git, all feature branches merge directly into `main`. The `main` branch is always in a releasable state.

| Release Tier | Trigger Event | Cadence | Tagging Action | Changelog Requirement |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1: Feature Release** | Completed feature branch merging to `main` with verified capabilities. | Continuous / as completed | **CalVer**: `YYYY.M.D[.N]` | **Mandatory**: Curated roll-up milestone entry. |
| **Tier 2: Breaking Major** | Breaking changes, major architectural redesigns, manual migration required. | Infrequent / deliberate | **Dual Tag**: `vX.0.0` + `YYYY.M.D[.N]` | **Mandatory**: Migration guide & breaking notices. |
| **Tier 3: Routine Patch / Hotfix** | Standalone bug fixes, configuration tweaks, or doc updates directly on `main`. | As needed | **Untagged Commit** | **Deferred**: Rolled up into next Tier 1 feature release. |

### Cadence Invariants:
1. **Never Tag Intermediate Commits on Feature Branches**: Feature branch commits remain untagged. Tags are applied *only* on the merge commit on `main`.
2. **Never Tag Routine Patches**: Routine fixes, micro-commits, and documentation adjustments on `main` remain untagged commits. CalVer tags are reserved strictly for feature releases and breaking major milestones.
3. **Annotated Tags Only**: All tags must be created as annotated tags (`git tag -a <tag> -m "<message>"`) to preserve tagger identity, timestamp, and message for `git describe`.

---

## 3. Pre-Tagging Proposal Checklist & Approval Gate

The agent must **NEVER** apply a tag autonomously. Before executing any tagging operation on `main`, the agent must present the **Tagging Proposal Packet** to the user and wait for explicit confirmation:

```text
[ Pre-Tagging Proposal Packet ]
1. Test Verification:
   All regression suites passed (./manage.sh test all) with 0 failures.

2. Commit Roll-Up Analysis:
   List of commits on main since last release tag:
   - <commit_sha> <commit_message>

3. Tagging Recommendation:
   "Recommend CalVer 2026.11.6 (Tier 1: Feature Release)
    Reason: Adds model-tiered subagents and completion audit without breaking contracts. SemVer major not required."

4. Changelog Preview:
   Drafted CHANGELOG.md entry categorizing Added, Changed, Fixed, and Security items.
```

**Human Decision Gate**:
The user must explicitly approve or adjust the proposed version and changelog before the agent commits `CHANGELOG.md`, merges to `main`, and tags.

---

## 4. Release Versioning Tiers

When completing work on a branch, classify the change into one of the following tiers:

1. **Feature Release (Tier 1 — CalVer)**:
   - Substantive feature completions (e.g., adding a new service stack, integrating a dedicated Tailscale VPN bridge, implementing Restic backup subsystem, or modernizing agentic harnesses).
   - Tag: `YYYY.M.D[.N]`.
   - Requires curated `CHANGELOG.md` entry.

2. **Breaking Major Release (Tier 2 — SemVer Major + CalVer)**:
   - Breaking changes to repository structure, core networking architecture (e.g. replacing reverse proxy or subnet schemes), or incompatible CLI automation redesigns requiring manual operator migration.
   - Tag: Dual tag `vX.0.0` + `YYYY.M.D[.N]`.
   - Requires explicit user confirmation, migration guide, and curated `CHANGELOG.md` entry.

3. **Routine Patch / Hotfix (Tier 3 — Untagged Commit)**:
   - Routine bug fixes, minor documentation corrections, micro-patches, and syntax tweaks merged directly to `main`.
   - Tag: **None** (untagged commit).
   - Changelog notes deferred and rolled up into the next feature release.

---

## 5. Roll-Up Release Synthesis

Each `CHANGELOG.md` entry must provide a high-level overview of **ALL** changes across the codebase since the previous changelog entry.

Because multiple routine patches, bug fixes, and untagged commits may accumulate on `main` between feature releases:
- The changelog entry for a new release must roll up and synthesize those intermediate commits alongside the new feature.
- Aggregate changes into curated, meaningful bullet points categorized under `Added`, `Changed`, `Fixed`, and `Security`.
- **Deployer-Focused Brevity & Scope**:
  - Write entries strictly from the perspective of stack deployers and maintainers.
  - Highlight user-facing operational impacts, breaking contracts, service additions/removals, port/URL routing updates, and security postures.
  - Avoid purely internal development minutiae: omit lines-of-code metrics, internal test assertion counts/pass rates, internal script control-flow constructs (`case` statements, regex pipelines, helper functions), and internal issue tracker IDs.
- Omit trivial commits, typos, or negligible micro-edits.

---

## 6. Changelog Entry Format Examples

### Standard Feature Release (CalVer)
```markdown
## [2026.11.6] - Dedicated Background Worker & Event Queue (2026-11-06)

### Added
- Dedicated event queue consumer service with automated backoff retry and dead-letter queue.
- Automated health check probes and contract assertion test suite.

### Changed
- Standardized environment variable missing parameter assertions across all service manifests.

### Fixed
- Remediated memory leak in websocket event dispatcher during client reconnection storms.

### Security
- Enforced non-root execution container profiles with dropped capabilities (`cap_drop: [ALL]`).
```

### Breaking Major Release (SemVer Major + CalVer)
```markdown
## [v4.0.0] / [2026.12.1] - Orchestrator Architecture Overhaul (2026-12-01)

### Breaking Changes & Migration Notice
- Replaced Docker Compose v1 with Compose v2 plugin specification; manual host update required (`manage.sh setup`).
- Migrated default bridge subnet from `192.168.255.0/24` to `172.28.0.0/16`.

### Added
- Native health check telemetry and service discovery endpoints.
```
