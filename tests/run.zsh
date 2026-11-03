#!/usr/bin/env zsh
# Tests for claude-guard. Run: zsh tests/run.zsh
# Uses fake `curl` and `claude` commands; makes no network requests.
emulate -L zsh
setopt err_return no_unset pipe_fail

ROOT=${0:A:h:h}
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/bin"

# Fake curl: prints a trace with $FAKE_IP, or fails when FAKE_IP is empty.
cat > "$WORK/bin/curl" <<'EOF'
#!/bin/sh
[ -n "$FAKE_IP" ] || exit 7
printf 'fl=1\nh=claude.ai\nip=%s\nts=1\n' "$FAKE_IP"
EOF
# Fake claude: shows its arguments and the first line of stdin, if any.
cat > "$WORK/bin/claude" <<'EOF'
#!/bin/sh
if [ -t 0 ]; then in=; else read -r in || true; fi
echo "claude-ran args=[$*] stdin=[$in]"
EOF
chmod +x "$WORK/bin/curl" "$WORK/bin/claude"

pass=0 fail=0

# run <name> <expected exit> <expected output pattern> <zsh code>
# The code runs in a fresh `zsh -f` with the plugin sourced.
run() {
  local name=$1 want_rc=$2 want_out=$3 code=$4 out rc=0
  out=$(env -i HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" LANG=C \
        CLAUDE_GUARD_ALLOWLIST="$WORK/allow" CLAUDE_GUARD_TTY="$WORK/tty" \
        FAKE_IP="${FAKE_IP-}" zsh -f -c "source '$ROOT/claude-guard.plugin.zsh'; $code" 2>&1 </dev/null) || rc=$?
  if [[ $rc == $want_rc && $out == $~want_out ]]; then
    (( pass += 1 )); print -r -- "ok   $name"
  else
    (( fail += 1 )); print -r -- "FAIL $name (exit $rc, want $want_rc)"; print -r -- "$out" | sed 's/^/     | /'
  fi
}

reset_state() { rm -f -- "$WORK/allow" "$WORK/tty"; rm -rf -- "$WORK/home"; }

# --- allowlisted IP starts claude without asking
reset_state
printf '# home\n203.0.113.7\n\n  198.51.100.1  # vps\n' > "$WORK/allow"
FAKE_IP=203.0.113.7 run "allowed IP starts claude" 0 "claude-ran args=\[--resume\]*" 'claude --resume'
FAKE_IP=198.51.100.1 run "inline comment and spaces are ignored" 0 "claude-ran*" 'claude'

# --- IP not in the list
FAKE_IP=192.0.2.9 run "unknown IP, no terminal: abort" 1 "*not in the allowlist*no terminal*" 'claude'
print -n n > "$WORK/tty"
FAKE_IP=192.0.2.9 run "unknown IP, answer n: abort" 1 "*not in the allowlist*" 'claude'
print -n "" > "$WORK/tty"
FAKE_IP=192.0.2.9 run "unknown IP, empty answer: abort" 1 "*not in the allowlist*" 'claude'
print -n y > "$WORK/tty"
FAKE_IP=192.0.2.9 run "unknown IP, answer y: start" 0 "*claude-ran*" 'claude'
FAKE_IP=192.0.2.9 run "answer y does not change the allowlist" 1 "*not in the allowlist*" 'CLAUDE_GUARD_TTY=/nonexistent claude'

# --- answer a adds the IP, then the next start passes
print -n a > "$WORK/tty"
FAKE_IP=192.0.2.9 run "answer a: add and start" 0 "*added 192.0.2.9*claude-ran*" 'claude'
rm -f "$WORK/tty"
FAKE_IP=192.0.2.9 run "added IP passes next time" 0 "claude-ran*" 'claude'

# --- first run: no allowlist file, directory does not exist yet
reset_state
FAKE_IP=192.0.2.9 run "missing allowlist: says empty" 1 "*allowlist is empty*" 'claude'
print -n a > "$WORK/tty"
FAKE_IP=192.0.2.9 run "missing allowlist dir is created on a, path shown with ~" 0 "*added 192.0.2.9 to ~/.config/claude-guard/allowed-ips*claude-ran*" \
  "CLAUDE_GUARD_ALLOWLIST='$WORK/home/.config/claude-guard/allowed-ips' claude"
[[ $(cat "$WORK/home/.config/claude-guard/allowed-ips") == 192.0.2.9 ]] &&
  { (( pass += 1 )); print "ok   created file holds the IP"; } ||
  { (( fail += 1 )); print "FAIL created file holds the IP"; }
run "default allowlist path follows XDG_CONFIG_HOME" 0 "/x/claude-guard/allowed-ips" \
  'unset CLAUDE_GUARD_ALLOWLIST; XDG_CONFIG_HOME=/x; source '"'$ROOT/claude-guard.plugin.zsh'"'; print -r -- $CLAUDE_GUARD_ALLOWLIST'

# --- request fails (proxy down)
reset_state
echo 203.0.113.7 > "$WORK/allow"
FAKE_IP= run "curl fails, no terminal: abort" 1 "*cannot reach*no terminal*" 'claude'
print -n a > "$WORK/tty"
FAKE_IP= run "curl fails, answer a: abort (no IP to add)" 1 "*cannot reach*" 'claude'
print -n y > "$WORK/tty"
FAKE_IP= run "curl fails, answer y: start" 0 "*claude-ran*" 'claude'
rm -f "$WORK/tty"

# --- bypasses
FAKE_IP=192.0.2.9 run "--version skips the check" 0 "claude-ran args=\[--version\]*" 'claude --version'
FAKE_IP=192.0.2.9 run "-h skips the check" 0 "claude-ran args=\[-h\]*" 'claude -h'
FAKE_IP=192.0.2.9 run "CLAUDE_GUARD_SKIP=1 skips the check" 0 "claude-ran*" 'CLAUDE_GUARD_SKIP=1 claude'
FAKE_IP=192.0.2.9 run "command claude skips the check" 0 "claude-ran*" 'command claude'
FAKE_IP=192.0.2.9 run "function snapshot without helpers lets it through" 0 "claude-ran*" \
  'unfunction -m "_claude_guard_*"; claude'

# --- stdin is left for claude (answer is read from the terminal)
print -n y > "$WORK/tty"
FAKE_IP=192.0.2.9 run "stdin reaches claude after the prompt" 0 "*claude-ran args=\[-p\] stdin=\[hello\]*" \
  'echo hello | claude -p'
rm -f "$WORK/tty"

# --- an existing alias named claude does not break sourcing
FAKE_IP=203.0.113.7 run "alias claude defined before source" 0 "claude-ran*" \
  'unfunction claude; alias claude="claude --x"; source '"'$ROOT/claude-guard.plugin.zsh'"'; unalias claude; claude'

# --- messages follow the locale
FAKE_IP=192.0.2.9 run "Chinese messages for zh locale" 1 "*不在白名单*" 'LANG=zh_CN.UTF-8 claude'
FAKE_IP=192.0.2.9 run "CLAUDE_GUARD_LANG overrides the locale" 1 "*not in the allowlist*" \
  'LANG=zh_CN.UTF-8 CLAUDE_GUARD_LANG=en claude'

# --- claude-guard status
reset_state
printf '203.0.113.7\n198.51.100.1 # vps\n' > "$WORK/allow"
FAKE_IP=203.0.113.7 run "status: allowed, exit 0" 0 \
  "egress IP   203.0.113.7  \(*\)*allowlist   */allow  \(2 entries: 203.0.113.7 198.51.100.1\)*result      allowed:*" \
  'claude-guard status'
FAKE_IP=192.0.2.9 run "status: not allowed, exit 1" 1 "*egress IP   192.0.2.9*result      not allowed:*" \
  'claude-guard status'
FAKE_IP= run "status: unreachable, exit 2" 2 "egress IP   none  \(cannot reach *result      claude.ai not reachable:*" \
  'claude-guard status'
FAKE_IP=203.0.113.7 run "status: one entry is singular" 0 "*\\(1 entry: 203.0.113.7\\)*" \
  "print 203.0.113.7 > '$WORK/one'; CLAUDE_GUARD_ALLOWLIST='$WORK/one' claude-guard status"
FAKE_IP=203.0.113.7 run "status: empty allowlist file" 1 "*\\(0 entries\\)*" \
  ": > '$WORK/empty'; CLAUDE_GUARD_ALLOWLIST='$WORK/empty' claude-guard status"
FAKE_IP=203.0.113.7 run "status: missing allowlist file" 1 "*\(file not found\)*not allowed*" \
  "CLAUDE_GUARD_ALLOWLIST='$WORK/nope' claude-guard status"
FAKE_IP=203.0.113.7 run "status: no proxy variable" 0 "*proxy       no proxy variable set*" \
  'claude-guard status'
FAKE_IP=203.0.113.7 run "status: proxy password is hidden" 0 "*proxy       https_proxy=http://\*\*\*@127.0.0.1:7890*" \
  'out=$(https_proxy=http://user:secret@127.0.0.1:7890 claude-guard status); [[ $out != *secret* ]] && print -r -- $out'
FAKE_IP=203.0.113.7 run "status: HTTPS_PROXY used when https_proxy is unset" 0 "*proxy       HTTPS_PROXY=http://127.0.0.1:1*" \
  'HTTPS_PROXY=http://127.0.0.1:1 claude-guard status'
FAKE_IP=203.0.113.7 run "status: note when CLAUDE_GUARD_SKIP is set" 0 "*note        CLAUDE_GUARD_SKIP is set*" \
  'CLAUDE_GUARD_SKIP=1 claude-guard status'
FAKE_IP=203.0.113.7 run "status: Chinese output" 0 "出口 IP   203.0.113.7*结果      在白名单*" \
  'CLAUDE_GUARD_LANG=zh claude-guard status'
FAKE_IP= run "check: proxy password is hidden" 1 "*http://\*\*\*@127.0.0.1:7890*" \
  'out=$(https_proxy=http://user:secret@127.0.0.1:7890 claude 2>&1); rc=$?; [[ $out != *secret* ]] && print -r -- $out; return $rc'
run "claude-guard without arguments shows usage" 0 "usage: claude-guard status*" 'claude-guard'
run "claude-guard unknown subcommand: exit 2" 2 "usage: claude-guard status*" 'claude-guard bogus'
run "claude-guard in a function snapshot: exit 2" 2 "*helper functions are not loaded*" \
  'unfunction -m "_claude_guard_*"; claude-guard status'

print -r -- "---"
print -r -- "$pass passed, $fail failed"
(( fail == 0 ))
