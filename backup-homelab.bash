#!/usr/bin/env bash
# ==============================================================================
# Script Name: backup-homelab.bash
# Description:
#   Backwards-compatible wrapper script for creating a timestamped homelab
#   configuration backup archive.
#
# Purpose and Operation:
#   Delegates directly to './homelab.sh backup', preserving compatibility with
#   any existing cron jobs, user habits, or external scripts that invoke
#   'backup-homelab.bash' directly.
#
# Usage:
#   ./backup-homelab.bash
# ==============================================================================

set -euo pipefail

# Resolve the directory containing this script and replace the current process
# image ('exec') with 'homelab.sh backup', forwarding any CLI arguments.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/homelab.sh" backup "$@"
