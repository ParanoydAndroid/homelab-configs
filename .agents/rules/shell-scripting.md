---
trigger: glob
globs:
  - "*.sh"
  - ".harness/*.sh"
  - ".scripts/*.sh"
---

# Shell Scripting Standards and Conventions

This rule applies automatically whenever authoring, modifying, or reviewing Bash shell scripts.

## 1. Strict Error Handling & Shell Standards
- Use `#!/usr/bin/env bash` as the interpreter directive.
- Enforce strict error boundaries at the top of every script:
  ```bash
  set -euo pipefail
  ```
- Always quote variable expansions (`"${VAR}"`) to prevent word splitting and globbing defects.
- Avoid invalid scoping outside functions; check preconditions explicitly before mutating state.
- Resolve active users and paths dynamically (`${SUDO_USER:-${USER}}`, `id -u`, `id -g`, `pwd`) rather than hardcoding personal user accounts.
- Script boundary parameter expansion: Shell scripts use standard expansion (`${VAR}`) without required Compose assertion syntax (`:?`).

## 2. Mandatory Documentation Standards
- **Script Header**: Every script must begin with a comprehensive header documenting purpose, architecture/context, usage syntax, subcommands, preconditions, and operational behavior.
- **Function Docstrings**: Every function must be preceded by a longform docstring defining:
  - `Description`: Clear explanation of purpose and mechanism.
  - `Arguments`: `$1`, `$2`, etc.
  - `Environment/Globals`: Variables read or mutated.
  - `Side Effects`: Filesystem, network, or process mutations.
  - `Return / Exit Codes`: Explicit return values.
- **Inline Comments**: Include explanatory inline comments above complex pipelines, `awk`/`sed`/`grep` expressions, `sqlite3` statements, parameter expansions, and non-obvious control-flow logic explaining both *what* the code does and *why*.

## 3. Universal Idempotency Preconditions
- Setup and teardown scripts must verify current state before mutating. Running repeatedly from any starting state must safely converge on the desired target state.
- Creating directories must use `mkdir -p`.
- Symlinking must use `ln -sf` or `ln -sfn`.
- When deploying configuration files to target host paths, detect whether existing target files have been modified since the last update and prompt or handle cleanly.
