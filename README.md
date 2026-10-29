# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and management automation for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at `/opt/${USER}/dockge/stacks` (symlinked to `/home/${USER}/services`) so that all service stacks are simultaneously version-controlled in git and manageable through Dockge. For a detailed overview of the architectural principles, directory layout, and container privilege model, see [the architecture](.agents/artifacts/architecture.md).

---

## 1. Quickstart

### 1.1 Fresh Host Setup
```bash
# 1. Clone the repository into the Dockge stacks path and symlink to ~/services
sudo mkdir -p "/opt/${USER}/dockge"
git clone <repo-url> "/opt/${USER}/dockge/stacks"
ln -s "/opt/${USER}/dockge/stacks" "/home/${USER}/services"
cd "/home/${USER}/services"

# 2. Initialize .env files, Docker networks, and host workarounds
sudo ./homelab.sh setup

# 3. Populate required per-stack secrets and API keys in the generated .env files:
#    - homepage/.env       (HOMEPAGE_VAR_PIHOLE_KEY: Pi-hole Web UI password / API token)
#    - qbittorrentvpn/.env (VPN_USER, VPN_PASS: PIA credentials; QBITTORRENT_PASSWORD: WebUI password)
#    - tandoor/.env        (SECRET_KEY: generate via `base64 /dev/urandom | head -c50`)
#    - jellyfin/.env       (JELLYFIN_API_KEY: Jellyfin Dashboard -> Administration -> API Keys)
#    - sonarr-radarr/.env  (RADARR_API_KEY, SONARR_API_KEY, PROWLARR_API_KEY: deterministic API keys)
#    - seerr/.env          (SEERR_API_KEY: deterministic API key)
#    - cloudflared/.env    (CLOUDFLARE_TUNNEL_TOKEN: Zero Trust Dashboard -> Networks -> Tunnels)

# 4. Re-run setup to sync variables, deploy tracked configs, and start all containers
sudo ./homelab.sh setup
```

### 1.2 Routine Update After `git pull`
```bash
cd ~/services
git pull
sudo ./homelab.sh setup
```

---

## 2. Network Architecture & Ingress/Egress Model

### 2.1 Subnets and Docker Networks

| Network Name | Type / Driver | Subnet | Gateway | Parent Interface | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| LAN | Physical Ethernet | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Primary home LAN |
| WireGuard VPN | Routed VPN | `192.168.1.128/25` | `192.168.1.128` | Gateway | Remote WireGuard VPN subnet exposed by router/gateway |
| `homelab` | Docker `bridge` | `192.168.255.0/24` | `192.168.255.1` | `br-*` | Internal container-to-container network linking NPM, `cloudflared`, and backend services |
| `external_npm` | Docker `macvlan` | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Attaches Nginx Proxy Manager directly to the LAN at `192.168.0.4` (`turing.home`) |

To create the Docker networks manually (automated by `./homelab.sh setup`):
```bash
docker network create -d bridge \
  --subnet=192.168.255.0/24 \
  --gateway=192.168.255.1 \
  homelab

docker network create -d macvlan \
  --subnet=192.168.0.0/24 \
  --gateway=192.168.0.1 \
  -o parent=eth0 \
  external_npm
```

### 2.2 LAN Configuration (DHCP, Local DNS, and Static IP Addressing)

- **Gateway & DHCP Server (`192.168.0.1`)**:
  - Acts as the primary DHCP server for `192.168.0.0/24`.
  - Distributes `192.168.0.2` (Pi-hole) as the primary DNS server to all LAN clients.
  - Advertises `.home` as the local domain search suffix.
- **Pi-hole Local DNS Resolver (`192.168.0.2`)**:
  - Resolves upstream DNS queries with ad-blocking.
  - Configured with conditional forwarding for `.home` directed back to `192.168.0.1`.
  - Defines local CNAME records mapping all internal `<service>.turing.home` hostnames to `turing.home` (`192.168.0.4`).
- **Static IP and LAN Host Assignments**:

