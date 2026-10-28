# Homelab Services Infrastructure and Configuration

This repository defines the Docker Compose service stacks, tracked application configurations, and management automation for the UGREEN NAS homelab environment (`nas.home` / `turing.home`).

The repository is checked out at `/opt/${USER}/dockge/stacks` (symlinked to `/home/${USER}/services`) so that all service stacks are simultaneously version-controlled in git and manageable through Dockge.

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
#    - qbittorrentvpn/.env (VPN_USER, VPN_PASS, QBITTORRENT_WIDGET_PASSWORD)
#    - tandoor/.env        (SECRET_KEY)
#    - jellyfin/.env       (JELLYFIN_WIDGET_KEY)
#    - sonarr-radarr/.env  (RADARR_WIDGET_KEY, SONARR_WIDGET_KEY, PROWLARR_WIDGET_KEY)

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

## 2. Network Architecture and Topology

### 2.1 Subnets and Docker Networks

| Network Name | Type / Driver | Subnet | Gateway | Parent Interface | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| LAN | Physical Ethernet | `192.168.0.0/24` | `192.168.0.1` | `eth0` | Primary home LAN (Single NAT; WAN IP assigned to gateway `192.168.0.1`) |
| WireGuard VPN | Routed VPN | `192.168.1.128/25` | `192.168.1.128` | Gateway | Remote WireGuard VPN subnet exposed by router/gateway |
| `homelab` | Docker `bridge` | `192.168.255.0/24` | `192.168.255.1` | `br-*` | Internal container-to-container network linking NPM and backend services |
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

### 2.2 Static IP and DNS Assignments

| Hostname / Domain | IP Address | Role and DNS Behavior |
| :--- | :--- | :--- |
| Gateway / Router | `192.168.0.1` | DHCP server; assigns `192.168.0.2` (Pi-hole) as DNS server and `.home` as local domain |
| Pi-hole | `192.168.0.2` | Local DNS resolver; conditional forwarding for `.home` to `192.168.0.1`; serves CNAME records for `<service>.turing.home` -> `turing.home` |
| `nas.home` | `192.168.0.3` | UGREEN NAS host OS (`eth0`); exposes NAS web UI and emergency Dockge port (`8010`) |
| `turing.home` | `192.168.0.4` | Nginx Proxy Manager (`external_npm` macvlan IP); terminates HTTP (`80`), HTTPS (`443`), and NPM Admin UI (`81`) for all `*.turing.home` and `*.kamaka.tech` subdomains |

### 2.3 Gateway Firewall Rules
```text
SOURCE 192.168.0.0/16 ALLOW
PORT 443 ALLOW (Forwarded to 192.168.0.4:443 for *.kamaka.tech)
ALL DENY
```

---

## 3. Service Catalog and Port Mappings

All HTTP/HTTPS web applications are reverse-proxied by Nginx Proxy Manager over the `homelab` Docker network (`192.168.255.0/24`). Host ports are exposed on the NAS (`192.168.0.3`) only where required for non-HTTP protocols or emergency orchestrator access; historical host ports are preserved below and in `compose.yml` comments for reference.

| Service Name | Stack / Path | Host Port (`nas.home`) | Container Port | Protocol | Active Host Binding | LAN Address (`turing.home`) | External Address (`kamaka.tech`) | Persistent Host Data Path |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| UGREEN NAS / DSM | Host OS | `5000` / `5001` | N/A | HTTP / HTTPS | Yes (Host OS) | `https://nas.home` | None | N/A |
| Dockge | `.configs/dockge` | `8010` | `5001` | TCP (HTTP) | **Yes** (`8010:5001`) | `https://dockge.turing.home` | None | `/volume1/docker/dockge/data` |
| Nginx Proxy Manager | `nginx/` | `8480` / `8443` / `8444` | `80` / `443` / `81` | TCP | Macvlan (`192.168.0.4:80,443,81`) | `http://turing.home:81` | `https://*.kamaka.tech` | `/volume1/docker/nginx/data` |
| Jellyfin | `jellyfin/` | `8020` / `8021` | `8096` / `8920` | TCP (HTTP/S) | No (Proxied via NPM) | `https://jellyfin.turing.home` | `https://jellyfin.kamaka.tech` | `/volume1/docker/jellyfin/data/config` |
| Jellyfin Discovery | `jellyfin/` | `8022` | `7359` | UDP | **Yes** (`8022:7359/udp`) | LAN Broadcast | None | N/A |
| Homepage | `homepage/` | `8030` | `3000` | TCP (HTTP) | No (Proxied via NPM) | `https://homepage.turing.home` | None | `/volume1/docker/homepage/data` |
| Radarr | `sonarr-radarr/` | `8040` | `7878` | TCP (HTTP) | No (Proxied via NPM) | `https://radarr.turing.home` | None | `/volume1/docker/radarr/data` |
| Sonarr | `sonarr-radarr/` | `8041` | `8989` | TCP (HTTP) | No (Proxied via NPM) | `https://sonarr.turing.home` | None | `/volume1/docker/sonarr/data` |
| Prowlarr | `sonarr-radarr/` | `8042` | `9696` | TCP (HTTP) | No (Proxied via NPM) | `https://prowlarr.turing.home` | None | `/volume1/docker/prowlarr/data` |
| FlareSolverr | `sonarr-radarr/` | `8043` | `8191` | TCP (HTTP) | No (Internal / NPM) | `https://flaresolverr.turing.home` | None | Stateless |
| Tandoor Recipes | `tandoor/` | `8050` | `8050` | TCP (HTTP) | No (Proxied via NPM) | `https://recipes.turing.home` | `https://recipes.kamaka.tech` | `/volume1/docker/tandoor/data/{staticfiles,mediafiles}` |
| PostgreSQL | `postgres/` | None | `5432` | TCP | No (`homelab` only) | `postgresql:5432` (Internal) | None | `/volume1/docker/postgres/data` |
| qBittorrentVPN | `qbittorrentvpn/` | `8081` | `8081` | TCP (WebUI) | No (Proxied via NPM) | `https://torrent.turing.home` | None | `/volume1/docker/qbittorrentvpn/data/config` |
| qBittorrentVPN Peers | `qbittorrentvpn/` | `58946` | `58946` | TCP / UDP | **Yes** (`58946:58946`) | VPN / Peer Port | VPN Tunnel | `/volume1/media` |

