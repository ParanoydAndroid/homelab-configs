# Project Backlog

This backlog tracks pending architectural improvements, infrastructure tasks, and technical debt items for the homelab environment.

---

## Active Backlog Items

### [BACKLOG-001] Tailscale tmpfs Socket Optimization
* **Priority**: Medium
* **Category**: Infrastructure / Reliability
* **Component**: `tailscale/compose.yml`
* **Trigger**: Execute after the host RAID 5 rebuild / reshape finishes.

#### Description
Add a `tmpfs: [/tmp]` mount to the Tailscale subnet router service definition in `tailscale/compose.yml`.

#### Motivation & Context
Under heavy disk I/O (such as host storage array rebuilds or parity reshapes), filesystem write operations within the container's overlayfs layer experience severe latency. Because Tailscale's `containerboot` entrypoint polls for `/tmp/tailscaled.sock` during daemon initialization, disk latency can cause initialization to exceed startup timeouts (`timed out waiting for tailscaled socket`). Additionally, persisting container sockets on disk can cause benign `[warning] failed to symlink socket: file exists` messages across restarts.

Mounting a `tmpfs` on `/tmp` keeps the UNIX domain socket entirely in host memory (RAM), eliminating disk contention and guaranteeing no stale socket files survive container recreation.

#### Verification Criteria
1. `tailscale/compose.yml` defines `tmpfs: [/tmp]`.
2. Tailscale container starts cleanly without socket startup delays.
3. `docker exec tailscale tailscale status --json` reports `BackendState: "Running"`.
4. `./homelab.sh test interconnect` passes with `test_interconnect_tailscale_backend_state` active.
