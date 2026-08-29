#!/bin/bash
# Installs ArchAlarm '99 by symlinking this repo's files into the standard
# Omarchy locations. Safe to re-run — every link is idempotent. Doesn't
# touch anything outside these paths and needs no root privileges itself.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_LINK="$HOME/.config/omarchy/plugins/alexander.archalarm"
SYSTEMD_DIR="$HOME/.config/systemd/user"
CURRENT_LINK="$HOME/.local/share/omarchy/archalarm-current"

mkdir -p "$BIN_DIR" "$HOME/.config/omarchy/plugins" "$SYSTEMD_DIR" "$(dirname "$CURRENT_LINK")"

# Every live path below points through this one indirection instead of
# straight at $REPO_DIR. On a fresh install that's an extra hop for no
# reason — but on an update, the in-app updater builds the new version in
# a separate directory and re-runs this script from there, and repointing
# one symlink here is the only thing that then needs to change. Every
# other path stays untouched, since it was never pointed at a specific
# version to begin with. Repointing 6 different symlinks one at a time
# used to mean up to 6 separate file-watcher events — and the whole bar
# visibly flickering with each one — for what should be a single update.
ln -sfn "$REPO_DIR" "$CURRENT_LINK"

for script in omarchy-archalarm omarchy-archalarm-apply omarchy-archalarm-monitor omarchy-archalarm-update; do
  chmod +x "$REPO_DIR/bin/$script"
  ln -sf "$CURRENT_LINK/bin/$script" "$BIN_DIR/$script"
done

# If a previous non-symlinked install (or a manual copy) is sitting at the
# plugin path, clear it before linking so this doesn't merge two copies.
if [[ -e "$PLUGIN_LINK" && ! -L "$PLUGIN_LINK" ]]; then
  rm -rf "$PLUGIN_LINK"
fi
ln -sfn "$CURRENT_LINK/plugin" "$PLUGIN_LINK"

ln -sf "$CURRENT_LINK/systemd/omarchy-archalarm-monitor.service" \
  "$SYSTEMD_DIR/omarchy-archalarm-monitor.service"

systemctl --user daemon-reload

cat <<'EOF'

ArchAlarm '99 is installed.

Next steps:
  1. Add the bar widget: open ~/.config/omarchy/shell.json and add
       { "id": "alexander.archalarm" }
     to the "right" array under "bar" -> "layout", then run:
       omarchy restart shell

  2. (Optional) Enable passwordless arm/disarm/ban:
       omarchy-archalarm setup-sudo

  3. (Optional) If the live feed stays empty while armed, add yourself to
     the journal group (log out/in after), then restart the monitor:
       sudo usermod -aG systemd-journal $USER

The firewall always starts disarmed. Click the bar icon to arm it.
EOF