| Hostname / Domain | IP Address | Role and DNS Behavior |
| :--- | :--- | :--- |
| Gateway / Router | `192.168.0.1` | DHCP server; forwards DNS queries to Pi-hole (`192.168.0.2`); authoritative for `.home` hostnames |
| Pi-hole | `192.168.0.2` | Local DNS resolver; CNAME entries for `<service>.turing.home` -> `turing.home` |
| `nas.home` | `192.168.0.3` | UGREEN NAS host OS (`eth0`); exposes NAS web UI and emergency Dockge port (`8010`) |
| `turing.home` | `192.168.0.4` | Nginx Proxy Manager (`external_npm` macvlan IP); terminates HTTP (`80`), HTTPS (`443`), and NPM Admin UI (`81`) |

### 2.3 WAN Configuration, CGNAT, and Cloudflare Ingress Architecture

- **Carrier-Grade NAT (CGNAT) Context**:
  - The residential gateway interface is assigned a carrier private WAN IP in the `100.64.0.0/10` block (RFC 6598) and exits through a shared public IP.
  - Because upstream ISP CGNAT routers do not maintain inbound port mappings to subscriber WAN interfaces, traditional inbound IPv4 port forwarding (e.g. forwarding WAN `443` -> `192.168.0.4:443`) cannot receive inbound connections from the internet.
- **Cloudflare Zero Trust Tunnel (`cloudflared`)**:
  - External ingress is implemented using an outbound-only Cloudflare Tunnel (`homelab-media` stack running `cloudflare/cloudflared:latest`).
  - The `cloudflared` container connects outbound from the `homelab` Docker bridge network to Cloudflare edge data centers over encrypted QUIC / HTTP/2.
  - No gateway router ports need to be forwarded, and no public IPv4 address is required.
- **Wildcard Ingress & NPM Centralization (`*.kamaka.tech`)**:
  - Cloudflare Tunnel Public Hostnames routes wildcard `*.kamaka.tech` down the tunnel to `https://nginx:443` (with `No TLS Verify` enabled).
  - Nginx Proxy Manager remains the single declarative ingress controller for all traffic:
    - `jellyfin.kamaka.tech` routes to `jellyfin:8096` with exploit blocking, WebSockets, and `/metrics` / `/swagger` denial rules.
    - `recipes.kamaka.tech` routes to `tandoor:8080` with static `/media/` mounts.
    - Unconfigured or unexpected subdomains hit NPM's default host and are dropped or return a 404.
- **Gateway Firewall Rules**:
  ```text
  SOURCE 192.168.0.0/16 ALLOW
  ALL DENY
  ```
  All external inbound access enters strictly through the outbound-established Cloudflare tunnel rather than exposed WAN ports.

---

## 3. Service Catalog and Port Mappings

All HTTP/HTTPS web applications are reverse-proxied by Nginx Proxy Manager over the `homelab` Docker network (`192.168.255.0/24`). Host ports are exposed on the NAS (`192.168.0.3`) only where required for non-HTTP protocols or emergency orchestrator access; historical host ports are preserved below and in `compose.yml` comments for reference.