---

## 4. Environment Variable Architecture (`.env.example` -> `.env`)

All live `.env` files are ignored by git (`.gitignore`). Configuration uses a two-tier `.env.example` model so that stacks work seamlessly both via `homelab.sh` and inside the Dockge web UI (which runs `docker compose` inside each `<stack>/` subdirectory):

1. **Root `.env.example` (Global Defaults)**:
   - Defines host-wide paths, user/group IDs, timezone, and macvlan network settings (`DOCKER_DATA_DIR`, `MEDIA_DIR`, `DOCKGE_DIR`, `DOCKGE_STACKS_DIR`, `PUID`, `PGID`, `TZ`, `EXTERNAL_NPM_SUBNET`, `EXTERNAL_NPM_GATEWAY`, `EXTERNAL_NPM_PARENT`, `NPM_IPV4_ADDRESS`).
   - When `./homelab.sh setup` runs, it initializes the root `.env` (resolving `${SUDO_USER:-${USER}}` into literal paths) and automatically syncs those global keys into every `<stack>/.env` and `${DOCKGE_DIR}/.env`.
2. **Per-Stack `<stack>/.env.example` (Secrets and Per-Install Keys)**:
   - Defines external credentials and per-installation API/cryptographic keys with blank defaults (`KEY=`):
     - `jellyfin/.env.example`: `JELLYFIN_WIDGET_KEY=`
     - `qbittorrentvpn/.env.example`: `VPN_USER=`, `VPN_PASS=`, `QBITTORRENT_WIDGET_PASSWORD=`
     - `sonarr-radarr/.env.example`: `RADARR_WIDGET_KEY=`, `SONARR_WIDGET_KEY=`, `PROWLARR_WIDGET_KEY=`
     - `tandoor/.env.example`: `SECRET_KEY=`

---

## 5. Automation CLI (`homelab.sh`) and Common Use-Case Guides

### 5.1 `homelab.sh` Subcommands

- `sudo ./homelab.sh setup`:
  Idempotently applies the UGREEN NAS `GODEBUG` fix, initializes missing `.env` files from `.env.example`, syncs root `.env` globals into stack `.env` files, warns on blank required variables, creates the `homelab` and `external_npm` Docker networks if missing, runs `deploy-configs`, deploys Dockge to `${DOCKGE_DIR}/compose.yml`, and starts Dockge and all Compose stacks in dependency order.
- `./homelab.sh deploy-configs`:
  Compares tracked files in `.configs/` against live files in `/volume1/docker/...` and `${DOCKGE_DIR}/compose.yml`. When differences are detected, shows a unified diff and prompts `[o]verwrite / [k]eep / [O]verwrite all / [K]eep all`. Skips deploying NPM proxy host `.conf` files whose referenced SSL certificates do not yet exist on disk, and reloads Nginx if any NPM config changes.
- `./homelab.sh pull-configs`:
  Retrieves live configuration changes made via UIs (Homepage YAML files, NPM `db.sqlite` host exports and `.conf` files, and `getvpnport.sh`) from `/volume1/docker/...` back into `.configs/` so they can be inspected with `git diff` and committed.
- `./homelab.sh backup` (or `./backup-homelab.bash`):
  Creates a timestamped archive `/volume1/docker/backup/homelab/YYYYMMDD_homelab_config.tar.gz` containing `README.md`, `homelab.sh`, `.configs/`, all `compose.yml` files, live `.env` files, and portable service configurations.

