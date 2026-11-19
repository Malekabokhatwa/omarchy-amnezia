#!/bin/bash
# Unprivileged tests for the helper's config parsing (no root, no network).
H="$(dirname "$0")/../helper/omarchy-amnezia-helper"
eval "$(sed -n '/^validate()/,/^}/p; /^iface_val()/,/^}/p; /^peer_endpoint()/p' "$H")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; failn=0
check() { # check NAME EXPECT(ok|bad) CONTENT
  printf '%s' "$3" >"$T/c.conf"; local r; r=$(validate "$T/c.conf")
  if [[ $2 == ok && -z $r ]] || [[ $2 == bad && -n $r ]]; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL $1: got '${r:-ok}'"; fi
}
GOOD='[Interface]
PrivateKey = aaa=
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
PublicKey = bbb=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 203.0.113.5:51820
PersistentKeepalive = 25
'
check plain-wireguard ok "$GOOD"
check awg2-params ok "${GOOD/DNS = 10.2.0.1/DNS = 10.2.0.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 15
S2 = 18
H1 = 1234567
I1 = <b 0xabcdef>}"
check crlf-comments ok "$(printf '%s' "$GOOD" | sed 's/$/\r/; 1i # comment')"
check postup-root-exec bad "${GOOD/DNS = 10.2.0.1/PostUp = touch /root/pwned}"
check preup-lowercase bad "${GOOD/DNS = 10.2.0.1/preup = id}"
check table-key bad "${GOOD/DNS = 10.2.0.1/Table = off}"
check saveconfig bad "${GOOD/DNS = 10.2.0.1/SaveConfig = true}"
check unknown-section bad "$GOOD
[Evil]
x = 1"
check no-peer bad '[Interface]
PrivateKey = a
'
check no-endpoint bad "${GOOD/Endpoint = 203.0.113.5:51820/}"
check two-interfaces bad "$GOOD
[Interface]
PrivateKey = c"
check junk-line bad "${GOOD/DNS = 10.2.0.1/just text}"
check peer-key-in-iface bad "${GOOD/DNS = 10.2.0.1/Endpoint = 1.2.3.4:1}"
printf '%s' "$GOOD" >"$T/c.conf"
[[ $(iface_val "$T/c.conf" Address) == 10.2.0.2/32 ]] && pass=$((pass+1)) || { failn=$((failn+1)); echo "FAIL iface_val"; }
[[ $(peer_endpoint "$T/c.conf") == 203.0.113.5:51820 ]] && pass=$((pass+1)) || { failn=$((failn+1)); echo "FAIL peer_endpoint"; }
echo "$pass passed, $failn failed"; ((failn == 0))
