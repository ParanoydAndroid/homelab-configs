---
name: stack-authoring
description: >-
  Procedural recipe and validation checklist for authoring, modifying, or retiring
  Dockge Compose stacks in the homelab environment. Use when creating new services,
  editing compose.yml files, adjusting environment variables, or auditing stack permissions.
---

# Stack Authoring Runbook

This skill guides the creation and modification of Dockge-compatible Docker Compose stacks in accordance with homelab architectural conventions.

## Prerequisites
- Reference [Docker Compose and Stack Standards Reference](./references/compose-spec.md) for canonical key order and privilege rules.
- Ensure the repository working tree is clean or on a feature branch.

---

## Authoring Procedure

### Step 1: Directory Setup
1. Create a root-level directory for the stack:
   ```bash
   mkdir -p <stack-name>
   ```
2. Verify the directory name is lowercase, alphanumeric, and uses hyphens if needed.
3. If creating an orchestrator or untracked service config, place it in `.configs/<service>/` instead of root.

### Step 2: Compose File Construction (`compose.yml`)
1. Create `<stack-name>/compose.yml` (never `docker-compose.yml`).
2. Omit the deprecated `version:` and top-level `name:` properties.
3. Apply the canonical service key ordering:
   - `image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `cap_drop`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `ports`, `networks`, `logging`, `labels`.
4. Enforce mandatory parameter expansion assertion syntax on every variable:
   ```yaml
   ${VARIABLE}
   ```
5. Ensure backend containers connect to the external `homelab` network:
   ```yaml
   networks:
     homelab:
       external: true
   ```
6. Expose host ports only for UDP broadcast discovery (`jellyfin`) or emergency fallback. Comment out standard HTTP/HTTPS host ports.

### Step 3: Environment Variable Configuration
1. Create `<stack-name>/.env.example`:
   - List all stack-specific secrets (`*_API_KEY=`, `VPN_PASS=`) with blank defaults.
   - Do NOT include root-level globals (`DOCKER_DATA_DIR`, `PUID`, `PGID`, `TZ`) unless overriding.
2. Synchronize environment files using the project CLI:
   ```bash
   ./homelab.sh setup
   ```
   * Or sync `.env` files directly: `source .scripts/env-tools.sh && init_and_sync_env`.

### Step 4: Host Volume and Permission Provisioning
1. Ensure persistent data paths adhere to:
   `${DOCKER_DATA_DIR}/<service>/data/...`
2. Shared media paths must mount to:
   `${MEDIA_DIR}/<category>` (mount `:ro` if write access is not required).
3. If the container runs as non-root (`PUID:PGID`), ensure data directory ownership:
   ```bash
   sudo chown -R 1000:100 "${DOCKER_DATA_DIR}/<service>/data"
   ```
   *(Exclude containers with fixed internal UIDs like `postgres` UID 70).*

### Step 5: Verification & Testing
1. Validate compose syntax:
   ```bash
   docker compose -f <stack-name>/compose.yml config
   ```
2. Start the stack:
   ```bash
   docker compose -f <stack-name>/compose.yml up -d
   ```
3. Verify container health status:
   ```bash
   docker inspect --format='{{.State.Health.Status}}' <container-name>
   ```
4. Author automated smoke tests in `.tests/suites/` (see `test-authoring` skill).
