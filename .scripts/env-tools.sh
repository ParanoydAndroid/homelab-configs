#!/usr/bin/env bash
# ==============================================================================
# Script Name: .scripts/env-tools.sh
# Description:
#   Two-tier environment variable initialization, global propagation, and
#   secret validation for the homelab Compose stacks and Dockge orchestrator.
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Function: init_and_sync_env
# Description:
#   Idempotently initializes and synchronizes the two-tier .env configuration:
#     1. Initializes root '.env' from '.env.example' if missing, substituting '${USER}'.
#     2. Exports root environment variables into the current shell process.
#     3. Initializes Dockge's '${DOCKGE_DIR}/.env'.
#     4. Initializes per-stack '.env' files from their '.env.example' templates.
#     5. Propagates referenced global variables from root '.env' into stack '.env's.
#     6. Emits warnings for any blank required secret keys in stack '.env' files.
#     7. Synchronizes root globals into '${DOCKGE_DIR}/.env'.
# Globals Read:
#   REPO_DIR, TARGET_USER, TARGET_GROUP, STACKS, DOCKGE_DIR
# ------------------------------------------------------------------------------
init_and_sync_env() {
  local root_env="${REPO_DIR}/.env"
  local root_example="${REPO_DIR}/.env.example"

  # Step 1: Initialize root .env from .env.example if missing
  if [[ ! -f "${root_env}" ]]; then
    log_info "Initializing ${root_env} from ${root_example} (user: ${TARGET_USER})"
    sed "s|\${USER}|${TARGET_USER}|g" "${root_example}" > "${root_env}"
  else
    local tmp_env
    tmp_env="$(mktemp)"
    sed "s|\${USER}|${TARGET_USER}|g" "${root_env}" > "${tmp_env}"
    cat "${tmp_env}" > "${root_env}"
    rm -f "${tmp_env}"
  fi
  chown "${TARGET_USER}:${TARGET_GROUP}" "${root_env}" 2>/dev/null || true

  # Step 2: Export all variables defined in root .env
  set -a
  # shellcheck disable=SC1090
  source "${root_env}"
  set +a

  # Step 3: Initialize Dockge's own .env file
  mkdir -p "${DOCKGE_DIR}"
  local dockge_env="${DOCKGE_DIR}/.env"
  if [[ ! -f "${dockge_env}" && -f "${REPO_DIR}/.configs/dockge/.env.example" ]]; then
    sed "s|\${USER}|${TARGET_USER}|g" "${REPO_DIR}/.configs/dockge/.env.example" > "${dockge_env}"
  fi

  # Step 4: Initialize and sync each stack's .env file
  local stack target_env stack_example stack_compose
  for stack in "${STACKS[@]}"; do
    [[ -d "${REPO_DIR}/${stack}" ]] || continue
    target_env="${REPO_DIR}/${stack}/.env"
    stack_example="${REPO_DIR}/${stack}/.env.example"
    stack_compose="${REPO_DIR}/${stack}/compose.yml"

    if [[ ! -f "${target_env}" ]]; then
      if [[ -f "${stack_example}" ]]; then
        sed "s|\${USER}|${TARGET_USER}|g" "${stack_example}" > "${target_env}"
      else
        touch "${target_env}"
      fi
    fi

    # Propagate variables from root .env if referenced in compose.yml or declared in .env.example
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
      [[ -z "${key}" || "${key}" =~ ^[[:space:]]*# ]] && continue
      local is_needed=0
      if [[ -f "${stack_compose}" ]] && grep -qE "(\\\$|\\\$\{)${key}[:}]?" "${stack_compose}" 2>/dev/null; then
        is_needed=1
      elif [[ -f "${stack_example}" ]] && grep -qE "^[[:space:]]*${key}=" "${stack_example}" 2>/dev/null; then
        is_needed=1
      fi
      if [[ "${is_needed}" -eq 1 ]]; then
        upsert_env_var "${target_env}" "${key}" "${val}"
      fi
    done < "${root_env}"

    chown "${TARGET_USER}:${TARGET_GROUP}" "${target_env}" 2>/dev/null || true

    # Step 5: Validate required per-stack secret keys and auto-generate cryptographic tokens
    if [[ -f "${stack_example}" ]]; then
      while IFS='=' read -r req_key _ || [[ -n "${req_key}" ]]; do
        [[ -z "${req_key}" || "${req_key}" =~ ^[[:space:]]*# ]] && continue
        local cur_val
        cur_val="$(get_env_var "${target_env}" "${req_key}")"
        if [[ -z "${cur_val}" ]]; then
          if [[ "${req_key}" == "SECRET_KEY" ]]; then
            local gen_key
            gen_key="$(LC_ALL=C tr -dc 'A-Za-z0-9!#%&*+,-./:;<=>?@^_~' < /dev/urandom | head -c 50 || true)"
            upsert_env_var "${target_env}" "SECRET_KEY" "${gen_key}"
            log_info "Auto-generated random cryptographic SECRET_KEY for ${stack}."
          elif [[ "${req_key}" == "TS_AUTHKEY" || "${req_key}" == "EXIT_NODE_TS_AUTHKEY" ]]; then
            # Optional pre-auth key; intentionally allowed to remain blank after initial registration
            :
          else
            log_warn "Required variable '${req_key}' in ${stack}/.env is currently blank."
          fi
        fi
      done < "${stack_example}"
    fi
  done

  # Step 6: Sync root globals into Dockge's .env
  while IFS='=' read -r key val || [[ -n "${key}" ]]; do
    [[ -z "${key}" || "${key}" =~ ^[[:space:]]*# ]] && continue
    upsert_env_var "${dockge_env}" "${key}" "${val}"
  done < "${root_env}"
  chown "${TARGET_USER}:${TARGET_GROUP}" "${dockge_env}" 2>/dev/null || true
}
