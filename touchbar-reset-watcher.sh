#!/bin/bash
#
# touchbar-reset-watcher.sh
# Restarts the Touch Bar whenever the MacBook wakes / the lid is opened.
#
# Two triggers, so both real-world cases are covered:
#   1. Wake from sleep — closing the lid usually sleeps the Mac. While
#      asleep this process is frozen, so a poll cycle that should take
#      INTERVAL seconds instead shows a large wall-clock gap. That gap
#      is a reliable "just woke up" signal (no extra dependencies).
#   2. Lid closed -> open while awake — e.g. clamshell mode with an
#      external display, where the Mac never sleeps. Caught by the
#      AppleClamshellState transition.
#
# On either trigger it restarts TouchBarServer (root-owned) and
# ControlStrip so the Touch Bar reinitialises instead of staying blank.
#
# With no argument it runs as the watcher loop (how launchd starts it).
# Run with --help to see the available flags.
#
# Runs as a root LaunchDaemon. See install.sh.

VERSION="1.1.0"

# --- Configuration --------------------------------------------------------
INTERVAL=5    # seconds between checks (lid stays closed minutes-to-hours, so this is plenty)
WAKE_GAP=12   # a poll cycle longer than this means the Mac was asleep
LOG_MAX_LINES=500                              # keep the newest entries, trim the rest

# --- Paths (absolute, so the flags work from anywhere) --------------------
LABEL="design.westerlund.touchbar-reset"
SCRIPT_PATH="/usr/local/bin/touchbar-reset-watcher.sh"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"
LOG="/var/log/touchbar-reset.log"              # plain timestamped activity log
ERR_LOG="/var/log/touchbar-reset.err.log"      # launchd stderr capture
PAUSE_FILE="/usr/local/var/touchbar-reset.paused"   # present == watcher is paused

# --- Helpers --------------------------------------------------------------
log_msg() {
  printf '%s  %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"
  if [ "$(/usr/bin/wc -l < "$LOG")" -gt "$LOG_MAX_LINES" ]; then
    /usr/bin/tail -n "$LOG_MAX_LINES" "$LOG" > "${LOG}.tmp" && /bin/mv "${LOG}.tmp" "$LOG"
  fi
}

get_clamshell() {
  # Prints "Yes" (lid closed) or "No" (lid open); empty if unavailable.
  /usr/sbin/ioreg -r -k AppleClamshellState -d 4 2>/dev/null \
    | /usr/bin/awk -F'= ' '/"AppleClamshellState"/ {gsub(/[" ]/,"",$2); print $2; exit}'
}

reset_touchbar() {
  /usr/bin/killall TouchBarServer 2>/dev/null
  /usr/bin/killall ControlStrip   2>/dev/null
  log_msg "RESET TouchBarServer + ControlStrip (trigger: $1)"
}

require_root() {
  if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    echo "This action needs root. Re-run: sudo $SCRIPT_PATH $1" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
touchbar-reset-watcher $VERSION — restart the Touch Bar on lid-open / wake

Usage: touchbar-reset-watcher.sh [flag]

With no flag it runs the watcher loop (this is how launchd starts it).

Flags:
  --once         Reset the Touch Bar now and exit.              (needs sudo)
  --pause        Stop resetting until --resume; daemon stays loaded. (needs sudo)
  --resume       Resume after a --pause.                        (needs sudo)
  --status       Show daemon state, pause state, lid state, recent log.
  --uninstall    Remove the daemon, script, logs, and pause marker. (needs sudo)
  --version, -v  Print the version.
  --help, -h     Show this help.
EOF
}

# --- Flag dispatch (no flag falls through to the watcher loop) ------------
case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --version|-v)
    echo "touchbar-reset-watcher $VERSION"
    exit 0
    ;;
  --once)
    require_root --once
    reset_touchbar "manual (--once)"
    echo "Touch Bar reset."
    exit 0
    ;;
  --pause)
    require_root --pause
    /bin/mkdir -p "$(/usr/bin/dirname "$PAUSE_FILE")"
    /usr/bin/touch "$PAUSE_FILE"
    log_msg "PAUSED via --pause"
    echo "Paused. The watcher will stop resetting within ${INTERVAL}s."
    echo "Resume with: sudo $SCRIPT_PATH --resume"
    exit 0
    ;;
  --resume)
    require_root --resume
    /bin/rm -f "$PAUSE_FILE"
    log_msg "RESUMED via --resume"
    echo "Resumed. The watcher is active again."
    exit 0
    ;;
  --status)
    echo "touchbar-reset-watcher $VERSION"
    if /usr/bin/pgrep -f 'touchbar-reset-watcher\.sh$' >/dev/null 2>&1; then
      echo "daemon:  running (pid $(/usr/bin/pgrep -f 'touchbar-reset-watcher\.sh$' | /usr/bin/tr '\n' ' '))"
    else
      echo "daemon:  not running"
    fi
    if [ -e "$PAUSE_FILE" ]; then echo "state:   PAUSED (resume with: sudo $SCRIPT_PATH --resume)"; else echo "state:   active"; fi
    echo "lid:     $(get_clamshell)  (Yes = closed, No = open)"
    echo "--- last 5 log lines ($LOG) ---"
    /usr/bin/tail -n 5 "$LOG" 2>/dev/null || echo "(no log yet)"
    exit 0
    ;;
  --uninstall)
    require_root --uninstall
    /bin/launchctl bootout "system/$LABEL" 2>/dev/null
    /bin/rm -f "$PLIST_PATH" "$SCRIPT_PATH" "$PAUSE_FILE" "$LOG" "${LOG}.tmp" "$ERR_LOG"
    echo "Uninstalled: daemon stopped; script, logs, and pause marker removed."
    exit 0
    ;;
  "")
    : # no flag — run the watcher loop below
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage
    exit 1
    ;;
esac

# --- Watcher loop ---------------------------------------------------------
log_msg "watcher v${VERSION} started (INTERVAL=${INTERVAL}s WAKE_GAP=${WAKE_GAP}s)"
last="$(get_clamshell)"
log_msg "initial clamshell=[$last]"
[ -e "$PAUSE_FILE" ] && log_msg "starting PAUSED (resume with --resume)"

while true; do
  before=$(/bin/date +%s)
  /bin/sleep "$INTERVAL"
  after=$(/bin/date +%s)
  current="$(get_clamshell)"
  gap=$((after - before))

  # While paused, keep tracking lid state but never reset.
  if [ -e "$PAUSE_FILE" ]; then
    [ -n "$current" ] && last="$current"
    continue
  fi

  # Trace every state change so we can see exactly what the daemon reads.
  if [ "$current" != "$last" ]; then
    log_msg "clamshell change [$last] -> [$current] (gap=${gap}s)"
  fi

  if [ "$gap" -gt "$WAKE_GAP" ]; then
    # The Mac was asleep and just resumed. Reset if the lid is now open.
    if [ "$current" != "Yes" ]; then
      reset_touchbar "wake-from-sleep"
    fi
  elif [ "$last" = "Yes" ] && [ "$current" = "No" ]; then
    # Lid opened while the Mac stayed awake (e.g. clamshell mode).
    reset_touchbar "lid-open"
  fi

  # Remember the last good reading; ignore empty/unknown samples.
  [ -n "$current" ] && last="$current"
done
