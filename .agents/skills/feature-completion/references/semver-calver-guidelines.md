# SemVer and CalVer Release Guidelines

## Versioning Model Overview

The homelab orchestrator repository tracks changes using a hybrid dual-versioning scheme:
1. **Semantic Versioning (SemVer)**: `vMAJOR.MINOR.PATCH` (e.g. `v2.4.0`)
   - Identifies functional and architectural milestones.
   - Used for primary software releases, major capability introductions, and breaking changes.
2. **Calendar Versioning (CalVer)**: `YYYY.M.D.N` (e.g. `2026.11.1.1`)
   - Identifies chronological snapshots, routine backups, and configuration commits on `main`.

---

## Release Versioning Tiers

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

## Roll-Up Release Synthesis

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