| Service Name | Stack / Path | Host Port (`nas.home`) | Container Port | Protocol | Active Host Binding | LAN Address (`turing.home`) | External Address (`kamaka.tech`) | Persistent Host Data Path |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| UGREEN NAS / DSM | Host OS | `5000` / `5001` | N/A | HTTP / HTTPS | Yes (Host OS) | `https://nas.home` | None | N/A |
| Dockge | `.configs/dockge` | `8010` | `5001` | TCP (HTTP) | **Yes** (`8010:5001`) | `https://dockge.turing.home` | None | `/volume1/docker/dockge/data` |
| Nginx Proxy Manager | `nginx/` | `8480` / `8443` / `8444` | `80` / `443` / `81` | TCP | Macvlan (`192.168.0.4:80,443,81`) | `https://proxy.turing.home` (or `http://turing.home:81`) | `https://*.kamaka.tech` (via Tunnel) | `/volume1/docker/nginx/data` |
| Cloudflare Tunnel | `cloudflared/` | None | None | QUIC / HTTP/2 | No (Egress Tunnel) | None | Ingress for `*.kamaka.tech` | Stateless |
| Jellyfin | `jellyfin/` | `8020` / `8021` | `8096` / `8920` | TCP (HTTP/S) | No (Proxied via NPM) | `https://jellyfin.turing.home` | `https://jellyfin.kamaka.tech` | `/volume1/docker/jellyfin/data/config` |
| Jellyfin Discovery | `jellyfin/` | `8022` | `7359` | UDP | **Yes** (`8022:7359/udp`) | LAN Broadcast | None | N/A |
| Homepage | `homepage/` | `8030` | `3000` | TCP (HTTP) | No (Proxied via NPM) | `https://homepage.turing.home` | None | `/volume1/docker/homepage/data` |
| Radarr | `sonarr-radarr/` | `8040` | `7878` | TCP (HTTP) | No (Proxied via NPM) | `https://radarr.turing.home` | None | `/volume1/docker/radarr/data` |
| Sonarr | `sonarr-radarr/` | `8041` | `8989` | TCP (HTTP) | No (Proxied via NPM) | `https://sonarr.turing.home` | None | `/volume1/docker/sonarr/data` |
| Prowlarr | `sonarr-radarr/` | `8042` | `9696` | TCP (HTTP) | No (Proxied via NPM) | `https://prowlarr.turing.home` | None | `/volume1/docker/prowlarr/data` |
| FlareSolverr | `sonarr-radarr/` | `8043` | `8191` | TCP (HTTP) | No (Internal / NPM) | `https://flaresolverr.turing.home` | None | Stateless |
| Seerr | `seerr/` | `8055` | `5055` | TCP (HTTP) | No (Proxied via NPM) | `https://seerr.turing.home` | None | `/volume1/docker/seerr/data` |
| Tandoor Recipes | `tandoor/` | `8050` | `8050` | TCP (HTTP) | No (Proxied via NPM) | `https://recipes.turing.home` | `https://recipes.kamaka.tech` | `/volume1/docker/tandoor/data/{staticfiles,mediafiles}` |
| PostgreSQL | `postgres/` | None | `5432` | TCP | No (`homelab` only) | `postgresql:5432` (Internal) | None | `/volume1/docker/postgres/data` |
| WireGuard PIA VPN | `qbittorrentvpn/` | `8081` | `8081` | TCP (WebUI) | No (Proxied via NPM) | `https://torrent.turing.home` | None | `/volume1/docker/qbittorrentvpn/data/{pia,pia-shared}` |
| qBittorrent | `qbittorrentvpn/` | Dynamic (PIA) | Dynamic (PIA) | TCP / UDP | No (`wg0` VPN Tunnel) | `http://qbittorrentvpn:8081` (Internal) | VPN Tunnel (`wg0`) | `/volume1/docker/qbittorrentvpn/data/config`, `/volume1/media` |

---

## 4. Environment Variable Architecture (`.env.example` -> `.env`)

All live `.env` files are ignored by git (`.gitignore`). Configuration uses a two-tier `.env.example` model so that stacks work seamlessly both via `homelab.sh` and inside the Dockge web UI (which runs `docker compose` inside each `<stack>/` subdirectory):

