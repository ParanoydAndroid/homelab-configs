# Automated Test Suite Catalog and Assertion Patterns

## Suite Organization

All tests are orchestrated via `./manage.sh test [suite]` and live under `.harness/suites/`:

| Suite File | Scope & Assertions |
| :--- | :--- |
| `test_conventions.sh` | Verifies repository invariants, canonical entrypoints, memory bank files, and secrets hygiene. |
| `test_containers.sh` | Verifies container runtime states, exit codes (`0`), and Docker health status (`healthy`). |
| `test_direct_admin.sh` | Tests direct host port accessibility for non-HTTP services (e.g. Jellyfin discovery `8022:7359/udp`, Dockge `8010:5001`). |
| `test_routing.sh` | Tests client-impersonated reverse proxy virtual host routing, SSL termination, and HTTP status codes (`200`/`302`). |
| `test_interconnect.sh` | Tests internal service-to-service DNS resolution, database sockets (`postgres:5432`), internal API endpoints, and Tailscale exit routing. |
| `test_negative_security.sh` | Tests that sensitive administrative paths (`/swagger`, `/api-docs`, `/metrics`) are blocked (HTTP 403) on external endpoints (`*.kamaka.tech`). |
| `test_backup.sh` | Tests Restic repository snapshot accessibility, lock release, and integrity check. |

---

## Assertion Helper Functions

The test framework sources `.harness/lib/common.sh` providing standard testing helpers:

```bash
# Assert string equality
assert_equals "expected" "actual" "Test description"

# Assert HTTP status code from curl
assert_http_status "https://${NPM_IPV4_ADDRESS}/" 200 "Homepage root returns 200 OK" -H "Host: homepage.kamaka.tech"

# Assert command exits with code 0
assert_success "docker exec postgres pg_isready -U postgres" "Postgres socket is ready"

# Assert container health
assert_container_healthy "jellyfin" "Jellyfin reports healthy status"
```

---

## Writing Client-Impersonated HTTP Routing Tests

Because macvlan host-isolation prevents direct loopback calls over `eth0`, test virtual host routing using client header impersonation:

```bash
test_service_vhost() {
  local host_header="jellyfin.home"
  local expected_status=200

  local actual_status
  actual_status=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: ${host_header}" "https://${NPM_IPV4_ADDRESS}/")

  assert_equals "${expected_status}" "${actual_status}" "Virtual host ${host_header} resolves via reverse proxy"
}
```

---

## RAID Transition and I/O Considerations

When a RAID rebuild/reshape/scrub is in progress on the UGREEN NAS host storage:
- Storage latency increases significantly.
- High I/O container operations (e.g., streaming full Restic volume checks or heavy database scans) may trigger container execution timeouts.
- Run targeted sub-suites (`./manage.sh test routing`, `./manage.sh test interconnect`) instead of full heavy scans when high disk latency is detected.
