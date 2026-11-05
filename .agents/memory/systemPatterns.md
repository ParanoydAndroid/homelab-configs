# System Patterns & Architecture Idioms

## Architectural Invariants
- **Dockge Compatibility**: Repository root contains only stack folders with `compose.yml` and an optional `.env`. Non-stack entities are hidden (`.` prefix). Root convenience symlinks (`AGENTS.md`, `manage.sh`, etc.) are permitted as Dockge indexes only directories. Dockge's own compose is deployed to `${DOCKGE_DIR}/compose.yml` above stacks.
- **Network Exposure Model**: Backend services run on the user-defined `homelab` Docker bridge network (`192.168.255.0/24`). Reverse proxy (Caddy) bridges LAN (`external_npm` macvlan `192.168.0.0/24`, static IP `192.168.0.4`) and `homelab` bridge. Direct host ports are closed except for non-HTTP/emergency fallback.
- **Secrets & Environment Variable Management**: Two-tier configuration model. Root `.env.example` syncs global host/network variables to stack `.env` files; per-stack `.env.example` defines secrets with blank defaults. Docker Compose enforces required variables with strict `${VAR:?Error message}` assertion syntax. Shell scripts use `${VAR}` parameter expansion.
- **Least-Privilege Container Execution**: Standard `1000:100` (`PUID:PGID`) execution, `security_opt: [no-new-privileges:true]`, `cap_drop: [ALL]`. Media mounts read-only (`:ro`) where possible.
- **Host Volume Standardization**: Persistent data isolated by container under `${DOCKER_DATA_DIR}/<service>/data/...` and media under `${MEDIA_DIR}`. Restic snapshot backups with zero-downtime database staging.
- **TRaSH Guides Adherence**: Media management baseline, NVMe scratch buffering (`/incomplete`), Btrfs No-CoW flags (`chattr +C`), RAM cache, anti-starvation queues.

## Repository & Agent Patterns
- **Multi-Agent Entrypoint Aliasing**: `AGENTS.md` is the canonical root file; `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `agent.md`, and `.agents/rules/project-conventions.md` symlink to it.
- **Memory Bank Lifecycle Synchronization**: Sessions must begin by reading memory bank files; task initiation updates `activeContext.md`; completion updates `activeContext.md` and `progress.md`.
- **Modular Scoped Rules**: Language and format conventions are glob-triggered (`containers-and-env.md`, `shell-scripting.md`) rather than combined into a single monolith.
- **Operational Dispatcher**: `./manage.sh` orchestrates `setup`, `startup`, `backup`, `snapshots`, `restore`, `test`, `audit`, and `hook` with zero external dependencies.
- **Protected Mainline**: Direct commits and pushes to `main` are guarded by git hooks and CI; feature branches permit unrestricted intermediate commits.
- **Agile Trunk Dual-Tagging**: Semantic versioning (`vMAJOR.MINOR.PATCH`) for functional milestones paired with Calendar Versioning (`YYYY.M.D.N`) for continuous trunk deployments.