1. **Root `.env.example` (Global Defaults)**:
   - Defines host-wide paths, user/group IDs, timezone, and macvlan network settings (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_SUBNET`, `EXTERNAL_NPM_GATEWAY`, `EXTERNAL_NPM_PARENT`, `NPM_IPV4_ADDRESS`).
   - When `./homelab.sh setup` runs, it initializes the root `.env` (resolving `${SUDO_USER:-${USER}}` into literal paths) and automatically syncs those global keys into every `<stack>/.env` and `${DOCKGE_DIR}/.env`.
2. **Per-Stack `<stack>/.env.example` (Secrets and Per-Install Keys)**:
   - Defines external credentials and per-installation API/cryptographic keys with blank defaults (`KEY=`):
     - `cloudflared/.env.example`: `CLOUDFLARE_TUNNEL_TOKEN=` (Cloudflare Zero Trust Tunnel authentication token)
     - `homepage/.env.example`: `HOMEPAGE_VAR_PIHOLE_KEY=` (Pi-hole admin password or API token from Pi-hole **Settings -> API / Web interface**)
     - `jellyfin/.env.example`: `JELLYFIN_API_KEY=` (Generated in Jellyfin **Dashboard -> Administration -> API Keys -> `+`**)
     - `qbittorrentvpn/.env.example`: `VPN_USER=`, `VPN_PASS=` (Private Internet Access OpenVPN/account credentials), `QBITTORRENT_PASSWORD=` (qBittorrent WebUI password configured in **Tools -> Options -> Web UI -> Authentication**)
     - `sonarr-radarr/.env.example`: `RADARR_API_KEY=`, `SONARR_API_KEY=`, `PROWLARR_API_KEY=` (Deterministic API keys for Servarr authentication)
     - `seerr/.env.example`: `SEERR_API_KEY=` (Deterministic API key for Seerr media request management)
     - `tandoor/.env.example`: `SECRET_KEY=` (Random 50-character secret generated via `base64 /dev/urandom | head -c50`)

### 4.1 How Homepage Dashboard Service Discovery and Widget Keys Work
Homepage (`ghcr.io/gethomepage/homepage`) aggregates live status metrics (active streams, torrent speeds, queue counts, DNS queries) by polling each backend service's HTTP API over the internal `homelab` Docker network (`192.168.255.0/24`). Credentials and API keys are supplied through two mechanisms so that **no secrets are ever committed to git**:

1. **Docker Container Labels (Containerized Services)**:
   - Homepage mounts `/var/run/docker.sock` (configured via `.configs/homepage/docker.yaml`) and inspects all running containers on the host for `homepage.*` labels.
   - In each stack's `compose.yml` (`jellyfin`, `qbittorrentvpn`, `sonarr-radarr`), labels define both the dashboard card metadata and the widget polling configuration:
     ```yaml
     labels:
       - homepage.group=Players
       - homepage.name=Jellyfin
       - homepage.icon=jellyfin
       - homepage.href=http://jellyfin.turing.home
       - homepage.widget.type=jellyfin
       - homepage.widget.version=2
       - homepage.widget.url=http://jellyfin:8096
       - homepage.widget.key=${JELLYFIN_API_KEY}
     ```
   - When `docker compose up -d` runs inside `<stack>/`, Docker Compose reads `<stack>/.env` and interpolates `${JELLYFIN_API_KEY}` into the running container's metadata labels.
   - Homepage reads those resolved labels from `/var/run/docker.sock` and queries `http://jellyfin:8096` directly over the `homelab` bridge network (so backend ports never need to be exposed on the NAS host).

2. **Static YAML Environment Substitution (`HOMEPAGE_VAR_*` for Non-Docker Appliances)**:
   - Services that do not run as local Docker containers on the NAS (such as Pi-hole on `192.168.0.2` or the UGREEN NAS DSM UI on `nas.home`) cannot be discovered via Docker labels and are instead defined in `.configs/homepage/services.yaml`.
   - Homepage natively substitutes any `{{HOMEPAGE_VAR_<NAME>}}` placeholder in its YAML config files with the value of the `HOMEPAGE_VAR_<NAME>` environment variable passed to the `homepage` container.
   - Therefore, `.configs/homepage/services.yaml` uses `key: "{{HOMEPAGE_VAR_PIHOLE_KEY}}"`, while the secret value lives in untracked `homepage/.env` (`HOMEPAGE_VAR_PIHOLE_KEY=...`) and is passed into the `homepage` container via `homepage/compose.yml`.

---

## 5. Automation CLI (`homelab.sh`) and Common Use-Case Guides

### 5.1 `homelab.sh` Subcommands

- `sudo ./homelab.sh setup`:
  Idempotently applies the UGREEN NAS `GODEBUG` fix, initializes missing `.env` files from `.env.example`, syncs root `.env` globals into stack `.env` files, warns on blank required variables, creates the `homelab` and `external_npm` Docker networks if missing, runs `deploy-configs`, deploys Dockge to `${DOCKGE_DIR}/compose.yml`, and starts Dockge and all Compose stacks in dependency order.
- `./homelab.sh test`:
  Executes an automated, zero-downtime smoke test suite across all 13 containers, validating container health status, direct admin interfaces (Dockge port 8010 and NPM Admin API), client-impersonated virtual host routing over NPM (verifying SSL status codes and security headers across both `*.turing.home` and `*.kamaka.tech`), and inter-container network sockets (Radarr/Sonarr to qBittorrent, Prowlarr to FlareSolverr, Tandoor to PostgreSQL, and PIA VPN port synchronization).
- `./homelab.sh deploy-configs`:
  Compares tracked files in `.configs/` against live files in `/volume1/docker/...` and `${DOCKGE_DIR}/compose.yml`. When differences are detected, shows a unified diff and prompts `[o]verwrite / [k]eep / [O]verwrite all / [K]eep all`. Skips deploying NPM proxy host `.conf` files whose referenced SSL certificates do not yet exist on disk, and reloads Nginx if any NPM config changes.
- `./homelab.sh pull-configs`:
  Retrieves live configuration changes made via UIs (Homepage YAML files, NPM `db.sqlite` host exports and `.conf` files, and `set-qbt-port.sh`) from `/volume1/docker/...` back into `.configs/` so they can be inspected with `git diff` and committed.
- `./homelab.sh backup [--tag [tag_name]] [-m <message>]`:
  Runs `pull-configs` to sync live service configurations into `.configs/`, commits any repository or configuration changes to git, optionally tags `HEAD` (defaulting to a chronological PEP 440 / CalVer tag `YYYY.M.D` or `YYYY.M.D.N` when `--tag` is passed without a name), and archives all untracked live `.env` secret files into `/volume1/docker/backup/homelab/YYYY.M.D_env_secrets.tar.gz` (symlinked at `latest_env_secrets.tar.gz`).

### 5.2 Use-Case Quick Guides

#### Use Case 1: Editing Proxy Hosts in the NPM UI and Versioning Changes in Git
1. Open the NPM Admin UI at `https://proxy.turing.home` (or `http://192.168.0.4:81`) and save your proxy host changes.
2. Pull the updated NPM database export and generated `.conf` files into the repository:
   ```bash
   cd ~/services
   ./homelab.sh pull-configs
   git diff .configs/nginx/
   git add .configs/nginx/
   git commit -m "Update NPM proxy host configuration"
   ```

#### Use Case 2: Updating Homepage Dashboard YAML or Adding a New Stack
1. Edit `.configs/homepage/*.yaml` (or modify `/volume1/docker/homepage/data/*.yaml` directly and run `./homelab.sh pull-configs`).
2. Deploy the updated configuration to `/volume1/docker/homepage/data/`:
   ```bash
   ./homelab.sh deploy-configs
   ```
3. If adding a new stack, create `<new-stack>/compose.yml` (and optional `<new-stack>/.env.example`), then run `sudo ./homelab.sh setup` to sync global `.env` variables and start the stack.

#### Use Case 3: Backing Up and Restoring Configurations and `.env` Secrets
Because all portable service configurations (`.configs/homepage/`, `.configs/nginx/`, `.configs/dockge/`, `.configs/qbittorrentvpn/`) live inside this git repository, `./homelab.sh backup` performs a four-step backup workflow:
1. **Pull Live Configs (`pull-configs`)**: Syncs any changes made through the Homepage or Nginx Proxy Manager Web UIs (plus `set-qbt-port.sh`) from `/volume1/docker/...` into `.configs/`.
2. **Git Commit**: If the repository working tree has any modified or new files, stages (`git add -A`) and commits them (using `-m "<message>"` if provided, or a default timestamped commit message).
3. **Optional Chronological Git Tag (`--tag` / `-t`)**:
   - Passing `--tag` without an argument creates an annotated PEP 440 / CalVer chronological tag on `HEAD` formatted as `YYYY.M.D` (e.g., `2026.10.28`), automatically incrementing to `YYYY.M.D.1`, `YYYY.M.D.2`, etc. if a tag already exists on that date.
   - Passing `--tag <custom_name>` tags `HEAD` with `<custom_name>`.
4. **Archive Untracked `.env` Secrets**: Collects the root `.env` and all per-stack `<stack>/.env` files (which are excluded from git via `.gitignore`) into `/volume1/docker/backup/homelab/YYYY.M.D_env_secrets.tar.gz` (`chmod 0600`) and updates the `/volume1/docker/backup/homelab/latest_env_secrets.tar.gz` symlink.

```bash
cd ~/services

# Standard backup with auto-generated chronological tag (e.g. 2026.10.28):
./homelab.sh backup --tag

# Backup with custom commit message and custom tag name:
./homelab.sh backup -m "Pre-upgrade snapshot" --tag 2026.10.28-pre-upgrade

# Push committed configuration history and tags to your remote git server:
git push && git push --tags

# Restore all untracked .env secret files in-place on a new/restored checkout:
tar -xzf /volume1/docker/backup/homelab/latest_env_secrets.tar.gz -C ~/services
sudo ./homelab.sh setup
```

---

## 6. Service-Specific Configuration & Hardening Procedures

### 6.1 Combined Local Self-Signed Certificate (`turing.home` and `nas.home`)
To avoid browser certificate warnings across both `*.turing.home` (NPM) and `*.nas.home` (UGREEN NAS web UI) using a single certificate:

1. Generate `turing.key` and `turing.crt` (valid for 10 years covering `turing.home`, `*.turing.home`, `nas.home`, and `*.nas.home`):
   ```bash
   cd ~/services/.configs/nginx
   ./generate-local-cert.sh
   ```
2. **Import into Client Devices**: Import `turing.crt` into your OS/browser Trusted Root Certification Authorities store.
3. **Upload to UGREEN NAS (`nas.home`)**: In the UGREEN NAS Control Panel -> Security -> Certificate, upload `turing.key` and `turing.crt` and set as default.
4. **Upload to Nginx Proxy Manager (`turing.home`)**:
   - Open `https://proxy.turing.home` (or `http://192.168.0.4:81`) -> SSL Certificates -> Add SSL Certificate -> Custom.
   - Name: `Local Wildcard (turing.home + nas.home)`, Certificate Key: `turing.key`, Certificate: `turing.crt`.
   - Assign this certificate to all `*.turing.home` Proxy Hosts.

### 6.2 Let's Encrypt Wildcard Certificate (`*.kamaka.tech`) in NPM
1. In NPM (`https://proxy.turing.home`), go to **SSL Certificates -> Add SSL Certificate -> Let's Encrypt**.
2. Set Domain Names to `kamaka.tech` and `*.kamaka.tech`.
3. Enable **Use a DNS Challenge**, select **Cloudflare**, and supply `dns_cloudflare_api_token = <your-cloudflare-dns-edit-token>`.
4. Assign the certificate to external Proxy Hosts (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`).
5. If setting up a fresh host where `deploy-configs` skipped NPM `.conf` files due to missing certs, re-run `./homelab.sh deploy-configs` after creating the certificates.

### 6.3 Cloudflare Zero Trust Ingress & Cache Rules

#### 1. Wildcard Ingress Routing to NPM
In [one.dash.cloudflare.com](https://one.dash.cloudflare.com/) -> **Networks -> Tunnels -> homelab-media -> Public Hostnames**:
- **Subdomain**: `*`
- **Domain**: `kamaka.tech`
- **Type**: `HTTPS`
- **URL**: `nginx:443`
- **Additional Application Settings -> TLS**:
  - **No TLS Verify**: `Enabled`
  - **Origin Server Name**: `jellyfin.kamaka.tech` (Required: provides the TLS SNI during the handshake with NPM; prevents Nginx from aborting the connection with `tls: unrecognized name` / 502 Bad Gateway)
  - **HTTP Host Header**: Blank (preserves client Host header)

#### 2. Cache Bypass for Video Streaming
To prevent Cloudflare's CDN caching layer from throttling or buffering video chunks:
1. In Cloudflare Dashboard -> `kamaka.tech` -> **Caching -> Cache Rules -> Create Rule**.
2. Rule Name: `Bypass Jellyfin Video Cache`.
3. When incoming requests match: Field `Hostname` equals `jellyfin.kamaka.tech`.
4. Action: **Bypass cache**.

### 6.4 External Jellyfin Security Hardening (`jellyfin.kamaka.tech`)

#### Container & Reverse Proxy Hardening (Automated in Repo)
- `jellyfin/compose.yml` runs Jellyfin as non-root (`user: "1000:100"`), drops all Linux capabilities (`cap_drop: [ALL]`), enforces `no-new-privileges:true`, removes direct HTTP/HTTPS host ports (`8020`/`8021`), and mounts `/volume1/media:/data/media:ro` read-only.
- The NPM proxy host (`proxy_host/3.conf` for `jellyfin.kamaka.tech`) enables Force SSL, HTTP/2, HSTS, Block Exploits, **WebSockets Support** (`allow_websocket_upgrade=1`), disables proxy buffering (`proxy_buffering off;`), sets security and real-IP headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `X-Robots-Tag`, `CF-Connecting-IP`), and blocks external access to `/swagger`, `/api-docs`, and `/metrics`.

#### Jellyfin Application Settings (One-Time Manual UI Check)
In **Jellyfin Dashboard -> Networking** and **Dashboard -> Users**:
1. **Local Network Subnets**: Add `192.168.255.0/24` so local Docker communication is classified as internal.
2. **Known Proxies**: Set `Known Proxies` to `192.168.255.0/24` (or NPM's `homelab` container hostname/IP `nginx`) and restart Jellyfin so Jellyfin logs and rate-limits real external client IPs instead of NPM's bridge IP.
3. **Disable Remote Admin Login**: Select your administrative user -> Profile -> uncheck **Allow remote connections to this server** (use a separate non-admin user account for remote playback).
4. **Hide Users & Enable Lockout**: Check **Hide this user from login screens on remote devices** for all users, and set **Maximum invalid login attempts before user is locked out** (e.g., `3` or `5`).

### 6.5 Tandoor Recipes Media Serving in NPM (`recipes.kamaka.tech`)
Tandoor's Gunicorn container does not serve `/media/` directly in production. Instead, `nginx/compose.yml` mounts `/volume1/docker/tandoor/data/mediafiles:/media:ro` and the `recipes.kamaka.tech` proxy host includes the custom Nginx configuration:
```nginx
location /media/ {
    root /;
}
```

### 6.6 UGREEN NAS `GODEBUG=tlskyber=0` Remediation (Go 1.23+ & Antigravity Remote Fix)
UGREEN NAS OS sets `GODEBUG=tlskyber=0` in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`, which causes Go 1.23+ binaries (including the Antigravity remote server) to panic on startup because the legacy `tlskyber` flag was removed in Go 1.23.

`sudo ./homelab.sh setup` automatically checks and remediates this on every run. To run the fix manually after a UGREEN firmware update:
```bash
sudo sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
sudo sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
sudo systemctl unset-environment GODEBUG
systemctl --user unset-environment GODEBUG || true
sudo systemctl daemon-reexec
```

### 6.7 WireGuard PIA VPN + qBittorrent Architecture and Automated Port Forwarding

#### Decoupled Two-Container Network Namespace (`wireguard-pia` + `qbittorrentvpn`)
The `qbittorrentvpn/compose.yml` stack decouples the VPN gateway and BitTorrent client into two dedicated containers sharing a single network namespace:
1. **`vpn` (`thrnz/docker-wireguard-pia:latest`, container `wireguard-pia`)**:
   - Authenticates against Private Internet Access (`USER` / `PASS`) and registers a WireGuard keypair with the region configured in `LOC` (`ca_ontario,ca_toronto,ca_montreal` primary with commented alternatives `us_chicago` and `us_east` in `qbittorrentvpn/compose.yml`).
   - Creates the kernel-space `wg0` WireGuard interface (`fwmark 0xca6c`) and enforces an `iptables` kill switch (`FIREWALL: 1`) that drops all untunnelled traffic except local WebUI traffic from `LOCAL_NETWORK: 192.168.0.0/16` (covering the home LAN `192.168.0.0/24`, remote WireGuard `192.168.1.128/25`, and internal `homelab` Docker bridge `192.168.255.0/24`).
   - Attaches to the `homelab` Docker bridge network (`192.168.255.0/24`) with network alias and hostname `qbittorrentvpn`.
2. **`qbittorrent` (`lscr.io/linuxserver/qbittorrent:latest`, container `qbittorrentvpn`)**:
   - Uses `network_mode: "service:vpn"` and `depends_on: vpn (condition: service_healthy)` so it shares `wireguard-pia`'s network stack (`lo`, `eth0`, and `wg0`), binds directly to `Connection\Interface=wg0`, and has no independent network interface capable of leaking traffic outside the WireGuard tunnel.
   - Because both containers share the same network namespace, Nginx Proxy Manager, Sonarr, Radarr, Prowlarr, and Homepage reach qBittorrent's WebUI seamlessly at `http://qbittorrentvpn:8081`.

#### Automated PIA NextGen Dynamic Port Forwarding (`set-qbt-port.sh`)
Private Internet Access (PIA) assigns a dynamic incoming port per VPN session on non-US regions (`ca_ontario`, `ca_toronto`, `ca_montreal`, etc.; US endpoints do not support port forwarding). `thrnz/docker-wireguard-pia` natively automates the PIA NextGen port-forwarding lifecycle:
1. **Token & Signature Negotiation**: When `PORT_FORWARDING: 1` and `PORT_PERSIST: 1` are enabled, `wireguard-pia`'s `/scripts/pf.sh` daemon requests a cryptographic port signature and payload from the PIA WireGuard gateway (`https://<cn>:19999/getSignature`), persists the token in `/pia/portsig.json` so the same port is reused across restarts until its ~60-day expiry, and opens the assigned TCP/UDP port on `wg0` in `iptables`.
2. **Automatic qBittorrent Listening Port Sync (`.configs/qbittorrentvpn/set-qbt-port.sh`)**: As soon as the port is bound, `wireguard-pia` executes `PORT_SCRIPT: /set-qbt-port.sh <port>` (tracked at `.configs/qbittorrentvpn/set-qbt-port.sh` and deployed to `/volume1/docker/qbittorrentvpn/data/set-qbt-port.sh`). The script waits until qBittorrent's WebUI listener (`127.0.0.1:8081`) is up and sends an HTTP POST request to `/api/v2/app/setPreferences` with `json={"listen_port":<port>}`. Because `WebUI\LocalHostAuth=false` is set in `qBittorrent.conf` (and `127.0.0.1` is isolated inside the container network namespace), qBittorrent immediately updates its listening port to match the PIA-forwarded port.
3. **15-Minute Keepalive Loop & Health Monitoring**: `pf.sh` automatically re-binds the port (`https://<cn>:19999/bindPort`) every 900 seconds (15 minutes). Because `PORT_FATAL: 1` is set, the container healthcheck verifies both `wg show wg0` and `pidof pf.sh`.
