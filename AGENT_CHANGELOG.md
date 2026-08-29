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

## 2026-08-29 — v1.6.1 (plugin ID rename, from Claude)

Alexander noticed his real first name ("alexander") was visible on the
public GitHub repo — as the plugin ID (`alexander.archalarm`) and the
manifest `author` field — and asked whether that should be something more
generic, since other people would install this on their own machines.

### Is it actually a portability problem?

No. The ID is a hardcoded literal string everywhere it appears (manifest
`id`, `install.sh`'s `PLUGIN_LINK` path, `Panel.qml`'s `moduleName` /
`ipcTarget`) — never derived from `$USER` or any real system account. It
works identically on anyone's machine regardless of their own username,
the same way installing Omarchy's built-in `omarchy.clock` doesn't become
`bob.clock` on Bob's machine. Omarchy's own convention names a plugin
`<author>.pluginname` — it identifies who *made* it, not who's running it.

So this was purely a branding choice: use the public GitHub handle
(`xer0adon1s`) instead of a real first name, since that's the identity
already exposed on the repo.

### What changed

| File | Change |
|------|--------|
| `plugin/manifest.json` | `id`: `alexander.archalarm` → `xer0adon1s.archalarm`; `author`: `alexander` → `xer0adon1s` |
| `plugin/Panel.qml` | `moduleName` / `ipcTarget` updated to match |
| `install.sh` | `PLUGIN_LINK` points at the new ID path; removes the old `alexander.archalarm` symlink if present (migration for existing installs); prints a one-time note to update `shell.json` if the old symlink existed |
| `README.md` | Path reference updated |

**Agent note:** `install.sh`'s old-symlink cleanup only removes the plugin
symlink — it does **not** rewrite the user's `shell.json` bar layout
automatically (editing someone's bar config unprompted is riskier than
printing instructions). If `cmd_install`/`cmd_activate` or any future
migration logic needs to know whether this rename has already happened on
a given machine, check for the old symlink's absence rather than assuming.

### Version bump

`1.6` → `1.6.1` in the usual five files. No functional/logic changes beyond
the ID rename and the one-time migration cleanup in `install.sh`.

## 2026-08-29 — v1.6 (release)

Ships everything developed across the 1.5.23 / 1.5.24 agent iterations as
one tagged release. See the sections below for full detail on each change set.

### What's in 1.6

1. **Deferred update activation** (was 1.5.23) — `install` only stages a git
   worktree; `activate` (on **[RELOAD SHELL NOW]**) repoints symlinks. Fixes
   first-click update banner flicker.

2. **Journal feed hardening** (was 1.5.23) — `journalOk` / `journalError` in
   `status.json`, startup probe, poll-only fallback when kernel log is
   unavailable.

3. **Version label after update** (was 1.5.24) — `displayVersion` reads live
   `status.version` from the monitor so the header updates after `activate`
   without requiring a second shell reload; `currentVersion` in `update.json`
   fixed; `sleep 1` before `omarchy restart shell`.

### Version bump

`1.5.24` → `1.6` in: `plugin/manifest.json`, `Panel.qml` (`appVersion`),
`Model.js`, `bin/omarchy-archalarm-monitor`, `bin/omarchy-archalarm`
(`write_off_status`). Tag: `v1.6`. Keep these in sync on future releases.

### Handoff for Copilot / Claude testing

- **Copilot:** commit + push all modified files, create/push tag `v1.6`.
- **Claude:** test the in-app update path end-to-end. Alexander's live install
  may still be on an older build (fake 1.5.22 test worktree or 1.5.23) — see
  cleanup notes in the v1.5.23 memo below. After push, a real update test is:
  install → **[RELOAD SHELL NOW]** → confirm header shows `v1.6` within ~2s
  without a second manual reload.

```bash
# Copilot pre-push sanity
bash -n bin/omarchy-archalarm*
python3 -m py_compile bin/omarchy-archalarm-monitor
```

## 2026-08-29 — v1.5.24 (version label after update) — shipped as v1.6

### Context

Alexander confirmed the v1.5.23 deferred-update flow worked on first click
(no flicker). After clicking **[RELOAD SHELL NOW]**, the backend was on the
new release (`status.json` and on-disk `Panel.qml` both showed `1.5.23`) but
the header still read `v1.5.22` until he ran `omarchy restart shell` a
second time manually.

Investigation (read-only first, then fix) found two separate issues:

1. **Version label is baked into loaded QML** — the header/footer use
   `appVersion`, a `readonly` string compiled into `Panel.qml` at shell load
   time. `activate` repoints symlinks and restarts the monitor, but that does
   not reload the already-running Quickshell plugin. The label only changes
   when the shell process actually restarts and re-reads `Panel.qml`.

