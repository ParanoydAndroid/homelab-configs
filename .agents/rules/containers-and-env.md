---
trigger: glob
globs:
  - "*compose*.yml"
  - "*compose*.yaml"
  - "Dockerfile*"
  - ".env*"
---

# Containers and Environment Configuration Standards

This rule applies automatically whenever creating, modifying, or reviewing container manifests, Docker Compose files, Dockerfiles, and environment templates.

## 1. Dockge Directory Compatibility
- Strictly preserve the Dockge-compatible directory structure at the repository root: one directory per stack containing `compose.yml` and an optional `.env` file.
- Do not create non-stack directories at the repository root. Keep agent metadata and project artifacts inside `.agents/` and tracked service configurations inside `.configs/<service>/`.
- Store Dockge's own `compose.yml` in `.configs/dockge/compose.yml` and deploy it to `${DOCKGE_DIR}/compose.yml` (one level above `stacks/`) so Dockge does not manage or restart itself.

## 2. Environment Variable Assertion Syntax
- Docker Compose manifests must enforce required variables using strict assertion syntax:
  ```yaml
  ${VARIABLE:?See env.example for default.}
  ```
- **Never use inline fallback defaults** in Compose files (e.g. avoid `${VAR:-default}`); all runtime defaults belong centrally in `.env.example` templates.
- Fixed stack invariants (such as static log levels, internal ports, or fixed subnets) must be directly inlined as static values in `compose.yml` rather than exposed as unnecessary environment variables.
- Intentionally optional secrets (such as one-time `TS_AUTHKEY`) must use `${TS_AUTHKEY:-}` so subsequent restarts succeed after the auth key is consumed.
- **Script Boundary**: Required-variable assertion syntax (`:?`) applies strictly to Docker Compose files (`compose.yml`). Shell scripts must use standard parameter expansion (`${VAR}`) without `:?`.

## 3. Two-Tier Environment Variable Architecture
1. **Root `.env.example`**: Defines global host paths, user/group IDs, timezone, and LAN network parameters (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_*`, `NPM_IPV4_ADDRESS`, `TAILSCALE_IPV4_ADDRESS`, `BACKUP_RESTIC_REPO`, `BACKUP_RETENTION_DAYS`) with populated defaults. Automation syncs these global values into each `<stack>/.env`.
2. **Per-Stack `<stack>/.env.example`**: Defines true external secrets (`VPN_USER`, `VPN_PASS`), application cryptographic secrets (`SECRET_KEY`), per-stack runtime selections (`PIA_REGION`), and service API keys with blank defaults (`KEY=`).

## 4. Least-Privilege Execution Model
- Standardize non-root execution via `${PUID}` and `${PGID}` (UID/GID `1000:100`).
- Use Compose `user: "${PUID}:${PGID}"` only for images (like `jellyfin/jellyfin`) that do not read `PUID`/`PGID` environment variables; do NOT set Compose `user:` on images (`lscr.io/linuxserver/*`, `vabene1111/recipes`) whose entrypoints require root startup before dropping privileges.
- Drop all unnecessary capabilities (`cap_drop: [ALL]`).
- Enable security restrictions (`security_opt: [no-new-privileges:true]`).
- Mount media and shared resources read-only (`:ro`) whenever write access is not strictly required.

## 5. Host Volume Standardization
- Standardize persistent service data and configuration paths under `${DOCKER_DATA_DIR}/<service>/data/...` and shared media under `${MEDIA_DIR}` (avoid redundant `/data/data` nesting).
- Maintain `1000:100` ownership on service data directories, explicitly excluding containers with fixed internal UIDs (`postgres` UID `70`) or root privileges (`nginx`, `homepage`, `dockge`).

## 6. Canonical Service Key Ordering
Maintain consistent 2-space YAML key ordering across container service blocks:
```yaml
image: ...
container_name: ...
hostname: ...
user: ...
restart: ...
privileged: ...
cap_add: ...
cap_drop: ...
security_opt: ...
sysctls: ...
devices: ...
group_add: ...
mac_address: ...
environment: ...
volumes: ...
ports: ...
networks: ...
logging: ...
labels: ...
```
