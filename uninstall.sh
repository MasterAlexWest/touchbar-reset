#!/bin/bash
#
# uninstall.sh — removes the Touch Bar lid-reset LaunchDaemon.
# Run with:  sudo bash uninstall.sh
#
set -euo pipefail

LABEL="design.westerlund.touchbar-reset"
SCRIPT_DST="/usr/local/bin/touchbar-reset-watcher.sh"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo bash uninstall.sh" >&2
  exit 1
fi

launchctl bootout system "$PLIST_DST" 2>/dev/null || true
rm -f "$PLIST_DST" "$SCRIPT_DST" \
      /var/log/touchbar-reset.log /var/log/touchbar-reset.err.log \
      /usr/local/var/touchbar-reset.paused
echo "Removed Touch Bar reset daemon, watcher script, logs, and pause marker."
