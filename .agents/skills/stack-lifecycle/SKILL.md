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
       3. Reverse Proxy (Caddy Docker Proxy Labels & Wildcard TLS)
             |
       4. Dashboard (.configs/homepage/services.yaml)
             |
       5. Backup Engine (.scripts/backup.sh & Restic)
             |
       6. Automated Tests (.harness/suites/*)
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
2. Run `./manage.sh setup` to generate `<stack-name>/.env` and sync globals.

### Touchpoint 3: Reverse Proxy Routing (Caddy Docker Proxy)
1. Add declarative Caddy labels to the service in `<stack-name>/compose.yml`:
   ```yaml
   labels:
     - caddy=<service>.kamaka.tech
     - caddy.reverse_proxy={{upstreams <port>}}
     - caddy.import=cloudflare_tls
   ```
2. For services requiring external access over Cloudflare Zero Trust (`*.kamakakai.com`):
   ```yaml
   labels:
     - caddy=<service>.kamaka.tech, <service>.kamakakai.com
     - caddy.reverse_proxy={{upstreams <port>}}
     - caddy.import=cloudflare_tls
   ```
   *Note*: When both internal and external hostnames share the same upstream, list them comma-separated so both inherit the `cloudflare_tls` security headers (HSTS, nosniff, SAMEORIGIN) and dotfile blocking. If distinct label blocks are required (e.g. to apply external-only endpoint filters), ensure every block imports `cloudflare_tls`:
   ```yaml
   labels:
     - caddy_0=<service>.kamaka.tech
     - caddy_0.reverse_proxy={{upstreams <port>}}
     - caddy_0.import=cloudflare_tls
     - caddy_1=<service>.kamakakai.com
     - caddy_1.reverse_proxy={{upstreams <port>}}
     - caddy_1.import=cloudflare_tls
   ```
3. Caddy Docker Proxy automatically discovers container labels over `/var/run/docker.sock` and requests/renews the Let's Encrypt wildcard certificate via Cloudflare DNS-01. No manual UI configuration or database updates required.

### Touchpoint 4: Homepage Dashboard
1. Add service widget labels in `<stack>/compose.yml` or edit `.configs/homepage/services.yaml`:
   ```yaml
   labels:
     - homepage.group=Utilities
     - homepage.name=MyService
     - homepage.icon=myservice
     - homepage.href=https://myservice.kamaka.tech
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
1. Add container assertion to `.harness/suites/test_containers.sh`:
   ```bash
   test_docker_up_<service>() {
     _assert_container_running "<container_name>" "<stack_name>"
   }
   ```
2. Add routing assertion to `.harness/suites/test_routing.sh`:
   ```bash
   test_vhost_<service>_internal() {
     _curl_vhost "<service>.kamaka.tech" "/" "^200$" "<stack_name>"
   }
   ```
3. Run `./manage.sh test all` to verify complete green pass.

---

## Procedure B: Decommissioning / Retiring a Service Stack

1. **Stop & Down Stack**:
   ```bash
   docker compose -f <stack-name>/compose.yml down -v
   ```
2. **Remove Proxy Hosts**:
   Remove Caddy proxy labels associated with `<service>.kamaka.tech`.
3. **Remove Dashboard Widget**:
   Remove entry from `.configs/homepage/services.yaml` if manually configured.
4. **Archive or Prune Persistent Data**:
   - Create final Restic snapshot before removal:
     ```bash
     ./manage.sh backup --tag retire-<stack-name>
     ```
   - Delete `${DOCKER_DATA_DIR}/<service>`.
5. **Clean Up Tests**:
   Remove or comment assertions in `.harness/suites/`. (Dynamic discovery will also automatically skip tests if stack directory is removed or `.disabled` is present).
6. **Remove Stack Directory**:
   ```bash
   rm -rf <stack-name>/
   ```
7. **Verify Mainline Health**:
   ```bash
   ./manage.sh test all
   ```
