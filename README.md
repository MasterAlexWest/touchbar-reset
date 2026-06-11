# touchbar-reset

A tiny macOS background service that restarts the Touch Bar whenever you
open your MacBook lid or wake it from sleep — fixing the common bug where
the Touch Bar goes blank after the laptop has been closed (especially when
undocking from an external display).

Tested on a MacBook Pro (M1, 2020) running macOS 15 (Sequoia).

## How it works

A small `launchd` daemon runs a shell watcher that polls the lid state
(`AppleClamshellState` from the IORegistry) every few seconds. It triggers a
Touch Bar restart on two events:

1. **Lid opened while awake** — e.g. clamshell mode with an external display,
   detected as a `closed → open` transition.
2. **Wake from sleep** — closing the lid usually sleeps the Mac, which freezes
   the watcher process. A poll cycle that takes far longer than its interval is
   a reliable "just woke up" signal, with no extra dependencies.

On either trigger it runs `killall TouchBarServer` and `killall ControlStrip`,
and `launchd` immediately respawns them, so the Touch Bar reinitialises.

Because `TouchBarServer` runs as **root**, the watcher must run as a root
**LaunchDaemon** — hence the one-time `sudo` at install. After that it runs
automatically at every boot with no further prompts.

## Install

```bash
sudo bash install.sh
```

## Uninstall

```bash
sudo bash uninstall.sh
```

## Activity log

The watcher logs lid changes and resets to `/var/log/touchbar-reset.log`
(auto-trimmed to the newest 500 lines):

```bash
cat /var/log/touchbar-reset.log
```

## Configuration

Edit the values at the top of `touchbar-reset-watcher.sh`, then re-run
`sudo bash install.sh`:

| Variable | Default | Meaning |
|----------|---------|---------|
| `INTERVAL` | `5` | Seconds between lid-state checks |
| `WAKE_GAP` | `12` | A poll cycle longer than this means the Mac was asleep |

## Files

| File | Role |
|------|------|
| `touchbar-reset-watcher.sh` | The watcher loop (installed to `/usr/local/bin`) |
| `design.westerlund.touchbar-reset.plist` | LaunchDaemon definition (installed to `/Library/LaunchDaemons`) |
| `install.sh` / `uninstall.sh` | Install / remove the daemon |

## License

MIT — see [LICENSE](LICENSE).
