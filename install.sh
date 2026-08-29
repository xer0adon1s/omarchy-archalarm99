#!/bin/bash
# Installs ArchAlarm '99 by symlinking this repo's files into the standard
# Omarchy locations. Safe to re-run — every link is idempotent. Doesn't
# touch anything outside these paths and needs no root privileges itself.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_LINK="$HOME/.config/omarchy/plugins/alexander.archalarm"
SYSTEMD_DIR="$HOME/.config/systemd/user"

mkdir -p "$BIN_DIR" "$HOME/.config/omarchy/plugins" "$SYSTEMD_DIR"

for script in omarchy-archalarm omarchy-archalarm-apply omarchy-archalarm-monitor omarchy-archalarm-update; do
  chmod +x "$REPO_DIR/bin/$script"
  ln -sf "$REPO_DIR/bin/$script" "$BIN_DIR/$script"
done

# If a previous non-symlinked install (or a manual copy) is sitting at the
# plugin path, clear it before linking so this doesn't merge two copies.
if [[ -e "$PLUGIN_LINK" && ! -L "$PLUGIN_LINK" ]]; then
  rm -rf "$PLUGIN_LINK"
fi
ln -sfn "$REPO_DIR/plugin" "$PLUGIN_LINK"

ln -sf "$REPO_DIR/systemd/omarchy-archalarm-monitor.service" \
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

The firewall always starts disarmed. Click the bar icon to arm it.
EOF
