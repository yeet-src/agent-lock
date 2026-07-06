#!/bin/sh
# adversary-lsm.sh — prove the eBPF (LSM) jail withstands escape attempts.
# Loads the LSM program, then runs the breakout suite (scripts/adversary.sh) as
# an "omp"-comm process confined to a temp dir, so the program self-enrolls and
# enforces. Reports the jailed leak count; 0 means the jail held.
#
# Run via `make adversary` (which builds first) or `sudo sh scripts/adversary-lsm.sh`.
# Everything runs in ONE process tree so the held loader is never reaped early.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$HERE"

# Jail under $HOME, NOT /tmp. /tmp/ is a blanket system-read prefix in the
# kernel program (sys_prefixes[]), so a sibling under /tmp is allowed as a
# benign scratch read regardless of the jail boundary — which would make the
# prefix-sibling test below leak for a reason that has nothing to do with the
# boundary check it exists to exercise. A home-dir path is both realistic (real
# jailed projects live there) and outside every system/scratch allowlist.
PROJ="$HOME/.agent-lock-adv"
rm -rf "$PROJ"; mkdir -p "$PROJ"
cp scripts/adversary.sh "$PROJ/adversary.sh"   # must live INSIDE the jail to be read
# Prefix-sibling directory: a same-prefix directory next to the jail that
# a naive path-prefix check would allow. The under_prefix() boundary check
# must refuse this — otherwise "$HOME/.agent-lock-adv2" is reachable from
# "$HOME/.agent-lock-adv". This is the escape vector this fix closes.
SIBLING="${PROJ}2"
rm -rf "$SIBLING"; mkdir -p "$SIBLING"
echo "SIBLING_SECRET" > "$SIBLING/secret.txt"
# decoy secrets the suite reaches for
mkdir -p "$HOME/.ssh" "$HOME/.aws" 2>/dev/null || true
[ -f "$HOME/.ssh/id_rsa" ] || printf 'PRIVKEY\n' > "$HOME/.ssh/id_rsa" 2>/dev/null || true
[ -f "$HOME/.aws/credentials" ] || printf '[d]\n' > "$HOME/.aws/credentials" 2>/dev/null || true

# omp-named shell so the LSM program self-enrolls it.
STANDIN=$(mktemp -d)/omp
cp "$(command -v dash 2>/dev/null || command -v sh)" "$STANDIN"

# Holder: load the LSM jail, patch dir + comm, hold. Same shape proven to enforce.
cat > /tmp/adv-holder.js <<JS
import { BpfObject, DataSec } from "yeet:bpf";
const dir = "$PROJ";
const p = new BpfObject({ exe: "../bin/probe.bpf.o", base: import.meta.dirname });
const c = await p
  .bind("events", { kind: "ring_buf", btf_struct: "file_event" })
  .bind("jailed", { kind: "hash" })
  .bind("probe.data", { kind: "data" })
  .start();
new DataSec(c, "probe.data").patch({ target_prefix: dir, target_prefix_len: dir.length, target_comm: "omp", audit_mode: 0 });
console.log("ADV_HOLDER_READY");
await new Promise(()=>{});
JS
cp /tmp/adv-holder.js "$HERE/scripts/adv-holder.js"

echo "== loading LSM jail =="
yeet run "$HERE/scripts/adv-holder.js" > /tmp/adv-holder.out 2>&1 &
HOLDER=$!
for i in $(seq 1 25); do grep -q ADV_HOLDER_READY /tmp/adv-holder.out 2>/dev/null && break; sleep 0.3; done
if ! grep -q ADV_HOLDER_READY /tmp/adv-holder.out 2>/dev/null; then
  echo "FAIL: jail did not load:"; grep -iE "error|map service|verifier" /tmp/adv-holder.out | head -3
  kill $HOLDER 2>/dev/null; exit 1
fi

echo "== running breakout suite as a jailed omp process =="
# The suite cd's into its own dir and runs the attacks; exit code = leak count.
"$STANDIN" -c "cd $PROJ && exec /bin/sh ./adversary.sh"
RC=$?

kill $HOLDER 2>/dev/null; pkill -9 -f adv-holder 2>/dev/null
rm -f "$HERE/scripts/adv-holder.js"; rm -rf "$(dirname "$STANDIN")" "$SIBLING"
echo "  jailed leaks: $RC"
[ "$RC" -eq 0 ] && echo "PASS: jail held" || { echo "FAIL: $RC leak(s)"; exit 1; }