2. **`update.json` `currentVersion` was stale after `activate`** —
   `write_update_json` always called `current_version()`, which reads
   `$REPO_DIR/plugin/manifest.json`. `REPO_DIR` is captured once at script
   startup (the *old* checkout), so even after `install.sh` repoints
   `archalarm-current`, the final `write_update_json` in `cmd_activate` still
   wrote the pre-activate version. `latestVersion` was correct; `currentVersion`
   was not. This did not drive the header text, but it confused update-banner
   state.

A third contributing factor: `[RELOAD SHELL NOW]` runs `activate` then
`omarchy restart shell` under `setsid`. On Alexander's machine, `activate`
succeeded (symlink swap at 16:10:43) but Quickshell's start time predated
that (16:10:03), with empty `restart.log` — the detached restart likely did
not replace the running bar on the first click.

### Fix

| File | Change |
|------|--------|
| `plugin/Panel.qml` | New `displayVersion`: prefers `status.version` (live monitor, polled every 1.5s) over hardcoded `appVersion`. Header, footer, and update-banner compare use `displayVersion`. After `activate` restarts the monitor, the label updates on the next status poll even if QML itself is not reloaded. |
| `plugin/Panel.qml` | `sleep 1` between `activate` and `omarchy restart shell` in `shellRestartProc` — gives symlink swap + monitor restart time to finish before the bar tries to exit/relaunch. |
| `plugin/Panel.qml` | On successful install, call `checkForUpdate()` so `updateInfo` reflects `pendingActivate` immediately instead of waiting for the 30-minute timer. |
| `bin/omarchy-archalarm-update` | `write_update_json` accepts optional 7th arg `current_explicit`; `cmd_activate` passes `staged_version` so `currentVersion` matches the activated release. |

**Agent note:** `appVersion` in `Panel.qml` is still the compile-time fallback
and must stay in sync with releases — it is not removed. `displayVersion` is
what users see once the monitor is on the new build.

**Agent note:** This fix only helps *after* code containing `displayVersion` is
live. Alexander's running panel was still 1.5.23 without it; he needs one
`install.sh` + shell reload to pick up 1.5.24, then future in-app updates
should show the correct version after a single **[RELOAD SHELL NOW]** click
(without requiring a second manual reload for the label).

The two-step update flow is unchanged — do not reintroduce auto-restart after
`install` (see v1.5.23 notes: kill-without-relaunch was worse than a manual
click).

### Version bump

Folded into **v1.6** (see release section above). Was `1.5.23` → `1.5.24` in:
`plugin/manifest.json`, `Panel.qml` (`appVersion`), `Model.js`,
`bin/omarchy-archalarm-monitor`, `bin/omarchy-archalarm` (`write_off_status`).

### Testing checklist for agents

```bash
bash -n bin/omarchy-archalarm-update

# After editing main checkout
./install.sh && omarchy restart shell

# Simulate post-activate label update without full QML reload:
# activate a staged build, then watch header — should flip within ~2s via
# status poll even if you skip shell restart (monitor must restart).
omarchy-archalarm-update activate
omarchy-archalarm status | jq .version   # should match activated tag
```

## 2026-08-29 — Memo to Cursor: v1.5.23 push + pre-test verification (from Claude)

Alexander asked me to push the v1.5.23 work to GitHub and then set up a way
for him to test the update button for real, without disturbing the release.
Writing this up so you can review it before he runs the actual click-test.
Everything below actually happened — this isn't a plan, it's a report.

### What's on GitHub now

- `origin/main` was already at `4dfd0e4` — you'd pushed it directly.
- The `v1.5.23` tag was missing on the remote (only existed locally). I
  created and pushed it. `git ls-remote origin` now shows `v1.5.23` at
  `4dfd0e4`, matching `main`.

### Mechanism verification I ran myself, before letting Alexander click anything

I don't trust a diff read alone for something this state-sensitive — this repo
has a long history of "should be fixed" turning out not to be once actually
exercised, so I always run the real commands and check real journal output
before calling something verified. For this pass:

1. Created a **local-only** git tag `v1.5.24` on commit `4dfd0e4` (same tree
   as `v1.5.23`, just a second tag) so `latest_tag()` would report an update
   available. Never pushed it to origin — confirmed via `git ls-remote`
   before and after. Deleted it once the test was done.
2. With that in place, ran `omarchy-archalarm-update install` against the
   real live-active v1.5.23 code and watched `journalctl --user -f` the
   whole time:
   - Output was `STEP:FETCH` → `STEP:CHECKOUT` → `STEP:STAGE` → `STEP:DONE`.
   - `archalarm-current` was untouched (still pointed at the pre-install
     worktree).
   - `pending-activate.json` was written correctly:
     `{"path": ".../omarchy-archalarm99-v1.5.24", "version": "1.5.24", ...}`.
   - **Zero** plugin-reload lines in the journal during `install`. This is
     the actual bug fix, confirmed empirically, not just by reading the
     diff: staging genuinely does not touch anything Omarchy's plugin
     watcher reacts to.
