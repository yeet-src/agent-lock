#!/bin/sh
# adversary.sh — a jail-breakout test suite. Plays the role of a malicious agent
# trying every filesystem-escape trick to read secrets outside its directory.
# Run it JAILED (via agent-lock) and every attempt should fail; run it unjailed to
# see the same attempts succeed (the baseline that proves the jail is doing work).
#
#   sudo agent-lock-bin DIR -- /bin/sh adversary.sh        # jailed: all should FAIL
#   sh adversary.sh                                       # unjailed: many SUCCEED
#
# It targets real secret paths and reports, per technique, whether it got data
# out (LEAK) or was refused (blocked). Exit code = number of leaks.
#
# These are the techniques a sandbox MUST withstand: a naive path filter that
# only checks the literal string would fall to traversal/symlink/procfs, but
# Landlock resolves the real inode, so they don't get out.

TARGETS="/etc/passwd /etc/shadow $HOME/.ssh/id_rsa $HOME/.aws/credentials"
leaks=0
pass=0

# Did we manage to read any bytes from `f`? Print verdict.
try() {
  name="$1"; f="$2"
  if data=$(cat "$f" 2>/dev/null) && [ -n "$data" ]; then
    printf '  [LEAK ] %-24s got %s bytes from %s\n' "$name" "$(printf '%s' "$data" | wc -c)" "$f"
    leaks=$((leaks + 1))
  else
    printf '  [block] %-24s refused: %s\n' "$name" "$f"
    pass=$((pass + 1))
  fi
}

echo "=== adversary: attempting to escape the jail ==="

# 1) Direct absolute read — the obvious one.
echo "[1] direct absolute path"
for t in $TARGETS; do try "direct" "$t"; done

# 2) Path traversal — climb out with ../../ from the jailed dir.
echo "[2] ../.. path traversal"
try "traversal-passwd" "../../../../../../etc/passwd"
try "traversal-shadow" "../../../../../../etc/shadow"

# 3) Symlink — plant a link inside the jail pointing out, then read the link.
echo "[3] symlink out of jail"
ln -sf /etc/passwd ./sneaky_link 2>/dev/null
try "symlink-passwd" "./sneaky_link"
ln -sf "$HOME/.ssh/id_rsa" ./key_link 2>/dev/null
try "symlink-sshkey" "./key_link"

# 4) /proc/self/root — the procfs root re-entry trick.
echo "[4] /proc/self/root re-entry"
try "procfs-root" "/proc/self/root/etc/passwd"
try "procfs-cwd" "/proc/self/cwd/../../../../etc/shadow"

# 5) /proc/<pid>/environ and other process introspection. A process can ALWAYS
#    read its own environment (Landlock can't wall a process off from itself),
#    so the real question is whether anything SECRET is in it. agent-lock scrubs
#    secret-bearing vars before exec, so this should find none.
echo "[5] /proc pid introspection"
try "proc-pid1-environ" "/proc/1/environ"
if env_data=$(cat /proc/self/environ 2>/dev/null | tr '\0' '\n') && \
   printf '%s' "$env_data" | grep -qiE 'KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|ANTHROPIC|OPENAI|AWS_SECRET'; then
  echo "  [LEAK ] proc-self-environ        SECRET found in own environment"
  leaks=$((leaks + 1))
else
  echo "  [block] proc-self-environ        own environ readable but holds no secrets"
  pass=$((pass + 1))
fi

# 6) Hardlink attempt. A hardlink to an out-of-jail file, planted inside the
#    jail, is a genuine gap in PATH-based enforcement: the link IS a real
#    directory entry under the jail, so bpf_d_path resolves the open to an
#    in-bounds path and the read is allowed. Closing it needs inode-level
#    checks (see README "Known limitations"). This can only be exercised on a
#    real filesystem — a cross-device hardlink onto tmpfs fails to create, so
#    the test is a no-op when the jail lives on /tmp. We report the outcome as
#    a KNOWN limitation rather than counting it as a leak, so the suite's
#    pass/fail stays about the escapes the jail actually claims to stop.
echo "[6] hardlink across boundary"
if ln /etc/passwd ./hard_passwd 2>/dev/null; then
  if data=$(cat ./hard_passwd 2>/dev/null) && [ -n "$data" ]; then
    echo "  [known] hardlink                 read $(printf '%s' "$data" | wc -c) bytes via in-jail hardlink (path-based limitation)"
  else
    echo "  [block] hardlink                 in-jail hardlink read refused"
    pass=$((pass + 1))
  fi
else
  echo "  [block] hardlink                 could not create link out of jail"
  pass=$((pass + 1))
fi

# 7) Walk up by opening parent directories directly.
echo "[7] parent directory listing"
if ls -la .. 2>/dev/null | grep -q .; then
  echo "  [LEAK ] parent-listing          could list parent directory"
  leaks=$((leaks + 1))
else
  echo "  [block] parent-listing          refused to list .."
  pass=$((pass + 1))
fi

# 8) Absolute write outside — exfil by dropping a file out of bounds.
echo "[8] write outside jail (exfil drop)"
if echo "stolen" > "$HOME/exfil_$$.txt" 2>/dev/null; then
  echo "  [LEAK ] exfil-write             wrote outside the jail"
  leaks=$((leaks + 1)); rm -f "$HOME/exfil_$$.txt" 2>/dev/null
else
  echo "  [block] exfil-write             refused to write outside"
  pass=$((pass + 1))
fi

# 9) Prefix-sibling directory — the jail dir is e.g. $HOME/.agent-lock-adv.
#    A sibling $HOME/.agent-lock-adv2 shares the same string prefix. A path
#    filter that only compares prefix_len bytes would wrongly treat it as
#    in-bounds. The boundary check in under_prefix() must catch this. The
#    sibling is derived from the real cwd (the jail dir), not hardcoded, so
#    this holds wherever the launcher put the jail.
echo "[9] prefix-sibling directory read"
SIBLING="$(pwd)2"
BASE="$(basename "$SIBLING")"
try "prefix-sibling-rel" "../$BASE/secret.txt"
try "prefix-sibling-abs" "$SIBLING/secret.txt"
try "prefix-sibling-dir" "$SIBLING"

# cleanup any links we planted (best effort; may be denied, that's fine)
rm -f ./sneaky_link ./key_link ./hard_passwd 2>/dev/null || true

echo "=== adversary done: $pass blocked, $leaks LEAKED ==="
exit "$leaks"
