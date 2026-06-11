#!/bin/bash
#
# install.sh — installs the Touch Bar lid-reset LaunchDaemon.
# Run with:  sudo bash install.sh
#
set -euo pipefail

LABEL="design.westerlund.touchbar-reset"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DST="/usr/local/bin/touchbar-reset-watcher.sh"
CMD_LINK="/usr/local/bin/touchbar-reset"
PLIST_DST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo bash install.sh" >&2
  exit 1
fi

echo "Installing watcher script -> $SCRIPT_DST"
mkdir -p /usr/local/bin
cp "$SRC_DIR/touchbar-reset-watcher.sh" "$SCRIPT_DST"
chown root:wheel "$SCRIPT_DST"
chmod 755 "$SCRIPT_DST"

echo "Installing command symlink -> $CMD_LINK"
ln -sfh "$SCRIPT_DST" "$CMD_LINK"

echo "Installing LaunchDaemon -> $PLIST_DST"
cp "$SRC_DIR/${LABEL}.plist" "$PLIST_DST"
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

# Reload cleanly if it was already installed.
launchctl bootout system "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DST"
launchctl enable "system/${LABEL}"

echo
echo "Done. Installed $("$SCRIPT_DST" --version)."
echo "The watcher is running and will start on every boot."
echo "Control it with the 'touchbar-reset' command (try: touchbar-reset --status)."
echo "Test it: close the lid, wait a few seconds, reopen — the Touch Bar should refresh."
echo "Logs:    log show --predicate 'eventMessage CONTAINS \"touchbar-reset\"' --last 1h"
