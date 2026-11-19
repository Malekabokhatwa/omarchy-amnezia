#!/usr/bin/env bash
# uninstall.sh: disconnect, then remove the helper, CLI, sudo rule and plugin.
# Leaves your configs in /etc/amnezia/amneziawg and the AUR packages alone.
set -uo pipefail
ID=malekabokhatwa.amnezia
[[ $EUID -ne 0 ]] || { echo "run as your user"; exit 1; }
sudo -v || exit 1
command -v omarchy-amnezia >/dev/null && omarchy-amnezia down >/dev/null 2>&1
sudo /usr/local/lib/omarchy-amnezia/omarchy-amnezia-helper autostart off >/dev/null 2>&1
sudo rm -f /etc/sudoers.d/omarchy-amnezia /usr/local/bin/omarchy-amnezia
sudo rm -rf /usr/local/lib/omarchy-amnezia
S="$HOME/.config/omarchy/shell.json"
if [[ -f $S ]]; then
  jq --arg id "$ID" '.bar.layout |= with_entries(.value |= (if type == "array" then map(select(.id != $id)) else . end))' "$S" >"$S.tmp" && mv "$S.tmp" "$S"
fi
rm -rf "$HOME/.config/omarchy/plugins/$ID"
echo "Removed. Configs are still in /etc/amnezia/amneziawg (sudo ls to see them)."
