# ArchAlarm '99

```
 █████╗ ██████╗  ██████╗██╗  ██╗ █████╗ ██╗      █████╗ ██████╗ ███╗   ███╗
██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗██║     ██╔══██╗██╔══██╗████╗ ████║
███████║██████╔╝██║     ███████║███████║██║     ███████║██████╔╝██╔████╔██║
██╔══██║██╔══██╗██║     ██╔══██║██╔══██║██║     ██╔══██║██╔══██╗██║╚██╔╝██║
██║  ██║██║  ██║╚██████╗██║  ██║██║  ██║███████╗██║  ██║██║  ██║██║ ╚═╝ ██║
╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝
                                                                    '99
```

A real `nftables` firewall for your Linux box, wearing the skin of a
late-90s desktop security suite. Think ZoneAlarm and BlackICE, if they'd
been built for Hyprland instead of Windows 98: a green-on-black panel that
lives in your [Omarchy](https://omarchy.org/) bar, a live feed of blocked
connection attempts scrolling past digital rain, a threat meter that goes
from calm to full dial-up-modem panic, and a one-click BAN hammer for
anything that knocks on a port it wasn't invited to.

It is also, underneath the theatrics, an actual firewall: one isolated
`nftables` table, inbound-only, that never touches your outbound traffic —
browsing, VPNs, dev servers, downloads all keep working exactly as before.
ARM it, and unsolicited inbound connections get logged and dropped. DISARM
it, and it's like it was never there.

![ArchAlarm panel](docs/screenshot.png)

## Install

Requires [Omarchy](https://omarchy.org/) (Hyprland + Quickshell) and
`nftables`.

```bash
git clone https://github.com/xer0adon1s/omarchy-archalarm99.git ~/omarchy-archalarm99
cd ~/omarchy-archalarm99
./install.sh
```

The installer symlinks the CLI, daemon, plugin, and systemd unit into the
standard Omarchy locations — it doesn't copy anything, so `git pull` in this
folder is all it ever takes to update. It's also how the in-app updater
works (see below). Follow the two next-steps it prints (add the bar widget,
optionally set up passwordless toggling) and you're armed.

## What it does

- **ARM/DISARM** a single isolated `inet archalarm` nftables table from the
  bar — no other firewall config on the system is touched. **Always starts
  disarmed**: status is cross-checked against whether the monitor daemon is
  actually running, so a stale "enabled" flag left over from a reboot or
  crash never shows as armed.
- **Inbound-only.** There is no output/forward chain. Nothing you initiate —
  browsing, a VPN client, an HTB/THM lab, a sync tool — is ever filtered.
- **Stealth or Reject** response mode, switchable live from the panel.
- **Banlist and whitelist**, both live-editable from the panel or CLI. Trust
  always overrides a ban. Banning is permanent and total: every existing
  feed/offender entry for that IP is purged (not hidden — gone), and any
  further traffic from it produces no entry, no notification, no counter
  increment, ever again.
- **Known-safe filter** (on by default): structurally allow-lists
  multicast/broadcast traffic (mDNS, SSDP, DHCP discovery) instead of
  logging it as an intrusion — this is what stops a device's own network
  chatter from looking like an attack on itself.
- **Reverse DNS** on blocked IPs, resolved in the background.
- **AI trace**: click `[TRACE]` on any entry for a plain-English read on
  what a blocked IP actually is (reverse DNS + WHOIS piped through
  `claude -p`). Each result is kept (last 20) so it can show up in an
  incident report later.
- **Scan pattern labeling**: the daemon tags a new blocked event `PSCAN`
  when the same source hits 3+ different ports within 30s, or `MSCAN`
  when 3+ different sources hit the same port within 30s — shown right in
  the live feed instead of a generic entry, so an actual scan reads
  differently from one stray connection attempt.
- **Incident report export**: click `[EXPORT INCIDENT REPORT]` to dump the
  current session — blocked events (with any scan-pattern tags), top
  offenders, banlist, whitelist, and recent AI traces — to a timestamped
  text file under `~/.local/state/omarchy/archalarm/reports/`.
- Expandable **socket/port/top-offenders** views, a live feed with a digital
  rain idle animation, desktop notifications, and a **theme picker** (plus
  matching the live Omarchy system theme).
- **Passwordless toggle** available via a sudoers rule scoped to exactly one
  script — `omarchy-archalarm setup-sudo` sets it up for you.
- **In-app updater**: checks this repo on GitHub once per boot and at most
  once every 24h, and shows a small `⇪ UPDATE (vX.Y.Z)` badge next to the
  version number when a newer tagged release is out. Click it to fetch and
  stage the new worktree, then activate it on the next shell reload. The
  panel now defers `install.sh` until the explicit `[RELOAD SHELL NOW]`
  step so the live plugin path cannot be hot-reloaded mid-update. The same
  button lives permanently under Settings too.

## How it stays safe to run

- Everything lives in one isolated nftables table (`inet archalarm`). The
  privileged half of this tool only ever creates or deletes that exact
  table — it never touches `ufw`, `iptables`, or any other table on your
  system.
- There is no output or forward chain, so outbound traffic is never
  evaluated, full stop.
- Established/related connections, loopback, ICMP ping/discovery, DHCP,
  and private LAN ranges (`10/8`, `172.16/12`, `192.168/16`, link-local) are
  always allowed before anything gets logged as a drop.
- The one script that runs as root (`omarchy-archalarm-apply`) does exactly
  one thing — add/remove elements in that one table — and every IP it's
  handed is validated as IP-shaped before it ever reaches an `nft` call.
- Optional passwordless sudo is scoped to that single script's path, not
  general root access — `setup-sudo` shows you exactly what it's granting
  before it grants it.

## CLI reference

```
omarchy-archalarm on               # arm
omarchy-archalarm off              # disarm
omarchy-archalarm toggle           # flip current state
omarchy-archalarm status           # print status.json
omarchy-archalarm mode stealth     # silent drop
omarchy-archalarm mode reject      # visible refusal
omarchy-archalarm knownsafe on     # auto-allow multicast/broadcast noise (default)
omarchy-archalarm knownsafe off    # log every drop, no exceptions
omarchy-archalarm ban <ip>         # permanent block, live if armed; also untrusts <ip>
omarchy-archalarm unban <ip>
omarchy-archalarm trust <ip>       # always-allow, live if armed; also unbans <ip>
omarchy-archalarm untrust <ip>
omarchy-archalarm investigate <ip> # reverse DNS + WHOIS -> claude -p, prints assessment
omarchy-archalarm setup-sudo       # install the passwordless-toggle sudoers rule
omarchy-archalarm report           # export an incident report, prints the file path

omarchy-archalarm-update check         # check GitHub for a newer release (gated to 1/boot, 1/24h)
omarchy-archalarm-update check force   # bypass the gate and check right now
omarchy-archalarm-update install       # fetch + stage the latest tag in a worktree (no symlink swap yet)
omarchy-archalarm-update activate      # repoint live symlinks (run automatically on shell reload)
```

`investigate` requires `whois` and the `claude` CLI on `PATH`; it makes a
live Claude API call and typically takes a few seconds.

---

## Architecture

This repo *is* the install — everything under `~/.local/bin`,
`~/.config/omarchy/plugins/xer0adon1s.archalarm`, and the systemd user unit
is a symlink, but not straight into a checkout: they all point through one
fixed indirection, `~/.local/share/omarchy/archalarm-current`, which is
itself a symlink to whichever checkout is currently live. Running
`install.sh` by hand updates that checkout in place, so a manual
`git pull` is all it takes. The in-app updater does it differently: it
builds the new version in a separate `git worktree` (a sibling directory)
and, once that's fully checked out, repoints only `archalarm-current` —
nothing downstream of it changes, so an update is a single symlink move
rather than six, and the files the running shell has open never change
out from under it mid-update (see Version history for why both of those
matter). Old worktrees are left on disk rather than cleaned up — a
rounding error for a repo this size, and worth it for never risking the
one currently in use.

```
omarchy-archalarm99/
├── install.sh          # symlinks everything below into place
├── bin/
│   ├── omarchy-archalarm           # unprivileged CLI
│   ├── omarchy-archalarm-apply     # privileged: nft table/element add/remove
│   ├── omarchy-archalarm-monitor   # unprivileged daemon: tails kernel log + ss
│   └── omarchy-archalarm-update    # unprivileged: checks/pulls new releases
├── plugin/
│   ├── manifest.json    # Omarchy plugin registration
│   ├── Panel.qml         # bar icon + popup panel
│   └── Model.js          # formatting/parsing helpers
└── systemd/
    └── omarchy-archalarm-monitor.service
```

State lives outside the repo, at `~/.local/state/omarchy/archalarm/`:
`status.json` (polled by the panel every 1.5s), `banned.txt`, `trusted.txt`,
`mode`, `knownsafe`, `panel-settings.json`, `update.json`, `last-boot-id`,
`traces.jsonl` (last 20 AI trace results), `reports/` (exported incident
reports), plus `~/.local/share/omarchy/archalarm-current` — the single
symlink every live path resolves through (see Architecture above).

**Privilege boundary:** `omarchy-archalarm-apply` is the only script that
runs as root (`sudo -n`, falling back to a `pkexec` prompt), and it only
ever touches the `inet archalarm` table. The panel is display-only — it
shells out to `omarchy-archalarm` for every action.

## What gets blocked

Applied by `omarchy-archalarm-apply on <stealth|reject> <banfile> <trustfile> <knownsafe>`:

- Established/related connections and loopback are always allowed.
- Whitelisted IPs are accepted next — trust overrides a stale or
  contradictory ban.
- Banned IPs are dropped before any other rule is checked.
- If the known-safe filter is on: traffic from `0.0.0.0` and anything
  addressed to a broadcast (`255.255.255.255`) or multicast
  (`224.0.0.0/4`, `ff00::/8`) destination is allowed.
- ICMP ping/discovery and DHCP client traffic are allowed.
- Private LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
  link-local) are allowed.
- Everything else new and inbound is logged (`ARCHALARM-DROP:` kernel
  prefix) and dropped or rejected depending on mode.
- There is no output/forward chain — outbound traffic is never evaluated.

## Version history

- **1.6.2** — Release-sync bump to keep the plugin, daemon, status output,
  and GitHub tag all reporting the same `1.6.2` version after the `1.6.1`
  ID rename. No functional changes beyond the version bookkeeping itself.
- **1.6.1** — Renamed the plugin ID and author from `alexander.archalarm`
  to `xer0adon1s.archalarm` so the identity baked into the repo matches the
  public GitHub handle rather than a first name. Purely a namespace/branding
  change — the ID was never tied to any real system username and works the
  same on anyone's machine either way. `install.sh` cleans up the old
  symlink automatically; if your `shell.json` bar layout still references
  the old ID, it prints a one-time note telling you to update it.
- **1.6** — Version label now follows the live monitor (`status.version`)
  instead of the QML build's compiled-in string, so the header updates right
  after `[RELOAD SHELL NOW]` without a second manual shell restart.
  `update.json`'s `currentVersion` is fixed to reflect the just-activated
  release instead of the pre-activate one. See `AGENT_CHANGELOG.md`.
- **1.5.23** — Deferred update activation (fixes first-click bar flicker).
  Monitor journal hardening: startup health check, `journalOk` in
  status.json, panel warning when the live feed is offline, optional
  `systemd-journal` group documented in `install.sh`. See
  `AGENT_CHANGELOG.md`.
- **1.5.1 – 1.5.22** — Diagnostic pass, GitHub repo, and an in-app
  updater — then round after round of actually using that updater and
  fixing the real bug each attempt turned up:
  - Fixed a self-heal check that never matched, missing IP validation on
    ban/trust, and an alert banner that could overflow the panel.
  - Added `omarchy-archalarm setup-sudo`, incident report export, and
    scan pattern labeling (`PSCAN`/`MSCAN` on feed entries).
  - Fixed the updater tearing down the panel mid-install, needing a
    manual restart to actually show the new version, a redundant click
    that could delete the live install, a shell restart that silently
    failed to complete, and a bar flicker on every update.
  - End state: one atomic symlink move per update, every step
    timeout-bounded, safe to click more than once, and the restart
    survives the bar restarting around it — each verified with a real
    update, not just read back.
- **1.5** — Known-safe filter for multicast/broadcast noise (fewer false
  positives). Banning now purges past feed entries too, not just future
  ones. Fixed traffic-light colors independent of theme.
- **1.4** — Whitelist added. Always starts disarmed. Settings menu (⚙)
  with a theme picker.
- **1.3** — Expandable socket list. AI-backed IP trace (`investigate`).
  Banlist collapsed by default.
- **1.2** — Idle animation in the live feed panel.
- **1.1** — Renamed RetroWall '95 → ArchAlarm '99. Added ban list, reverse
  DNS, stealth/reject mode, passwordless sudoers option.
- **1.0** — Initial release: ARM/DISARM, live blocked-connection feed, threat
  meter, inbound-only nftables backend.

## Known issues

- None open at v1.6. The first-click update banner flicker was fixed by
  deferring `install.sh` (symlink activation) until shell reload, and the
  header now updates on its own once the monitor restarts — see
  `AGENT_CHANGELOG.md`.

## Future ideas (not implemented)

- **Session summary on disarm** — a toast on DISARM: block count, unique IPs,
  top offender.
- **Auto-arm at login** — opt-in setting; stays off by default.

## License

MIT — see [LICENSE](LICENSE).
