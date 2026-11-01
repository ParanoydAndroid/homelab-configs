---
name: test-authoring
description: >-
  Systematic recipe and standards for authoring automated smoke, interconnect,
  routing, and security regression tests in .tests/suites/. Use when introducing
  new services, adding proxy endpoints, or writing reproduction tests for bug fixes.
---

# Test Authoring Runbook

This skill guides the authoring and maintenance of automated tests within the homelab test framework (`./homelab.sh test`).

## Prerequisites
- Reference [Automated Test Suite Catalog and Assertion Patterns](./references/suite-catalog.md) for available test helper functions and suite structure.

---

## Authoring Workflow

### Step 1: Identify Target Test Suite
Determine where the new check belongs:
- **New container**: Add container state assertion to `.tests/suites/test_containers.sh`.
- **New reverse proxy host**: Add HTTP routing assertion to `.tests/suites/test_routing.sh`.
- **Database or inter-service API**: Add connection check to `.tests/suites/test_interconnect.sh`.
- **Public endpoint hardening**: Add path restriction check to `.tests/suites/test_negative_security.sh`.

### Step 2: Implement Test Case
Follow standard naming convention `test_<feature_or_bug>`:

```bash
test_my_service_health() {
  log_test "Testing my-service container runtime..."
  assert_container_running "my-service" "my-service container is active"
  assert_container_healthy "my-service" "my-service passes health check"
}

test_my_service_routing() {
  log_test "Testing my-service reverse proxy routing..."
  local status
  status=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: myservice.home" "https://${NPM_IPV4_ADDRESS}/")
  assert_equals "200" "${status}" "myservice.home returns 200 via NPM"
}
```

### Step 3: Register Test in Suite Runner
Ensure the test function is invoked inside the suite's `run_suite()` block:
```bash
run_suite() {
  ...
  test_my_service_health
  test_my_service_routing
}
```

### Step 4: Validate Execution
Run the specific suite directly:
```bash
./homelab.sh test routing
```
Then run the entire test suite to guarantee zero side effects:
```bash
./homelab.sh test all
```
