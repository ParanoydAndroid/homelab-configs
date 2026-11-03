---
name: feature-completion
description: >-
  Standardized workflow for completing a feature branch: verify full test suite,
  stop on failure, update CHANGELOG.md, purge temporary planning artifacts, commit,
  push, merge to main, and apply dual SemVer/CalVer tags.
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
./homelab.sh test all
```
* **Assertion**: All test suites (containers, direct, routing, interconnect, security, backup) must PASS (or explicitly documented skips).
* **CRITICAL STOP-ON-FAILURE**: If any test fails:
  1. STOP immediately.
  2. Do NOT touch CHANGELOG.md.
  3. Do NOT delete planning documents.
  4. Do NOT commit, merge, or tag.
  5. Report the exact test failure and logs to the user and wait for instructions.

### Step 2: Update Changelog (SemVer Minor/Major Releases)
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

### Step 3: Clean Up Temporary Planning Artifacts
Remove ephemeral planning and design documents while preserving persistent architectural artifacts:
```bash
rm -f .agents/artifacts/plan_*.md
```
* Note: Keep persistent architectural specifications (such as `.agents/artifacts/architecture.md`) intact.

### Step 4: Final Feature Branch Commit and Push
Stage all modified files (including `compose.yml`, `CHANGELOG.md`, and rules):
```bash
git add -A
git commit -m "feat(<feature-name>): complete <feature-name> implementation and release notes"
git push origin <feature-branch>
```

### Step 5: Merge into Main and Apply Dual Release Tags
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
