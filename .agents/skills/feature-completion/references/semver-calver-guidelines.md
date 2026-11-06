# SemVer and CalVer Release Guidelines (Agile Trunk Governance)

## 1. Versioning Model Overview

The homelab orchestrator repository tracks changes using a hybrid dual-versioning scheme tailored for **Agile Trunk-Based Development**:

1. **Semantic Versioning (SemVer)**: `vMAJOR.MINOR.PATCH` (e.g. `v3.5.0`)
   - Identifies functional and architectural milestones.
   - Always prefixed with a lower-case `v` to distinguish software releases from CalVer.
   - Used for primary capabilities, breaking changes, and public interface contracts.
2. **Calendar Versioning (CalVer)**: `YYYY.M.D.N` (e.g. `2026.11.6.1`)
   - Identifies chronological snapshots, routine backups, and configuration commits on `main`.
   - Adheres to PEP 440 format (no leading zeros in month/day, monotonic sequence revision `.N` for same-day releases).

---

## 2. Tagging Cadence in Agile Trunk Development

In agile trunk-based git, all feature branches merge directly into `main`. The `main` branch is always in a releasable state.

| Release Tier | Trigger Event | Cadence | Tagging Action | Changelog Requirement |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1: Semantic Minor** | Completed feature branch merging to `main` with new capabilities. | Several times per sprint / continuous | **Dual Tag**: `vX.Y.0` + `YYYY.M.D.N` | **Mandatory**: Curated roll-up milestone entry. |
| **Tier 2: Semantic Major** | Breaking contract changes, architectural redesigns, schema resets. | Infrequent / deliberate | **Dual Tag**: `vX.0.0` + `YYYY.M.D.N` | **Mandatory**: Migration guide & breaking notices. |
| **Tier 3: Trunk Patch / Hotfix** | Routine bug fixes, configuration tweaks, or doc updates. | As needed | **CalVer-Only**: `YYYY.M.D.N` | **Deferred**: Rolled up into next Tier 1 SemVer release. |

### Cadence Invariants:
1. **Never Tag Intermediate Commits on Feature Branches**: Feature branch commits remain untagged. Tags are applied *only* on the merge commit on `main`.
2. **Annotated Tags Only**: All tags must be created as annotated tags (`git tag -a <tag> -m "<message>"`) to preserve tagger identity, timestamp, and message for `git describe`.

---

## 3. Pre-Tagging Proposal Checklist & Approval Gate

The agent must **NEVER** apply a tag autonomously. Before executing any tagging operation on `main`, the agent must present the **Tagging Proposal Packet** to the user and wait for explicit confirmation:

```text
[ Pre-Tagging Proposal Packet ]
1. Test Verification:
   All regression suites passed (./manage.sh test all) with 0 failures.

2. Commit Roll-Up Analysis:
   List of commits on main since last SemVer tag:
   - <commit_sha> <commit_message>

3. Version Tier Recommendation:
   "Recommend semver-minor (v3.5.0) paired with CalVer 2026.11.6.1
    Reason: Adds new capability without breaking existing contracts."

4. Changelog Preview:
   Drafted CHANGELOG.md entry categorizing Added, Changed, Fixed, and Security items.
```

**Human Decision Gate**:
The user must explicitly approve or adjust the recommended version tier before the agent commits `CHANGELOG.md`, merges to `main`, and tags.

---

## 4. Release Versioning Tiers

When completing work on a branch, classify the change into one of the following tiers:

1. **Semantic Major (`semver-major`)**:
   - Breaking changes to repository structure, core networking architecture (e.g. replacing reverse proxy or subnet schemes), or incompatible CLI automation redesigns.
   - Requires user confirmation, full test suite pass, and curated `CHANGELOG.md` entry.

2. **Semantic Minor (`semver-minor`)**:
   - Substantive feature completions automatically qualify for a minor version bump (e.g., adding a new service stack, integrating a dedicated Tailscale VPN bridge, implementing Restic backup subsystem).
   - Critical or major security remediations that alter access models or introduce significant defense-in-depth layers.
   - Requires curated `CHANGELOG.md` entry.

3. **Semantic Patch / CalVer-Only (`semver-patch` / CalVer)**:
   - Routine bug fixes, minor documentation corrections, micro-patches, and syntax tweaks.
   - These do **NOT** generate standalone semantic minor bumps or individual changelog entries.
   - Merged to `main` under CalVer tracking.

4. **Tier Ambiguity**:
   - If the agent cannot confidently determine whether changes qualify for major, minor, or patch, it must present its analysis, recommend a version tier, and explicitly ask the user for confirmation before updating the changelog or tagging.

---

## 5. Roll-Up Release Synthesis

Each `CHANGELOG.md` entry must provide a high-level overview of **ALL** changes across the codebase since the previous changelog entry.

Because multiple routine patches, bug fixes, and CalVer commits may accumulate on `main` between minor feature releases:
- The changelog entry for a new SemVer release must roll up and synthesize those intermediate commits alongside the new feature.
- Aggregate changes into curated, meaningful bullet points categorized under `Added`, `Changed`, `Fixed`, and `Security`.
- **Deployer-Focused Brevity & Scope**:
  - Write entries strictly from the perspective of stack deployers and maintainers.
  - Highlight user-facing operational impacts, breaking contracts, service additions/removals, port/URL routing updates, and security postures.
  - Avoid purely internal development minutiae: omit lines-of-code metrics, internal test assertion counts/pass rates, internal script control-flow constructs (`case` statements, regex pipelines, helper functions), and internal issue tracker IDs.
- Omit trivial commits, typos, or negligible micro-edits.

---

## Changelog Entry Format Example

```markdown
## [2.4.0] / [2026.11.1.1] - Dedicated Tailscale PIA VPN Bridge (2026-11-01)

### Added
- Dedicated `vpn-bridge` stack pairing Tailscale and Gluetun PIA WireGuard into a unified exit node and subnet router.
- Automated health check assertions for subnet routing and NAT masquerade iptables rules.

### Changed
- Standardized Docker Compose missing variable assertions across all 12 stack definitions.
- Migrated default VPN DNS resolver to Quad9 (`9.9.9.9,149.112.112.112`) for improved privacy and malware blocking.

### Fixed
- Remediated Tailscale subnet routing loop caused by `100.64.0.0/10` in `LOCAL_NETWORK`.

### Security
- Hardened Tailscale TUN device access with explicit `cap_add: [NET_ADMIN]` and `cap_drop: [ALL]`.
```
