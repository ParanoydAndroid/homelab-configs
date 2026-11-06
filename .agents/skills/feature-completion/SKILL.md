---
name: feature-completion
description: >-
  Standardized workflow for completing a feature branch: verify full test suite,
  stop on failure, execute systematic documentation and runbook audit, update CHANGELOG.md,
  purge temporary planning artifacts, commit, push, merge to main, and apply dual SemVer/CalVer tags.
---

# Feature Completion Runbook

This skill automates the safe, verified graduation of a feature branch into `main`.

## Prerequisites
- Currently on an active feature branch (`git branch --show-current` != `main`).
- Plan execution and intermediate implementation changes have been committed to the feature branch.
- **MANDATORY USER SIGN-OFF**: The agent has paused, presented the implementation state and test results to the user, and received explicit user approval to proceed with feature completion, changelog drafting, artifact cleanup, and merging. Never auto-trigger this skill without user confirmation.
- Working tree has all feature changes staged or ready to commit.

## Execution Procedure

### Step 1: Run Full Regression and Smoke Test Suite
Execute the entire test suite against the live environment:
```bash
./manage.sh test all
```
* **Assertion**: All test suites (containers, direct, routing, interconnect, security, backup) must PASS (or explicitly documented skips).
* **CRITICAL STOP-ON-FAILURE**: If any test fails:
  1. STOP immediately.
  2. Do NOT touch CHANGELOG.md.
  3. Do NOT delete planning documents.
  4. Do NOT commit, merge, or tag.
  5. Report the exact test failure and logs to the user and wait for instructions.

### Step 2: Interactive Code & Architecture Audit (`principal-reviewer`)
Before proceeding to documentation and release notes, conduct an interactive code audit using the `principal-reviewer` persona (`Model: "pro"`):

1. **Automated Baseline Audit**:
   Execute the baseline audit command to verify mechanical hygiene:
   ```bash
   ./manage.sh audit
   ```
   * Ensure 0 world-writable files, 0 broken symlinks, valid git index execution modes (`100755` for scripts), compliant container host ports, and full environment template alignment.

2. **Branch Diff Inspection**:
   Inspect the full implementation diff relative to `main`:
   ```bash
   git diff main...HEAD
   ```

3. **Architectural Evaluation Across 4 Pillars**:
   The reviewer evaluates the concrete changes against the core design priorities:
   - **Golden Path & Mechanical Integrity**: Did fragile wrappers, redundant utility functions, or undocumented workarounds sneak into the code? Can native platform primitives, standard libraries, or framework features replace custom logic?
   - **Declarative State & Idempotency**: Are configurations centrally declared in `.env.example` with strict parameter expansion assertions (`${VAR:?error}`)? Does the system converge cleanly and idempotently via `./manage.sh setup`?
   - **Failure Modes & Defensiveness**: Are errors handled defensively without silent suppression? Are existing automated tests respected and preserved? Are bug fixes accompanied by reproducing regression tests?
   - **Least Privilege & Boundary Security**: Are permissions strictly least-privilege (secrets at `600`, scripts at `755`)? Are service identities non-root and credentials excluded from git history, logs, and artifacts?

4. **Interactive Engagement**:
   - The reviewer presents its findings, concrete trade-offs, and proposed simplifications to the user.
   - If architectural concerns, anti-patterns, or drift are identified, address and remediate them before proceeding.
   - Do not proceed to documentation or release steps until user alignment is settled.

### Step 3: Systematic Documentation and Runbook Audit
Before writing release notes or committing, conduct a comprehensive audit across all documentation, runbooks, and skills to ensure they accurately reflect the feature's changes:

1. **Branch Diff Inspection**:
   Inspect all modified files on the feature branch relative to `main`:
   ```bash
   git diff --stat main...HEAD
   ```
   Identify every touched service, network configuration, port mapping, environment variable, or volume mount.

2. **Core Operational Documentation (`README.md`, `.docs/`)**:
   - **Service Catalog & Ports**: If services, container names, exposed ports, internal URLs, or external routes were added, modified, or retired, update the catalog tables in `README.md` and `.docs/service-catalog.md`.
   - **Network Architecture & Topology**: If networks, subnets, IP assignments, or ingress/egress flows were altered, update `README.md` Section 1 (including the Mermaid topology diagram) and `.docs/routing-topology.md`.
   - **Environment Variables**: If `.env.example` templates were modified, ensure corresponding additions/removals are documented in `.docs/env-reference.md`.

3. **Operational Skills and Runbooks (`.agents/skills/`)**:
   - Review skills related to the modified components (e.g., `stack-lifecycle`, `network-diagnostics`, `backup-recovery`, `stack-authoring`, `start-homelab`).
   - Audit for stale terminology or legacy patterns: Search for deprecated container names, retired reverse proxy platforms, legacy domains, or outdated code snippets:
     ```bash
     git grep -i "<deprecated-term>" .agents/skills/
     ```
   - Verify that all skill execution runbooks and code block snippets accurately describe active declarative patterns.

