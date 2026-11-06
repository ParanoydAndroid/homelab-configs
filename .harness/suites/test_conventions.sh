#!/usr/bin/env bash
# ==============================================================================
# Suite: test_conventions
# Purpose: Verifies agent harness structural invariants, multi-agent entrypoints,
#          memory bank persistence, modular rules, and secrets hygiene.
# ==============================================================================
set -euo pipefail

# Sourced by test runner; REPO_DIR is set in test environment

test_conventions_entrypoint() {
  [[ -s "${REPO_DIR}/AGENTS.md" ]]
}

test_skills_symlink() {
  [[ -L "${REPO_DIR}/.skills" ]] && [[ -d "${REPO_DIR}/.skills" ]]
}

test_ecosystem_symlinks() {
  [[ -L "${REPO_DIR}/CLAUDE.md" && -e "${REPO_DIR}/CLAUDE.md" ]] && \
  [[ -L "${REPO_DIR}/GEMINI.md" && -e "${REPO_DIR}/GEMINI.md" ]] && \
  [[ -L "${REPO_DIR}/.cursorrules" && -e "${REPO_DIR}/.cursorrules" ]] && \
  [[ -L "${REPO_DIR}/agent.md" && -e "${REPO_DIR}/agent.md" ]] && \
  [[ -L "${REPO_DIR}/.agents/rules/project-conventions.md" && -e "${REPO_DIR}/.agents/rules/project-conventions.md" ]]
}

test_manage_executable() {
  [[ -x "${REPO_DIR}/manage.sh" ]]
}

test_env_example_presence() {
  [[ -s "${REPO_DIR}/.env.example" ]]
}

test_gitignore_secrets() {
  grep -q "\.env" "${REPO_DIR}/.gitignore"
}

test_subagents_presence() {
  [[ -s "${REPO_DIR}/.agents/subagents/principal-reviewer.md" ]] && \
  [[ -s "${REPO_DIR}/.agents/subagents/grep-worker.md" ]] && \
  [[ -s "${REPO_DIR}/.agents/subagents/diff-worker.md" ]]
}

test_memory_bank_presence() {
  [[ -s "${REPO_DIR}/.agents/memory/activeContext.md" ]] && \
  [[ -s "${REPO_DIR}/.agents/memory/systemPatterns.md" ]] && \
  [[ -s "${REPO_DIR}/.agents/memory/progress.md" ]]
}

test_modular_rules_presence() {
  [[ -s "${REPO_DIR}/.agents/rules/shell-scripting.md" ]] && \
  [[ -s "${REPO_DIR}/.agents/rules/containers-and-env.md" ]]
}

test_ci_workflow_presence() {
  [[ -s "${REPO_DIR}/.github/workflows/ci.yml" ]]
}

suite_conventions() {
  init_suite "Agentic Harness & Structural Invariants"
  run_test test_conventions_entrypoint "Canonical AGENTS.md entrypoint exists"
  run_test test_skills_symlink ".skills convenience symlink is available and resolves"
  run_test test_ecosystem_symlinks "Multi-agent ecosystem symlinks (agent.md, CLAUDE.md, GEMINI.md, .cursorrules) resolve"
  run_test test_manage_executable "manage.sh master entrypoint is executable"
  run_test test_env_example_presence "Root .env.example configuration template exists"
  run_test test_gitignore_secrets ".gitignore properly protects .env credentials"
  run_test test_subagents_presence ".agents/subagents/ prompt specifications exist"
  run_test test_memory_bank_presence ".agents/memory/ session memory bank exists and is populated"
  run_test test_modular_rules_presence ".agents/rules/ glob-scoped rules exist"
  run_test test_ci_workflow_presence ".github/workflows/ci.yml continuous integration workflow exists"
}
