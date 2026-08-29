# Agent changelog (Cursor build notes)

This file is for AI coding agents (Cursor, Codex, etc.) working on this
repo. It records **why** recent changes were made, not just what changed.
Human-facing release notes stay in `README.md`.

## Rollback/testing note for Claude

The update-flow fix is the important one here: `install.sh` is intentionally
not run during the staged update step, and activation is deferred until shell
reload. That avoids the first-click flicker caused by hot-reloading a plugin
path while the daemon is still using the old checkout.

For the manual rollback test: when you need to force the updater to think a
newer release exists, temporarily set the "running" version one patch lower
than the latest tagged release you want to test against (for example, leave
this checkout at `1.5.23` while the remote tag is `1.5.22` or vice versa),
then revert the version strings back before leaving the repo in its normal
release state. Do not leave the repo in a deliberately downgraded version
unless the test specifically requires it.

## 2026-08-29 — v1.5.23 (journal feed + update flicker)

### Context

Two issues were investigated read-only, then fixed in one pass:

1. **`journalctl -k` reliability** — the monitor tails kernel logs for
   `ARCHALARM-DROP:` lines. On some distros only `systemd-journal` members
   can read a persistent journal; failures were silent (`stderr=DEVNULL`)
   and the feed looked armed-but-empty.

2. **First-click update banner flicker** — `omarchy-archalarm-update install`
   ran `install.sh` immediately after building a git worktree. That repoints
   `~/.local/share/omarchy/archalarm-current`, which changes the resolved
   plugin path Omarchy watches → hot-reload kills the bar mid-animation while
   the update `Process` is still a child of Quickshell.

### Fix 1: Journal / live feed

| File | Change |
|------|--------|
| `systemd/omarchy-archalarm-monitor.service` | *(no unit change — user systemd cannot add `SupplementaryGroups` the user is not already in; causes exit 216/GROUP)* |
| `install.sh` | Optional post-step: `sudo usermod -aG systemd-journal $USER` when feed is empty |
| `bin/omarchy-archalarm-monitor` | Startup `journal_accessible()` probe; `journalOk` + `journalError` in `status.json`; append `journal.log` instead of discarding stderr; if journal unavailable at start, poll-only loop (no restart storm) |
| `bin/omarchy-archalarm` | `write_off_status()` includes `journalOk` / `journalError` |
| `plugin/Model.js` | Parse defaults for `journalOk`, `journalError` |
| `plugin/Panel.qml` | Warning when armed and `!journalOk` |

**Agent note:** Firewall (`nft`) is independent of the feed. A missing journal
only disables notifications/counters/events — not blocking.

### Fix 2: Deferred update activation

**Two-phase update:**

```
install  → fetch + git worktree add → pending-activate.json (NO install.sh)
activate → install.sh + daemon-reload + monitor restart → clear pending
```

| File | Change |
|------|--------|
| `bin/omarchy-archalarm-update` | `install` only stages; new `activate` subcommand runs `install.sh`; `update.json` gains `pendingActivate` / `pendingVersion` |
| `plugin/Panel.qml` | `[RELOAD SHELL NOW]` runs `omarchy-archalarm-update activate` then `omarchy restart shell` (both under `setsid`); staged banner + copy updates |
| `plugin/Model.js` | `pendingActivate`, `pendingVersion` in update info |

**State files** (under `~/.local/state/omarchy/archalarm/`):

- `pending-activate.json` — `{"path": "<worktree>", "version": "x.y.z", "stagedAt": <epoch>}`
- `activate.log` — output from `activate` on reload
- `journal.log` — `journalctl` stderr from the monitor

**Agent note:** Do not call `install.sh` from `cmd_install` again — that
reintroduces the flicker. Activation must stay tied to shell reload (or an
explicit `omarchy-archalarm-update activate`).

### Version bump

`1.5.22` → `1.5.23` in: `plugin/manifest.json`, `Panel.qml` (`appVersion`),
`Model.js`, `bin/omarchy-archalarm-monitor`, `bin/omarchy-archalarm`
(`write_off_status`). Keep these in sync on future releases.

### Testing checklist for agents

```bash
# Syntax
bash -n bin/omarchy-archalarm*
python3 -m py_compile bin/omarchy-archalarm-monitor

# Re-link live install after editing main checkout
./install.sh
systemctl --user daemon-reload
systemctl --user restart omarchy-archalarm-monitor.service   # if armed

# Journal probe (should succeed on Arch with SupplementaryGroups)
journalctl -k -n 1 --no-pager -o cat

# Update flow (needs a newer tag on origin to fully exercise)
omarchy-archalarm-update install    # should end at STEP:STAGE, write pending-activate.json
omarchy-archalarm-update activate   # or use panel [RELOAD SHELL NOW]
```

### Out of scope (not changed here)

- UFW vs ArchAlarm double-firewall confusion (UFW logs ≠ `ARCHALARM-DROP:`)
- IPv6 ban/trust sets (still `ipv4_addr` only)
- Version single-source-of-truth refactor
