#!/usr/bin/env bash
# ==============================================================================
# Script: 01-auto-import.sh
# Purpose: Initialize automated Calibre library ingestion inside Calibre-Web container
# Architecture: S6-overlay custom container init script (/custom-cont-init.d)
# Context: Runs on container startup as root to provision the periodic auto-import
#          cron job and trigger initial library ingestion from /import into /books.
# Usage: Executed automatically by /etc/s6-overlay/s6-rc.d/init-custom-files/run
# Preconditions: LinuxServer S6-overlay container with universal-calibre mod installed
# ==============================================================================
set -euo pipefail

AUTO_IMPORT_BIN="/usr/local/bin/calibre-auto-import.sh"

echo "[custom-init] Initializing Calibre automated book ingestion..."

# Write automated import worker script
cat <<'EOF' > "${AUTO_IMPORT_BIN}"
#!/usr/bin/env bash
# ==============================================================================
# Script: calibre-auto-import.sh
# Purpose: Periodically ingest pending ebooks from /import into Calibre library
# ==============================================================================
set -euo pipefail

export CALIBRE_CONFIG_DIRECTORY="/config/calibre-config"
mkdir -p "${CALIBRE_CONFIG_DIRECTORY}"

# Verify /import directory has candidate files
if [ -d /import ] && compgen -G "/import/*" > /dev/null; then
    /usr/bin/calibredb add -r /import/ \
        --library-path /books \
        --automerge overwrite \
        >> /config/auto-import.log 2>&1 || true
fi
EOF

chmod +x "${AUTO_IMPORT_BIN}"
lsiown abc:users "${AUTO_IMPORT_BIN}"

# Configure crontab for non-root container user (abc) to run every 5 minutes
echo "*/5 * * * * ${AUTO_IMPORT_BIN}" | crontab -u abc -

# Execute immediate initial sync pass on startup as user abc
s6-setuidgid abc "${AUTO_IMPORT_BIN}" || true

echo "[custom-init] Automated Calibre library ingestion configured (every 5 minutes)."
