# omarchy-amnezia

**AmneziaWG in the Omarchy bar.** Connect, import `.conf` files, turn on
obfuscation, and test configs in a sandbox, from a shield icon that sits next
to the network button and follows your Omarchy theme.

Built for networks where WireGuard "connects" but nothing gets through.

## The problem it solves

WireGuard has no connection handshake that can fail visibly: the interface
comes up and every client says *connected*, even when the server never
answers. On networks whose DPI fingerprints the WireGuard handshake, that is
exactly what you get: "connected", 100% packet loss, nothing loads.

This was measured, not guessed (on a network in Egypt, Proton free servers):

| Config | Plain WireGuard | With junk packets (`Jc/Jmin/Jmax`) |
| --- | --- | --- |
| Proton NL #79 | no handshake, 296 B out, 0 B in | handshake in 0 s, HTTPS works |
| Proton NL #112 | no handshake | handshake in 1 s |
| Proton NL #132 | no handshake | handshake in 1 s, HTTPS works |

[AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/) can send junk
packets before the handshake. **Ordinary WireGuard servers ignore them**, so you
get obfuscation against any server, including commercial ones, with no server
changes. Configs from a real AmneziaWG server (`S1`, `S2`, `H1`-`H4`, `I1`...)
are used as they are.

## Features

- **Bar icon** (shield with a lock) beside the network button: dim when off,
  pulsing while connecting, full colour when connected, red after a failure.
  Left-click opens the panel, right-click connects/disconnects.
- **Panel** built from Omarchy's own components, so it follows every theme:
  on/off switch, live traffic and handshake age, your configs with one-click
  connect, an obfuscation toggle per config, delete with confirm.
- **Import**: `.conf` files in `~/VPNs`, `~/Downloads` and `~/Documents` show up
  as one-click imports; any other path can be pasted.
- **Diagnose in a sandbox**: tests a config inside a throwaway network
  namespace and reports handshake, ping and HTTPS separately. Your real
  connection is never touched.
- **Connect that can't strand you**: after connecting it checks for a real
  handshake and real traffic (HTTPS by IP, or ping) and **disconnects again by
  itself** within seconds if either is missing. A blocked server can't leave
  you with a dead default route.
- **Connect at boot** for the config you choose.
- CLI for everything: `omarchy-amnezia help`.

## Install

```bash
git clone https://github.com/Malekabokhatwa/omarchy-amnezia.git ~/Work/omarchy-amnezia
cd ~/Work/omarchy-amnezia
./install.sh
# replacing an older VPN widget:
./install.sh --replace io.github.hcduller.vpn glafeara.wireguard
```

The installer sets up `amneziawg-dkms` and `amneziawg-tools` (AUR, via yay or
paru), kernel headers, `dkms` and `systemd-resolvconf`. It installs the helper
and CLI, adds the bar widget before the network button, and enables it.
Re-running it is safe. `./uninstall.sh` removes everything except your configs.

## Use

| Action | Bar | CLI |
| --- | --- | --- |
| Connect / disconnect | right-click the icon, or the switch | `omarchy-amnezia toggle` |
| Connect a specific config | click it in the panel | `omarchy-amnezia up NAME` |
| Import | click a suggested file, or paste a path | `omarchy-amnezia import FILE [NAME]` |
| Obfuscation | the shield button on a config | `omarchy-amnezia obfuscate NAME on` |
| Test safely | the gauge button on a config | `omarchy-amnezia diagnose NAME` |
| Connect at boot | toggle at the bottom | `omarchy-amnezia autostart NAME` |

Keys in the panel: `t` toggles, `/` or `i` focuses the import field.

**If it says "no handshake"**, turn on obfuscation and diagnose again. **If ping
fails but HTTPS works**, the server drops ICMP (Proton free does). The tunnel is
fine; only ping-based meters (like a packet-loss readout) will look wrong.

## Security

Only one small root helper (`/usr/local/lib/omarchy-amnezia/omarchy-amnezia-helper`)
is privileged. One sudoers rule lets the `wheel` group run that file, and
nothing else, without a password. The helper:

- validates every argument (`[A-Za-z0-9_-]{1,15}` names);
- parses each config against an allow-list and **rejects `PostUp`, `PreUp`,
  `PostDown`, `PreDown`, `Table`, `SaveConfig`** and any unknown key or section,
  so importing a config can never run a command as root;
- stores configs `0600 root` in `/etc/amnezia/amneziawg/` (where `awg-quick`
  expects them);
- prints JSON; the plugin renders every string as plain text.

`tests/validate.sh` covers the parser (15 cases, including the rejections):

```bash
tests/validate.sh   # 15 passed, 0 failed
```

## Files

```
helper/omarchy-amnezia-helper   root helper (list/status/import/remove/obfuscate/up/down/diagnose/autostart)
bin/omarchy-amnezia             user CLI, used by the plugin
plugin/                         Omarchy shell plugin (manifest, Panel.qml, Service.qml, i18n/en.json)
install.sh, uninstall.sh
tests/validate.sh
```

## License

MIT