4. **Architecture Specifications (`.agents/artifacts/architecture.md`)**:
   - Verify that `.agents/artifacts/architecture.md` aligns with current architectural invariants, container relationships, and storage mappings.

5. **Style and Brevity Verification**:
   - Ensure all updated documentation adheres to the project-wide documentation conventions: value brevity, align detail to audience/scope, eliminate redundant fine details, and omit internal development minutiae.

6. **Memory Bank Synchronization (`.agents/memory/`)**:
   - Synchronize `activeContext.md` by clearing completed feature focus, updating active patterns, and noting upcoming tasks.
   - Synchronize `progress.md` by recording completed capabilities, updating the automated test count, and noting release tags. Never leave finished milestones marked pending.

### Step 4: Update Changelog (Feature Releases & Breaking Changes)
Review [CalVer and SemVer Release Guidelines](./references/semver-calver-guidelines.md) for version tier determination, roll-up synthesis, and format rules.
* **Tagging & Changelog Scope**:
  - All completed feature branches qualify for a CalVer release (`YYYY.M.D[.N]`) and require a curated `CHANGELOG.md` entry.
  - SemVer major bumps (`vX.0.0`) are reserved exclusively for breaking changes, major architecture redesigns, or migrations. SemVer minor and patch tags are retired.
  - Routine security updates, bugfixes, micro-patches, and documentation adjustments merged directly on `main` remain untagged commits without standalone changelog entries (their notes roll up into the next feature release).
* **Roll-Up Overview**:
  - The `CHANGELOG.md` entry must provide a high-level overview of ALL changes across the codebase since the previous changelog entry.
  - The entry rolls up and synthesizes intermediate untagged commits, hotfixes, refactors, and the completed feature into a unified milestone summary.
* Calculate today's CalVer tag (`date +%Y.%-m.%-d`).
* Prepend the new release section to `CHANGELOG.md` directly below the top header:
  ```markdown
  ## [<CalVer>] - <Feature Title> (YYYY-MM-DD)

  ### Added
  - <Bullet points describing user-facing additions>

  ### Changed
  - <Bullet points describing architectural or convention modifications>

  ### Fixed
  - <Bullet points describing remediated issues>

  ### Security
  - <Bullet points describing security hardening or access control updates>
  ```
  *(If breaking major release, format header as `## [<Next-SemVer-Major>] / [<CalVer>] - <Feature Title> (YYYY-MM-DD)`)*

### Step 5: Pre-Tagging Proposal Packet & Mandatory Human Approval Gate
Before committing the changelog or initiating merge/tagging operations, the agent MUST present the **Pre-Tagging Proposal Packet** to the user and pause:

```text
[ Pre-Tagging Proposal Packet ]
1. Test Verification:
   All regression suites passed (./manage.sh test all) with 0 failures.
   Audit passed (./manage.sh audit) with 0 issues.

2. Commit Roll-Up Analysis:
   List of commits on main since last release tag:
   - <commit_sha> <commit_message>

3. Tagging Recommendation:
   "Recommend CalVer <YYYY.M.D[.N]> (Tier 1: Feature Release)
    Reason: <Rationale; note whether breaking major SemVer is required>."

4. Changelog Preview:
   <Preview of drafted CHANGELOG.md entry>
```

* **CRITICAL PAUSE GATE**: Do NOT proceed to Step 6, Step 7, or Step 8 until the user explicitly reviews and approves the proposal packet.

### Step 6: Clean Up Temporary Planning Artifacts
Remove ephemeral planning and design documents while preserving persistent architectural artifacts:
```bash
rm -f .agents/artifacts/plan_*.md
```
* Note: Keep persistent architectural specifications (such as `.agents/artifacts/architecture.md`) intact.

### Step 7: Final Feature Branch Commit and Push
Stage all modified files (including `compose.yml`, documentation, `CHANGELOG.md`, and rules):
```bash
git add -A
git commit -m "feat(<feature-name>): complete <feature-name> implementation and release notes"
git push origin <feature-branch>
```

### Step 8: Merge into Main and Apply Release Tags
Switch to `main`, synchronize with remote, merge the feature branch with `--no-ff`, apply tags, and push:
```bash
git checkout main
git pull origin main
git merge --no-ff <feature-branch> -m "merge: merge branch '<feature-branch>' into main"

# Determine CalVer tag (and SemVer major if breaking)
CALVER_TAG="$(bash -c 'source .scripts/common.sh && resolve_chronological_tag')"

# Tag release (annotated tag)
git tag -a "${CALVER_TAG}" -m "Release ${CALVER_TAG}: <Headline>"

# If breaking major release:
# git tag -a "vX.0.0" -m "Release vX.0.0 / ${CALVER_TAG}: <Headline>"

# Push mainline and tags
git push origin main --tags

# Remove local feature branch
git branch -d <feature-branch>
```
