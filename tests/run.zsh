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
echo "claude-ran args=[$*] stdin=[$in] skip=[${CLAUDE_GUARD_SKIP-}]"
EOF
chmod +x "$WORK/bin/curl" "$WORK/bin/claude"

pass=0 fail=0
# Runs the prompt hook the way Claude Code does, with a JSON input on stdin.
HOOK="zsh '$ROOT/claude-guard-hook.zsh' <<< '{\"prompt\":\"hi\"}'"

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
[[ $(cut -d" " -f1 "$WORK/home/.config/claude-guard/allowed-ips") == 192.0.2.9 ]] &&
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
run "claude-guard without arguments shows usage" 0 "usage:*claude-guard status*claude-guard add*claude-guard remove*" 'claude-guard'
run "claude-guard unknown subcommand: exit 2" 2 "usage:*" 'claude-guard bogus'
FAKE_IP=203.0.113.7 run "claude-guard works without the helper functions (Bash tool)" 0 "*result      allowed*" \
  'unfunction -m "_claude_guard_*"; claude-guard status'

# --- claude-guard add / remove
reset_state
printf '# home\n203.0.113.7  # home\n198.51.100.1\n' > "$WORK/allow"
FAKE_IP=192.0.2.9 run "add without IP adds the egress IP" 0 "✅ added 192.0.2.9 to */allow" 'claude-guard add'
[[ $(tail -1 "$WORK/allow") == "192.0.2.9    # added "<->-<->-<-> ]] &&
  { (( pass += 1 )); print "ok   add writes the IP with a date comment"; } ||
  { (( fail += 1 )); print "FAIL add writes the IP with a date comment"; tail -1 "$WORK/allow"; }
FAKE_IP=192.0.2.9 run "add without IP writes the cache (hook passes)" 0 "" "FAKE_IP= $HOOK"
FAKE_IP=192.0.2.9 run "add of a listed IP says so" 0 "192.0.2.9 is already in the allowlist*" 'claude-guard add'
run "add with an IPv4" 0 "✅ added 198.51.100.77*" 'claude-guard add 198.51.100.77'
run "add with an IPv6 is lowercased" 0 "✅ added 2001:db8::1 *" 'claude-guard add 2001:DB8::1'
run "add rejects a part above 255" 1 "*not a valid IP: 203.0.113.256*" 'claude-guard add 203.0.113.256'
run "add rejects three parts" 1 "*not a valid IP: 1.2.3*" 'claude-guard add 1.2.3'
run "add rejects a name" 1 "*not a valid IP: example.com*" 'claude-guard add example.com'
run "add rejects two arguments" 2 "usage:*" 'claude-guard add 192.0.2.1 192.0.2.2'
FAKE_IP= run "add without IP, claude.ai not reachable: exit 2" 2 "*cannot reach*" 'claude-guard add'
run "add in Chinese" 0 "✅ 已把 192.0.2.44 加入*" 'CLAUDE_GUARD_LANG=zh claude-guard add 192.0.2.44'
run "add creates a missing directory" 0 "✅ added 192.0.2.45*" \
  "CLAUDE_GUARD_ALLOWLIST='$WORK/new/dir/allowed-ips' claude-guard add 192.0.2.45 && grep -q '^192.0.2.45 ' '$WORK/new/dir/allowed-ips'"
run "add starts a new line when the file has no final newline" 0 "*" \
  "printf 203.0.113.7 > '$WORK/nonl'; CLAUDE_GUARD_ALLOWLIST='$WORK/nonl' claude-guard add 192.0.2.46 >/dev/null; [[ \$(sed -n 2p '$WORK/nonl') == '192.0.2.46 '* && \$(sed -n 1p '$WORK/nonl') == 203.0.113.7 ]]"

printf '# home\n203.0.113.7  # home\n198.51.100.1\n# vps\n' > "$WORK/allow"
run "remove deletes only that entry" 0 "✅ removed 203.0.113.7 from */allow" 'claude-guard remove 203.0.113.7'
[[ $(<"$WORK/allow") == $'# home\n198.51.100.1\n# vps' ]] &&
  { (( pass += 1 )); print "ok   remove keeps the other lines and comments"; } ||
  { (( fail += 1 )); print "FAIL remove keeps the other lines and comments"; cat "$WORK/allow"; }
run "remove of an IP not listed: exit 1" 1 "*203.0.113.7 is not in the allowlist*" 'claude-guard remove 203.0.113.7'
run "remove needs an IP" 2 "usage:*" 'claude-guard remove'
FAKE_IP=198.51.100.1 run "removed IP is blocked at once, even when cached" 2 "*not in the allowlist*" \
  "$HOOK >/dev/null; claude-guard remove 198.51.100.1 >/dev/null; $HOOK"