### 5.2 Use-Case Quick Guides

#### Use Case 1: Editing Proxy Hosts in the NPM UI and Versioning Changes in Git
1. Open the NPM Admin UI at `http://192.168.0.4:81` (or `http://turing.home:81`) and save your proxy host changes.
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

#### Use Case 3: Creating a Full Configuration Backup Before Major Changes
```bash
cd ~/services
./homelab.sh pull-configs
./homelab.sh backup
ls -lh /volume1/docker/backup/homelab/
```

---

## 6. One-Time Manual Setup and Hardening Procedures

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
   - Open `http://192.168.0.4:81` -> SSL Certificates -> Add SSL Certificate -> Custom.
   - Name: `Local Wildcard (turing.home + nas.home)`, Certificate Key: `turing.key`, Certificate: `turing.crt`.
   - Assign this certificate to all `*.turing.home` Proxy Hosts.

### 6.2 Let's Encrypt Wildcard Certificate (`*.kamaka.tech`) in NPM
1. In NPM (`http://192.168.0.4:81`), go to **SSL Certificates -> Add SSL Certificate -> Let's Encrypt**.
2. Set Domain Names to `kamaka.tech` and `*.kamaka.tech`.
3. Enable **Use a DNS Challenge**, select **Cloudflare**, and supply `dns_cloudflare_api_token = <your-cloudflare-dns-edit-token>`.
4. Assign the certificate to external Proxy Hosts (`jellyfin.kamaka.tech`, `recipes.kamaka.tech`).
5. If setting up a fresh host where `deploy-configs` skipped NPM `.conf` files due to missing certs, re-run `./homelab.sh deploy-configs` after creating the certificates.

### 6.3 Tandoor Recipes Media Serving in NPM (`recipes.kamaka.tech`)
Tandoor's Gunicorn container does not serve `/media/` directly in production. Instead, `nginx/compose.yml` mounts `/volume1/docker/tandoor/data/mediafiles:/media:ro` and the `recipes.kamaka.tech` proxy host includes the custom Nginx configuration:
```nginx
location /media/ {
    root /;
}
```

### 6.4 External Jellyfin Security Hardening (`jellyfin.kamaka.tech`)

#### Container & Reverse Proxy Hardening (Automated in Repo)
- `jellyfin/compose.yml` runs Jellyfin as non-root (`user: "1000:100"`), drops all Linux capabilities (`cap_drop: [ALL]`), enforces `no-new-privileges:true`, removes direct HTTP/HTTPS host ports (`8020`/`8021`), and mounts `/volume1/media:/data/media:ro` read-only.
- The NPM proxy host (`proxy_host/3.conf` for `jellyfin.kamaka.tech`) enables Force SSL, HTTP/2, HSTS, Block Exploits, **WebSockets Support** (`allow_websocket_upgrade=1`), disables proxy buffering (`proxy_buffering off;`), sets security and real-IP headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `X-Robots-Tag`, `CF-Connecting-IP`), and blocks external access to `/swagger`, `/api-docs`, and `/metrics`.

#### Jellyfin Application Settings (One-Time Manual UI Check)
In **Jellyfin Dashboard -> Networking** and **Dashboard -> Users**:
1. **Known Proxies**: Set `Known Proxies` to `192.168.255.0/24` (or NPM's `homelab` container hostname/IP `nginx`) and restart Jellyfin so Jellyfin logs and rate-limits real external client IPs instead of NPM's bridge IP.
2. **Disable Remote Admin Login**: Select your administrative user -> Profile -> uncheck **Allow remote connections to this server** (use a separate non-admin user account for remote playback).
3. **Hide Users & Enable Lockout**: Check **Hide this user from login screens on remote devices** for all users, and set **Maximum invalid login attempts before user is locked out** (e.g., `3` or `5`).

### 6.5 UGREEN NAS `GODEBUG=tlskyber=0` Remediation (Go 1.23+ & Antigravity Remote Fix)
UGREEN NAS OS sets `GODEBUG=tlskyber=0` in `/etc/profile.d/go.sh` and `/etc/systemd/system.conf`, which causes Go 1.23+ binaries (including the Antigravity remote server) to panic on startup because the legacy `tlskyber` flag was removed in Go 1.23.

`sudo ./homelab.sh setup` automatically checks and remediates this on every run. To run the fix manually after a UGREEN firmware update:
```bash
sudo sed -i 's/^[[:space:]]*export GODEBUG=tlskyber=0/# export GODEBUG=tlskyber=0/' /etc/profile.d/go.sh
sudo sed -i 's/^[[:space:]]*DefaultEnvironment="GODEBUG=tlskyber=0"/# DefaultEnvironment="GODEBUG=tlskyber=0"/' /etc/systemd/system.conf
sudo systemctl unset-environment GODEBUG
systemctl --user unset-environment GODEBUG || true
sudo systemctl daemon-reexec
```
