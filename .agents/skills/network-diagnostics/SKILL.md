---
name: network-diagnostics
description: >-
  Systematic diagnostic algorithm for troubleshooting homelab container networking,
  reverse proxy virtual hosts, macvlan isolation, DNS resolution, WireGuard killswitches,
  and Tailscale exit node routing loops.
---

# Network Diagnostics Runbook

This skill provides a step-by-step diagnostic workflow to troubleshoot routing, reverse proxy failures, DNS mismatches, and VPN bridge forwarding issues.

## Prerequisites
- Reference [Homelab Routing and Network Topology Reference](./references/routing-topology.md) for IP allocations and SQLite database schema.

---

## Diagnostic Flowchart

```text
[ Issue Detected ]
       │
       ├── HTTP/HTTPS Routing Issue? ───────> Run Phase 1 (NPM & VHost)
       ├── Container Communication Issue? ──> Run Phase 2 (Bridge & DNS)
       └── VPN / Tailscale Issue? ──────────> Run Phase 3 (VPN Bridge & Routes)
```

---

## Diagnostic Procedures

### Phase 1: Reverse Proxy & Virtual Host Triage
1. Check Nginx Proxy Manager container status and logs:
   ```bash
   docker ps -f name=nginx
   docker logs --tail 50 nginx
   ```
2. Verify SQLite proxy host forwarding configuration:
   ```bash
   sqlite3 /volume2/docker/nginx/data/database.sqlite \
     "SELECT id, domain_names, forward_host, forward_port, is_deleted FROM proxy_host WHERE domain_names LIKE '%<domain>%';"
   ```
3. Test virtual host routing with client impersonation (bypassing DNS):
   ```bash
   curl -k -v -H "Host: <domain>" https://192.168.0.4/
   ```
   * *Status 200/302*: Reverse proxy routing is working; issue is local client DNS.
   * *Status 502/504*: Forwarding target (`forward_host:forward_port`) is unreachable on the `homelab` network.

---

### Phase 2: Internal Bridge & Container DNS Resolution
1. Verify target container is running on the `homelab` bridge network:
   ```bash
   docker inspect <container_name> --format '{{json .NetworkSettings.Networks}}'
   ```
2. Test container-to-container DNS from within the `nginx` container:
   ```bash
   docker exec nginx getent hosts <forward_host>
   ```
3. Test raw TCP socket reachability:
   ```bash
   docker exec nginx nc -zvw3 <forward_host> <forward_port>
   ```

---

### Phase 3: VPN Bridge & Tailscale Exit Node Triage
1. Verify WireGuard (Gluetun) public IP and handshake:
   ```bash
   docker logs --tail 30 gluetun-pia
   docker exec gluetun-pia wget -qO- https://ipinfo.io/ip
   ```
2. Check Tailscale peer status and advertised routes:
   ```bash
   docker exec tailscale-pia tailscale status
   ```
3. Verify NAT masquerade and forwarding iptables rules inside `tailscale-pia`:
   ```bash
   docker exec tailscale-pia iptables -t nat -L POSTROUTING -v -n
   docker exec tailscale-pia iptables -L FORWARD -v -n
   ```
4. Check for routing loops:
   - Ensure `LOCAL_NETWORK` in `vpn-bridge/.env` does **NOT** contain `100.64.0.0/10`.
   - Verify MTU clamping rule exists:
     `iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`
