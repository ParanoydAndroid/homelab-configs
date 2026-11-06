---
name: feature-initiation
description: >-
  Standardized workflow for starting new features: synchronize main with origin,
  create a feature branch (feature/<name>), scaffold an initial architectural plan,
  execute an interactive grill-me design review to eliminate bloat and maintain golden-path
  conventions, and commit the refined plan artifact to the feature branch.
---

# Feature Initiation and Design Review Runbook

This skill automates the disciplined kickoff of a new feature branch, including mainline synchronization, branch isolation, architectural drafting, and an adversarial design review ("grill-me") before code implementation begins.

## Prerequisites
- Working directory is clean (`git status` reports no untracked or uncommitted changes).
- Reference [Grill-Me Persona & Critique Framework](./references/grill-me-persona.md) for review posture and questions.

---

## Execution Procedure

### Step 1: Mainline Synchronization
Always branch from the latest state of `origin/main` to avoid drift:
```bash
git checkout main
git pull origin main
```

### Step 2: Branch Creation
Create and switch to a descriptive feature branch adhering to the `feature/<name>` convention:
```bash
git checkout -b feature/<feature-name>
```

### Step 3: Plan Prompt & Initial Architectural Draft
1. Prompt the user for requirements or feature scope if not already provided.
2. Author an initial architectural plan document at `.agents/artifacts/plan_<feature-name>.md`.
3. Ensure the initial draft outlines:
   - Proposed stack/service architecture and container images.
   - Network bindings (`homelab` bridge, reverse proxy routing, host ports).
   - Volume persistence paths (`${DOCKER_DATA_DIR}/<service>/data`).
   - Required environment variables and `.env.example` keys.
   - Automated test checks needed in `.harness/suites/`.
4. Update `.agents/memory/activeContext.md` to document the active feature focus, decisions, and planned steps.

### Step 4: Interactive "Grill-Me" Review Cycle
Adopt the persona of an **experienced, opinionated homelab infrastructure engineer**:
- **Core Stance**: Ruthlessly simplify, eliminate waste, reduce custom scripts, enforce declarative golden-path patterns, and protect maintainability.
- **Review Strategy**:
  1. Question assumptions: Can built-in image capabilities or Docker Compose primitives replace custom scripts?
  2. Critique deviations from the golden path (e.g., unnecessary host ports, bespoke networks, nested data folders).
  3. Identify failure modes (e.g., container restarts, VPN leaks, backup corruption, restore downtime).
  4. Propose concrete, simpler alternatives for every flagged issue.
- Present targeted questions and alternative proposals to the user. Do not artificially limit question count or prematurely conclude the critique; iterate across multiple question rounds as long as relevant, substantive ambiguities, trade-offs, or unaddressed failure modes exist. Do not begin implementation until all design trade-offs are settled.

### Step 5: Iterative Plan Convergence and Commit
1. Refine `.agents/artifacts/plan_<feature-name>.md` based on user feedback and resolved architectural decisions.
2. Commit the approved plan artifact directly to the feature branch so design history is tracked in git:
   ```bash
   git add .agents/artifacts/plan_<feature-name>.md
   git commit -m "docs(plan): add architectural plan for <feature-name>"
   ```

### Step 6: Plan Execution, Intermediate Commit, and User Review Checkpoint (MANDATORY)
1. Execute the implementation steps according to the approved plan using relevant implementation skills (`stack-authoring`, `test-authoring`, `backup-recovery`).
2. Verify runtime health and execute automated tests (`./manage.sh test all`).
3. Commit all implementation changes to the feature branch:
   ```bash
   git add -A
   git commit -m "feat(<feature-name>): implement <feature-name> changes"
   ```
4. **CRITICAL MANDATORY PAUSE**: Stop immediately. Do NOT run `feature-completion`.
5. **Report & Solicit User Input**: Present a concise operational summary of the current state, runtime behavior, and test verification results to the user.
6. **Wait for User Input**: Explicitly ask the user to inspect, test, and approve the state before proceeding. NEVER proceed autonomously to release notes, changelog updates, artifact cleanup, mainline merge, or tagging until the user provides explicit confirmation.
