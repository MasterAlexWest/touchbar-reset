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
# Runs as a root LaunchDaemon. See install.sh.

VERSION="1.0.0"

case "$1" in
  --version|-v)
    echo "touchbar-reset-watcher $VERSION"
    exit 0
    ;;
esac

INTERVAL=5    # seconds between checks (lid stays closed minutes-to-hours, so this is plenty)
WAKE_GAP=12   # a poll cycle longer than this means the Mac was asleep
LOG=/var/log/touchbar-reset.log   # plain timestamped activity log
LOG_MAX_LINES=500                 # keep the newest entries, trim the rest

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

log_msg "watcher v${VERSION} started (INTERVAL=${INTERVAL}s WAKE_GAP=${WAKE_GAP}s)"
last="$(get_clamshell)"
log_msg "initial clamshell=[$last]"

while true; do
  before=$(/bin/date +%s)
  /bin/sleep "$INTERVAL"
  after=$(/bin/date +%s)
  current="$(get_clamshell)"
  gap=$((after - before))

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
