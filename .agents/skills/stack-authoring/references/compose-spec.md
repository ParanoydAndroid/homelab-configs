# Docker Compose and Stack Standards Reference

## Directory Layout Standards

Dockge requires a strict 1-to-1 directory structure at repository root:
```text
/opt/${USER}/dockge/stacks/
├── <stack-name>/
│   ├── compose.yml
│   └── .env.example
```

- Each non-hidden directory at root represents a runnable Dockge stack.
- Tracked non-stack assets or orchestrators must live in `.configs/<service>/` (e.g. `.configs/dockge/compose.yml`) to prevent Dockge from treating them as child stacks.

---

## Canonical Service Key Ordering

Maintain consistent 2-space YAML key ordering across all service blocks:

```yaml
services:
  <service-name>:
    image: <image>:<tag>
    container_name: <service-name>
    hostname: <service-hostname>
    user: "${PUID:?...}:${PGID:?...}"        # Only where appropriate (see Privilege Model)
    restart: unless-stopped
    privileged: false                        # Default false; omit or set true only if strictly required
    cap_add:
      - NET_ADMIN
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    sysctls:
      - net.ipv4.ip_forward=1
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - PUID=${PUID:?See env.example for default.}
      - PGID=${PGID:?See env.example for default.}
      - TZ=${TZ:?See env.example for default.}
    volumes:
      - ${DOCKER_DATA_DIR:?See env.example for default.}/<service>/data:/config
      - ${MEDIA_DIR:?See env.example for default.}:/data:ro
    ports:
      # Expose host ports only for broadcast/LAN protocols or emergency fallback
      # - "8080:8080"
      - "8022:7359/udp"
    networks:
      - homelab
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    labels:
      - "com.dockge.stack=<stack-name>"
```

---

## Environment Variable Assertion Syntax

All Docker Compose files must treat runtime environment variables as required using explicit parameter expansion assertions:

```yaml
${VARIABLE:?See env.example for default.}
```

### Invariant Rules:
1. **Never use inline fallback defaults** in `compose.yml` (e.g. `${VAR:-default}`). All default values belong exclusively in `.env.example`.
2. **Fixed stack invariants** (such as static internal ports, log levels, or allowed hosts) should be hardcoded directly in `compose.yml` rather than cluttering `.env.example`.
3. **Intentionally optional runtime values** (such as one-time setup keys like `TS_AUTHKEY`) must use `${TS_AUTHKEY:-}` so subsequent container restarts succeed after the token is invalidated.
4. **Script Boundary**: Shell scripts (`.scripts/*.sh`, `homelab.sh`) must use normal parameter expansion (`${VAR}`) without `:?`.

---

## Privilege and Non-Root Execution Model

1. **Images dropping privileges internally via PUID/PGID**:
   - Examples: `lscr.io/linuxserver/*`, `vabene1111/recipes`.
   - **Do NOT** set Compose `user:` key on these containers. Their entrypoints require root startup to configure file ownership before stepping down to `PUID`/`PGID`.
   - Pass `PUID` and `PGID` in `environment:`.

2. **Images requiring explicit Compose user specification**:
   - Examples: `jellyfin/jellyfin`.
   - Set Compose `user: "${PUID:?See env.example for default.}:${PGID:?See env.example for default.}"`.

3. **Containers requiring root or internal system UIDs**:
   - `postgres`: Runs under internal `postgres` user (UID `70`). Do not override with host `1000:100`.
   - `dockge`, `nginx` (NPM): Run as root for orchestration and socket binding.

---

## Network Architecture

1. **Internal Bridge (`homelab`)**:
   - All backend containers must attach to `homelab` (`192.168.255.0/24`).
   - Declared at top level:
     ```yaml
     networks:
       homelab:
         external: true
     ```

2. **LAN Macvlan (`external_npm`)**:
   - Reserved exclusively for Nginx Proxy Manager (`192.168.0.4`) to bridge HTTP/HTTPS traffic to the internal bridge.