# --- prompt hook (claude-guard-hook.zsh)
CACHE="$WORK/home/.cache/claude-guard/last-ok"
reset_state
echo 203.0.113.7 > "$WORK/allow"
FAKE_IP=203.0.113.7 run "hook: allowed IP passes silently" 0 "" "$HOOK"
[[ $(cut -d' ' -f2 "$CACHE") == 203.0.113.7 ]] &&
  { (( pass += 1 )); print "ok   hook: pass writes the cache"; } ||
  { (( fail += 1 )); print "FAIL hook: pass writes the cache"; }
FAKE_IP= run "hook: recent pass is reused (no request)" 0 "" "$HOOK"
FAKE_IP= run "hook: TTL 0 always checks" 2 "*cannot reach*The prompt was not sent*" "CLAUDE_GUARD_HOOK_TTL=0 $HOOK"
FAKE_IP= run "hook: other proxy variables do not reuse the cache" 2 "*cannot reach*https_proxy=http://127.0.0.1:1*" \
  "https_proxy=http://127.0.0.1:1 $HOOK"
FAKE_IP= run "hook: expired cache is not reused" 2 "*cannot reach*" \
  "print -r -- \"1 203.0.113.7 \$(_claude_guard_proxy_key)\" > '$CACHE'; $HOOK"
FAKE_IP= run "hook: cached IP no longer allowed is not reused" 2 "*cannot reach*" \
  "zmodload zsh/datetime; print -r -- \"\$EPOCHSECONDS 192.0.2.50 \$(_claude_guard_proxy_key)\" > '$CACHE'; $HOOK"
rm -f "$CACHE"
FAKE_IP=192.0.2.9 run "hook: unknown IP blocks with a fix command" 2 \
  "*egress IP 192.0.2.9 is not in the allowlist \\(203.0.113.7\\). The prompt was not sent.*start the line with !*claude-guard add 192.0.2.9" "$HOOK"
FAKE_IP=192.0.2.9 run "hook: Chinese message" 2 "*出口 IP 192.0.2.9 不在白名单*这条 prompt 没有发送*" "CLAUDE_GUARD_LANG=zh $HOOK"
FAKE_IP=192.0.2.9 run "hook: bare command when the user's PATH has bin/" 2 "*!\\):?  claude-guard add 192.0.2.9" "$HOOK"
FAKE_IP=192.0.2.9 run "hook: full path when the user's PATH lacks bin/" 2 "*!\\):?  $ROOT/bin/claude-guard add 192.0.2.9" \
  "PATH='$WORK/bin:/usr/bin:/bin' $HOOK"
FAKE_IP=192.0.2.9 run "hook: bare command as a Claude Code plugin" 2 "*!\\):?  claude-guard add 192.0.2.9" \
  "CLAUDE_PLUGIN_ROOT='$ROOT' PATH='$WORK/bin:/usr/bin:/bin' $HOOK"
FAKE_IP=192.0.2.9 run "hook: CLAUDE_GUARD_SKIP lets the prompt through" 0 "" "CLAUDE_GUARD_SKIP=1 $HOOK"
FAKE_IP=203.0.113.7 run "hook: cache does not store the proxy password" 0 "" \
  "https_proxy=http://user:secret@127.0.0.1:7890 $HOOK; ! grep -q secret '$CACHE'"
FAKE_IP= run "hook: unreachable hides the proxy password" 2 "*https_proxy=http://\*\*\*@127.0.0.1:1*" \
  "out=\$(https_proxy=http://u:secret@127.0.0.1:1 CLAUDE_GUARD_HOOK_TTL=0 $HOOK 2>&1); rc=\$?; [[ \$out != *secret* ]] && print -r -- \$out; return \$rc"

# --- wrapper and hook together
reset_state
echo 203.0.113.7 > "$WORK/allow"
FAKE_IP=203.0.113.7 run "wrapper pass writes the cache for the first prompt" 0 "claude-ran*" \
  "claude && FAKE_IP= $HOOK"
print -n y > "$WORK/tty"
FAKE_IP=192.0.2.9 run "answer y starts claude with CLAUDE_GUARD_SKIP=1" 0 "*claude-ran*skip=\[1\]*" 'claude'
FAKE_IP=192.0.2.9 run "answer y does not write the cache" 0 "*claude-ran*" "rm -f '$CACHE'; claude; [[ ! -e '$CACHE' ]]"
print -n a > "$WORK/tty"
FAKE_IP=192.0.2.9 run "answer a writes the cache" 0 "*claude-ran*skip=\[\]*" "claude && [[ \$(cut -d' ' -f2 '$CACHE') == 192.0.2.9 ]]"
rm -f "$WORK/tty"

print -r -- "---"
print -r -- "$pass passed, $fail failed"
(( fail == 0 ))
