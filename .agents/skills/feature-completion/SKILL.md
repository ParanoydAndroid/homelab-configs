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

### Step 2: Systematic Documentation and Runbook Audit
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

### Step 3: Update Changelog (SemVer Minor/Major Releases)
Review [SemVer and CalVer Guidelines](./references/semver-calver-guidelines.md) for version tier determination, roll-up synthesis, and format rules.
* **Tagging & Changelog Scope**:
  - Only features automatically receive `semver.minor` or `semver.major` bumps.
  - All `semver.minor` and `semver.major` changes require a curated `CHANGELOG.md` entry.
  - Critical or major security remediations may also warrant a `semver.minor` release.
  - Routine security updates, bugfixes, and patches are typically `semver.patch` or CalVer-only and do not generate a standalone semantic minor version or changelog entry.
  - If the agent cannot confidently determine whether the changes qualify for major, minor, or patch, it must present its analysis, recommend a version tier, and explicitly ask the user for confirmation before proceeding.
* **Roll-Up Overview**:
  - The `CHANGELOG.md` entry must provide a high-level overview of ALL changes across the codebase since the previous changelog entry.
  - The entry rolls up and synthesizes intermediate CalVer commits, hotfixes, refactors, and the completed feature into a unified milestone summary.
* Calculate next minor SemVer (e.g. via `bump_semver minor` from `.scripts/backup.sh`) and today's CalVer (`date +%Y.%-m.%-d`).
* Prepend the new release section to `CHANGELOG.md` directly below the top header:
  ```markdown
  ## [<Next-SemVer>] / [<CalVer>] - <Feature Title> (YYYY-MM-DD)

  ### Added
  - <Bullet points describing user-facing additions>

  ### Changed
  - <Bullet points describing architectural or convention modifications>

  ### Fixed
  - <Bullet points describing remediated issues>

  ### Security
  - <Bullet points describing security hardening or access control updates>
  ```

### Step 4: Clean Up Temporary Planning Artifacts
Remove ephemeral planning and design documents while preserving persistent architectural artifacts:
```bash
rm -f .agents/artifacts/plan_*.md
```
* Note: Keep persistent architectural specifications (such as `.agents/artifacts/architecture.md`) intact.

### Step 5: Final Feature Branch Commit and Push
Stage all modified files (including `compose.yml`, documentation, `CHANGELOG.md`, and rules):
```bash
git add -A
git commit -m "feat(<feature-name>): complete <feature-name> implementation and release notes"
git push origin <feature-branch>
```

### Step 6: Merge into Main and Apply Dual Release Tags
Switch to `main`, synchronize with remote, merge the feature branch, apply tags, and push:
```bash
git checkout main
git pull origin main
git merge <feature-branch>

# Determine versions
NEXT_SEMVER="<Calculated-SemVer>"
CURRENT_CALVER="<Calculated-CalVer>"

# Tag release
git tag -a "${NEXT_SEMVER}" -m "Release ${NEXT_SEMVER} / ${CURRENT_CALVER}"
git tag -a "${CURRENT_CALVER}" -m "Release ${CURRENT_CALVER}"

# Push mainline and tags
git push origin main --tags

# Remove local feature branch
git branch -d <feature-branch>
```