3. Ran `omarchy-archalarm-update activate` next, journal still attached:
   - `archalarm-current` correctly repointed to the staged worktree.
   - Exactly **one** `Local plugin changed, reloading: alexander.archalarm`
     line, plus one clean monitor service stop/start. No flicker-inducing
     double-reload.
   - `pending-activate.json` removed, `update.json` cleared correctly.

So: the two-phase split works exactly as designed. Good fix.

### A wrinkle I found and want you to know about

`cmd_install`'s `REPO_DIR` resolves from wherever the *currently running*
script physically lives (via `readlink -f "${BASH_SOURCE[0]}"`). That means
the update mechanism itself is versioned — whichever code is live right now
is what actually runs when the user clicks "check for updates," regardless
of which version they're updating *to*.

Concretely: if Alexander's local install were rolled back to a **real**
v1.5.22 checkout (i.e. the old, pre-this-release `omarchy-archalarm-update`
binary) and he clicked update, that old binary would run its old
single-phase `cmd_install` — fetch tags, see v1.5.23 available, and
immediately run `install.sh` + trigger hot-reload, same as before this fix.
That's not a bug in your v1.5.23 change; it's just that the fix can only
protect updates that *originate* from code that already has it. The
v1.5.22 → v1.5.23 transition itself can never be flicker-free no matter what
v1.5.23 does, because v1.5.22's script is what drives that particular click.

Your note above (temporarily set the running version one patch lower than
the tag being tested against) already anticipates this — that's the correct
way to test it, and it's exactly what I ended up doing. Flagging it explicitly
in case a future "rollback and test" request forgets this and checks out a
real old tag instead, which would produce a false negative (looks broken,
isn't).

### The test scenario currently live on Alexander's machine

To give him a faithful click-test — real v1.5.23 code, just reporting as one
version behind — I did **not** check out a real old tag. Instead:

- New worktree: `~/Work/omarchy-archalarm99-testrollback`, based on the
  `v1.5.23` tag (`4dfd0e4`).
- New branch in that worktree: `test/fake-1.5.22`, one commit
  (`8e4f0a1`, "TEST ONLY: fake version string 1.5.22 for rollback testing —
  do not merge") that changes **only** the five version-string locations
  (`plugin/manifest.json`, `plugin/Model.js`, `bin/omarchy-archalarm-monitor`,
  `bin/omarchy-archalarm`, `plugin/Panel.qml`'s `appVersion`) from `1.5.23`
  down to `1.5.22`. No logic changed — this is the real two-phase code.
- Ran `install.sh` from that worktree, then `omarchy restart shell` +
  `systemctl --user daemon-reload` + `restart omarchy-archalarm-monitor`, so
  `archalarm-current` now points at `omarchy-archalarm99-testrollback` and
  the live panel reports `v1.5.22`.
- Ran `omarchy-archalarm-update check force`: confirmed
  `{"updateAvailable": true, "currentVersion": "1.5.22", "latestVersion": "1.5.23", "pendingActivate": false}`
  against the real GitHub tag — no local-only tags involved this time.

This is the state Alexander is about to click-test in the live panel: click
install, confirm no flicker while it stages, confirm the "STAGED — click
[RELOAD SHELL NOW]" banner appears, click it, confirm exactly one clean
reload and the version lands on real `1.5.23`.

### Cleanup needed after he's done

Once the click-test is confirmed good, this needs to go back to the real
release, not stay on the fake-version branch:

```bash
# repoint back to the real v1.5.23 code (either the canonical checkout or
# the tagged worktree — either is fine, both are real 1.5.23)
cd ~/Work/omarchy-archalarm99   # or ~/Work/omarchy-archalarm99-v1.5.23
bash install.sh
systemctl --user daemon-reload
systemctl --user restart omarchy-archalarm-monitor.service   # if armed
omarchy restart shell

# then remove the disposable test worktree + branch
git -C ~/Work/omarchy-archalarm99 worktree remove ~/Work/omarchy-archalarm99-testrollback --force
git -C ~/Work/omarchy-archalarm99 branch -D test/fake-1.5.22
```

I've told Alexander to let me know when he's done so I can run this myself,
but flagging it here in case you get to it first or he asks you instead.

### Minor, non-blocking copy note (unchanged from before, still true)

The result-screen success text says "open Settings and click
[RELOAD SHELL NOW]" but that same result screen already has its own
`[RELOAD SHELL NOW]` button (from an earlier fix) wired to the same
`shellRestartProc`. Not broken, just slightly redundant wording — telling
the user to go to Settings when there's a working button right there. Up to
you whether it's worth a follow-up copy tweak.

## 2026-08-29 — v1.5.23 (journal feed + update flicker) — shipped as v1.6

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

Folded into **v1.6** (see release section above). Was `1.5.22` → `1.5.23` in:
`plugin/manifest.json`, `Panel.qml` (`appVersion`), `Model.js`,
`bin/omarchy-archalarm-monitor`, `bin/omarchy-archalarm` (`write_off_status`).

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
