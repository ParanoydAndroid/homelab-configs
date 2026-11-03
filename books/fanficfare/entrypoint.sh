#!/bin/sh
set -e

POLL_INTERVAL=${POLL_INTERVAL:-14400}

echo "[royalroad-sync] Starting FanFicFare background worker..."
echo "[royalroad-sync] Monitoring /config/stories.txt every ${POLL_INTERVAL} seconds."

# Seed default personal.ini with flaresolverr proxy configuration if missing
if [ ! -f /config/personal.ini ]; then
  echo "[royalroad-sync] Initializing default /config/personal.ini with FlareSolverr proxy..."
  cat <<'EOF' > /config/personal.ini
[defaults]
use_flaresolverr_proxy: true
flaresolverr_proxy_address: flaresolverr
flaresolverr_proxy_port: 8191
flaresolverr_proxy_protocol: http
flaresolverr_proxy_timeout: 60000
slow_down_sleep_time: 2
EOF
fi

while true; do
  if [ -s /config/stories.txt ]; then
    echo "[royalroad-sync] Processing stories at $(date)..."
    cd /import
    if [ -f /config/personal.ini ]; then
      fanficfare -u -i /config/stories.txt --config /config/personal.ini --non-interactive || echo "[royalroad-sync] Warning: fanficfare sync encountered non-fatal errors"
    else
      fanficfare -u -i /config/stories.txt --non-interactive || echo "[royalroad-sync] Warning: fanficfare sync encountered non-fatal errors"
    fi
  else
    echo "[royalroad-sync] /config/stories.txt is empty or missing. Waiting for story URLs..."
  fi

  sleep "${POLL_INTERVAL}" &
  wait $!
done
