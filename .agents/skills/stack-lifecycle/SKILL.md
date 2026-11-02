---
name: stack-lifecycle
description: >-
  Standardized operational runbook for provisioning a new service stack or cleanly
  decommissioning an existing one across all 6 homelab architectural touchpoints:
  Compose specification, environment templates, reverse proxy virtual hosts, dashboard
  widgets, backup policies, and automated smoke test assertions.
---

# Service Stack Lifecycle Runbook (Addition & Decommissioning)

This skill coordinates adding a new service or decommissioning an existing service across the 6 architectural touchpoints of the homelab platform.

```
       1. Compose Stack (<stack>/compose.yml)
             |
       2. Environment (.env.example & .env)
             |
       3. Reverse Proxy (NPM Virtual Host & SSL)
             |
       4. Dashboard (.configs/homepage/services.yaml)
             |
       5. Backup Engine (.scripts/backup.sh & Restic)
             |
       6. Automated Tests (.tests/suites/*)
```

---

## Procedure A: Adding a New Service Stack

### Touchpoint 1: Compose Specification (`<stack>/compose.yml`)
1. Create a root directory named `<stack-name>/` (lowercase, alphanumeric, hyphens only).
2. Author `<stack-name>/compose.yml` adhering to:
   - Canonical key order (`image`, `container_name`, `hostname`, `user`, `restart`, `privileged`, `cap_add`, `cap_drop`, `security_opt`, `sysctls`, `devices`, `group_add`, `mac_address`, `environment`, `volumes`, `tmpfs`, `ports`, `networks`, `logging`, `labels`).
   - Non-root UID/GID (`PUID:PGID` or `user: "${PUID}:${PGID}"`).
   - Attached to external `homelab` bridge network.
   - Host ports commented out unless non-HTTP or emergency direct access.
   - Standard logging capped at `10m` / `max-file: 3`.

### Touchpoint 2: Environment Templates (`<stack>/.env.example`)
1. Create `<stack-name>/.env.example`:
   - List only stack-specific secrets (`*_API_KEY=`, `*_SECRET=`, `*_PASSWORD=`) with blank defaults.
   - Do NOT include root globals (`DOCKER_DATA_DIR`, `PUID`, `PGID`, `TZ`).
2. Run `./homelab.sh setup` to generate `<stack-name>/.env` and sync globals.

### Touchpoint 3: Reverse Proxy Host (Nginx Proxy Manager)
1. Add an internal proxy host in NPM:
   - Domain: `<service>.turing.home` (and optional external `<service>.kamaka.tech`).
   - Scheme: `http`, Forward Hostname: `<container_name>`, Forward Port: `<port>`.
   - Enable: **Block Common Exploits**, **Websockets Support**.
   - SSL: Select local wildcard certificate, enable **Force SSL** and **HTTP/2**.

### Touchpoint 4: Homepage Dashboard
1. Add service widget labels in `<stack>/compose.yml` or edit `.configs/homepage/services.yaml`:
   ```yaml
   labels:
     - homepage.group=Utilities
     - homepage.name=MyService
     - homepage.icon=myservice
     - homepage.href=https://myservice.turing.home
     - homepage.description=Service description
   ```

### Touchpoint 5: Persistent Volume & Backup Policy
1. Ensure data path follows `${DOCKER_DATA_DIR}/<service>/data/...`.
2. Apply `1000:100` ownership if non-root:
   ```bash
   sudo chown -R 1000:100 "${DOCKER_DATA_DIR}/<service>/data"
   ```
3. If database-backed, add online staging dump in `.scripts/backup.sh`.

### Touchpoint 6: Automated Smoke Tests
1. Add container assertion to `.tests/suites/test_containers.sh`:
   ```bash
   test_docker_up_<service>() {
     _assert_container_running "<container_name>" "<stack_name>"
   }
   ```
2. Add routing assertion to `.tests/suites/test_routing.sh`:
   ```bash
   test_vhost_<service>_internal() {
     _curl_vhost "<service>.turing.home" "/" "^200$" "<stack_name>"
   }
   ```
3. Run `./homelab.sh test all` to verify complete green pass.

---

## Procedure B: Decommissioning / Retiring a Service Stack

1. **Stop & Down Stack**:
   ```bash
   docker compose -f <stack-name>/compose.yml down -v
   ```
2. **Remove Proxy Hosts**:
   In NPM, delete proxy hosts associated with `<service>.turing.home`.
3. **Remove Dashboard Widget**:
   Remove entry from `.configs/homepage/services.yaml` if manually configured.
4. **Archive or Prune Persistent Data**:
   - Create final Restic snapshot before removal:
     ```bash
     ./homelab.sh backup --tag retire-<stack-name>
     ```
   - Delete `${DOCKER_DATA_DIR}/<service>`.
5. **Clean Up Tests**:
   Remove or comment assertions in `.tests/suites/`. (Dynamic discovery will also automatically skip tests if stack directory is removed or `.disabled` is present).
6. **Remove Stack Directory**:
   ```bash
   rm -rf <stack-name>/
   ```
7. **Verify Mainline Health**:
   ```bash
   ./homelab.sh test all
   ```
