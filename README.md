# ArchAlarm '99

```
   ▄████▄   ▄▄▄       ██▀███   ▄████▄   ██░ ██
  ▒██▀ ▀█  ▒████▄    ▓██ ▒ ██▒▒██▀ ▀█  ▓██░ ██▒
  ▒▓█    ▄ ▒██  ▀█▄  ▓██ ░▄█ ▒▒▓█    ▄ ▒██▀▀██░
  ▒▓▓▄ ▄██▒░██▄▄▄▄██ ▒██▀▀█▄  ▒▓▓▄ ▄██▒░▓█ ░██
  ▒ ▓███▀ ░ ▓█   ▓██▒░██▓ ▒██▒▒ ▓███▀ ░░▓█▒░██▓
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
  version number when a newer tagged release is out. Click it to fetch,
  check out the new tag, and re-run the installer, with a retro
  dial-up-style progress screen while it works — no manual `git pull`
  needed.

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
omarchy-archalarm-update install       # fetch + check out the latest tag, re-run install.sh
```

`investigate` requires `whois` and the `claude` CLI on `PATH`; it makes a
live Claude API call and typically takes a few seconds.

---

## Architecture

This repo *is* the install — everything under `~/.local/bin`,
`~/.config/omarchy/plugins/alexander.archalarm`, and the systemd user unit
is a symlink back into this checkout. Pull a new version and every symlinked
copy updates instantly; nothing needs re-copying.

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
reports).

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

- **1.5.5** — Two "Future ideas" shipped: incident report export
  (`[EXPORT INCIDENT REPORT]` in the panel, `omarchy-archalarm report` on
  the CLI) and scan pattern labeling (`PSCAN`/`MSCAN` tags on feed
  entries, computed by the daemon from a 30s window of recent events).
  The pattern tag sits right after the timestamp rather than at the end
  of the line, so it survives `ElideRight` truncation on a long row
  instead of getting cut off along with everything else.
- **1.5.4** — Verified end-to-end: rolled a live install back to v1.5.3 and
  used the real in-app updater to bring it forward to this release, to
  confirm fetch → checkout → reinstall → reload actually works and not
  just the version-comparison logic in isolation.
- **1.5.3** — Two real bugs found by actually running the 1.5.2 updater
  end-to-end: `omarchy-archalarm-update` derived its own location from
  `$BASH_SOURCE`, but it's always invoked through the `~/.local/bin`
  symlink, so it was resolving to the wrong directory entirely and every
  check silently failed with "couldn't reach GitHub." Also, the `⇪ UPDATE`
  badge lived inline in the header next to the gear icon with no width
  cap, so a longer version string would run into it — moved to its own
  full-width banner underneath instead.
- **1.5.2** — Moved to a real GitHub repo (`bin/`, `plugin/`, `systemd/`) —
  everything under `~/.local/bin`, the Omarchy plugin directory, and the
  systemd user unit is now a symlink into this checkout, installed via
  `install.sh`. Added an in-app updater: checks GitHub for a newer tagged
  release once per boot and at most once every 24h, shows an `⇪ UPDATE`
  badge next to the version number when one's out, and installs it with a
  retro dial-up-style progress animation on click. Added
  `omarchy-archalarm setup-sudo`, which generates and installs the
  passwordless-toggle sudoers rule for whoever's actually running it
  (the old setup command had this machine's home directory hardcoded).
- **1.5.1** — Full diagnostic pass, two real bugs fixed: the "always starts
  disarmed" self-heal check compared against `"enabled":true` with no space,
  but status.json is always written with a space after the colon, so it
  never actually matched — a stale "enabled" flag would have stuck around
  instead of resetting. Also added IP-format validation to
  `ban`/`unban`/`trust`/`untrust` (previously any string was accepted and
  written straight to the ban/whitelist files and into the privileged nft
  call). Fixed a text-overflow bug where the "INTRUSION ATTEMPT DETECTED"
  banner could run past the panel's edge instead of wrapping.
- **1.5** — Known-safe filter: auto-allow multicast/broadcast destination
  traffic (mDNS, SSDP, DHCP) so it stops producing false-positive alerts,
  toggleable in Settings. Top offenders made collapsible. Banning now purges
  every existing feed/offender entry for that IP, not just future ones, and
  the daemon independently refuses to re-record a hit from a banned IP as a
  second guard beyond the nft rule order. Ban/trust actions animate instead
  of vanishing silently. Bar icon and status text use fixed traffic-light
  colors (green/yellow/red) independent of the active theme.
- **1.4** — Whitelist added alongside the banlist. Always starts disarmed
  (status self-heals against a stale "enabled" flag). Live feed box shrunk
  and shows a live status line instead of static text. Settings menu (⚙)
  with a theme picker: ArchAlarm, Amber CRT, Cyber Red Alert, or match the
  live Omarchy system theme.
- **1.3** — Expandable socket list. AI-backed IP trace (`investigate`).
  Banlist collapsed by default.
- **1.2** — Idle animation in the live feed panel.
- **1.1** — Renamed RetroWall '95 → ArchAlarm '99. Added ban list, reverse
  DNS, stealth/reject mode, passwordless sudoers option.
- **1.0** — Initial release: ARM/DISARM, live blocked-connection feed, threat
  meter, inbound-only nftables backend.

## Future ideas (not implemented)

- **Session summary on disarm** — a toast on DISARM: block count, unique IPs,
  top offender.
- **Auto-arm at login** — opt-in setting; stays off by default.

## License

MIT — see [LICENSE](LICENSE).
