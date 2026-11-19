#!/usr/bin/env bash
# install.sh: AmneziaWG for the Omarchy bar.
#
#   ./install.sh                       install / update (safe to re-run)
#   ./install.sh --replace ID [ID...]  also take these bar widgets out of the bar
#                                      and move their plugin folders to a backup
#                                      (e.g. an older VPN widget)
#   ./uninstall.sh                     remove everything again
#
# What it does: installs amneziawg-dkms + amneziawg-tools (AUR) and the kernel
# headers they build against; installs the root helper and the CLI; adds ONE
# sudoers rule that lets the wheel group run only that helper; copies the
# plugin to ~/.config/omarchy/plugins and puts it just before the network
# button. Nothing touches your current connection.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID=malekabokhatwa.amnezia
LIBDIR=/usr/local/lib/omarchy-amnezia
HELPER=$LIBDIR/omarchy-amnezia-helper
SUDOERS=/etc/sudoers.d/omarchy-amnezia
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BACKUP="$HOME/.local/state/omarchy-amnezia/backup-$(date +%Y%m%d-%H%M%S)"

if [[ -t 1 ]]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'; else B='' G='' Y='' R='' N=''; fi
step() { echo; echo "${B}==> $*${N}"; }
ok() { echo "  ${G}✓${N} $*"; }
skip() { echo "  ${Y}·${N} $*"; }
die() { echo "  ${R}✗ $*${N}" >&2; exit 1; }

REPLACE=()
while (($#)); do
  case $1 in
    --replace) shift; while (($#)) && [[ $1 != --* ]]; do REPLACE+=("$1"); shift; done ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "run as your user, not root (it asks for sudo itself)"
command -v omarchy >/dev/null || die "this is for Omarchy"
sudo -v || die "sudo is needed"

step "Dependencies"
aur() { if command -v yay >/dev/null; then yay -S --needed --noconfirm "$@"; elif command -v paru >/dev/null; then paru -S --needed --noconfirm "$@"; else die "need yay or paru for the AUR"; fi; }
kpkg=$(pacman -Qqo "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -1)
need=()
[[ -n $kpkg ]] && ! pacman -Qq "$kpkg-headers" >/dev/null 2>&1 && need+=("$kpkg-headers")
pacman -Qq dkms >/dev/null 2>&1 || need+=(dkms)
pacman -Qq systemd-resolvconf openresolv >/dev/null 2>&1 || need+=(systemd-resolvconf)
if ((${#need[@]})); then sudo pacman -S --needed --noconfirm "${need[@]}" && ok "${need[*]}" || die "pacman failed"; else skip "kernel headers, dkms, resolvconf present"; fi
if pacman -Qq amneziawg-dkms amneziawg-tools >/dev/null 2>&1; then skip "amneziawg-dkms, amneziawg-tools present"
else aur amneziawg-dkms amneziawg-tools && ok "amneziawg-dkms, amneziawg-tools" || die "AUR install failed"; fi
if sudo modprobe amneziawg 2>/dev/null; then ok "kernel module amneziawg loads"
else die "amneziawg module did not load for $(uname -r): check 'dkms status' and reboot after a kernel update"; fi

step "Helper, CLI and sudo rule"
sudo install -D -o root -g root -m 755 "$HERE/helper/omarchy-amnezia-helper" "$HELPER" && ok "$HELPER"
sudo install -D -o root -g root -m 755 "$HERE/bin/omarchy-amnezia" /usr/local/bin/omarchy-amnezia && ok /usr/local/bin/omarchy-amnezia
who="%wheel"; id -nG | tr ' ' '\n' | grep -qx wheel || who=$(id -un)
tmp=$(mktemp)
printf '# omarchy-amnezia: let %s run only the AmneziaWG helper without a password.\n%s ALL=(root) NOPASSWD: %s\n' "$who" "$who" "$HELPER" >"$tmp"
if sudo visudo -cqf "$tmp"; then sudo install -o root -g root -m 440 "$tmp" "$SUDOERS" && ok "$SUDOERS ($who, this helper only)"; else rm -f "$tmp"; die "sudoers rule failed validation"; fi
rm -f "$tmp"
sudo install -d -m 700 /etc/amnezia/amneziawg

step "Bar plugin"
mkdir -p "$PLUGIN_DIR"
rsync -a --delete "$HERE/plugin/" "$PLUGIN_DIR/" && ok "$PLUGIN_DIR"

if ((${#REPLACE[@]})) && [[ -f $SHELL_JSON ]]; then
  mkdir -p "$BACKUP"; cp -a "$SHELL_JSON" "$BACKUP/shell.json"
  rm_json=$(printf '%s\n' "${REPLACE[@]}" | jq -R . | jq -s .)
  jq --argjson rm "$rm_json" '.bar.layout |= with_entries(.value |= (if type == "array" then map(select((.id // "") as $i | ($rm | index($i)) | not)) else . end))' \
    "$SHELL_JSON" >"$SHELL_JSON.tmp" && mv "$SHELL_JSON.tmp" "$SHELL_JSON" && ok "removed from bar: ${REPLACE[*]}"
  for r in "${REPLACE[@]}"; do
    [[ $r == "$ID" || ! -d $HOME/.config/omarchy/plugins/$r ]] && continue
    mv "$HOME/.config/omarchy/plugins/$r" "$BACKUP/" && ok "moved plugin $r to $BACKUP"
  done
fi

omarchy-shell -q shell rescanPlugins 2>/dev/null; sleep 1
# Third-party plugins start disabled; enabling also puts them on the bar.
omarchy plugin enable "$ID" >/dev/null 2>&1 && ok "plugin enabled" || echo "  ${Y}!${N} enable it yourself: omarchy plugin enable $ID"
# Then sit it right before the network button (where a VPN toggle belongs).
if omarchy bar move "$ID" --before omarchy.network >/dev/null 2>&1; then ok "placed before the network button"
else echo "  ${Y}!${N} the bar has no network button; it stays where 'enable' put it"; fi

step "Check"
if omarchy-amnezia status | grep -q '"ok":true'; then ok "omarchy-amnezia status works"; else die "status failed: $(omarchy-amnezia status)"; fi
echo
echo "${G}${B}Done.${N} Click the VPN icon next to the network button, or: omarchy-amnezia help"
[[ -d $BACKUP ]] && echo "Backups: $BACKUP"
