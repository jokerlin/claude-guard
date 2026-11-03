# claude-guard: check the egress IP before Claude Code starts.
# https://github.com/jokerlin/claude-guard
#
# Skip the check once:  CLAUDE_GUARD_SKIP=1 claude ...   or   command claude ...
# Design notes:         docs/design.md

# ---- settings (set any of these before this file is sourced to override) ----
: ${CLAUDE_GUARD_ALLOWLIST:=${XDG_CONFIG_HOME:-$HOME/.config}/claude-guard/allowed-ips}
: ${CLAUDE_GUARD_TRACE_URL:=https://claude.ai/cdn-cgi/trace}
: ${CLAUDE_GUARD_TIMEOUT:=10}
# Where the y/N/a answer is read from. Tests point it at a file.
: ${CLAUDE_GUARD_TTY:=/dev/tty}

# Message language: CLAUDE_GUARD_LANG=zh|en, otherwise taken from the locale.
_claude_guard_zh() {
  local l=${CLAUDE_GUARD_LANG:-${LC_ALL:-${LC_MESSAGES:-$LANG}}}
  [[ $l == zh* ]]
}

# Print the first argument in Chinese locales, the second otherwise.
_claude_guard_text() {
  if _claude_guard_zh; then print -r -- "$1"; else print -r -- "$2"; fi
}

# Same as _claude_guard_text, to stderr.
_claude_guard_say() { _claude_guard_text "$@" >&2 }

# The proxy variable that curl uses for https, as name=value with any
# user:password removed. Prints nothing when no proxy variable is set.
_claude_guard_proxy() {
  local name
  for name in https_proxy HTTPS_PROXY all_proxy ALL_PROXY; do
    if [[ -n ${(P)name} ]]; then
      print -r -- "$name=${(P)name}" | sed -E 's#(://)[^@/]*@#\1***@#'
      return
    fi
  done
}

# The IP that claude.ai sees. The request uses the same proxy settings as
# claude itself, so proxy routing rules give the same answer.
# Prints nothing when the request fails.
_claude_guard_exit_ip() {
  curl -fsS --max-time "$CLAUDE_GUARD_TIMEOUT" "$CLAUDE_GUARD_TRACE_URL" 2>/dev/null |
    sed -n 's/^ip=//p'
}

# Allowlist entries, one per line, without comments and blank lines.
_claude_guard_entries() {
  [[ -r $CLAUDE_GUARD_ALLOWLIST ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$CLAUDE_GUARD_ALLOWLIST"
}

_claude_guard_allowed() {
  [[ -n $1 ]] && _claude_guard_entries | grep -qxF -- "$1"
}

# Returns 0 when claude may start. On a mismatch, asks:
#   y = start anyway, a = add this IP to the allowlist and start, anything else = abort.
_claude_guard_check() {
  local ip reply prompt entries
  ip=$(_claude_guard_exit_ip)

  _claude_guard_allowed "$ip" && return 0

  if [[ -z $ip ]]; then
    local proxy=$(_claude_guard_proxy)
    _claude_guard_say \
      "⚠️  claude-guard: 无法访问 $CLAUDE_GUARD_TRACE_URL（代理没开？${proxy:-未设置代理变量}）" \
      "⚠️  claude-guard: cannot reach $CLAUDE_GUARD_TRACE_URL (proxy not running? ${proxy:-no proxy variable set})"
    prompt=$(_claude_guard_text "   仍要启动 [y] / 中止 [N]: " "   Start anyway [y] / abort [N]: ")
  else
    entries=$(_claude_guard_entries | paste -sd ' ' -)
    if [[ -z $entries ]]; then
      _claude_guard_say \
        "🚫 claude-guard: 白名单为空（${(D)CLAUDE_GUARD_ALLOWLIST}），当前出口 IP 为 $ip" \
        "🚫 claude-guard: the allowlist is empty (${(D)CLAUDE_GUARD_ALLOWLIST}); the egress IP is $ip"
    else
      _claude_guard_say \
        "🚫 claude-guard: 出口 IP $ip 不在白名单（$entries）" \
        "🚫 claude-guard: egress IP $ip is not in the allowlist ($entries)"
      _claude_guard_say \
        "   可能原因：代理节点选错 / 当前 shell 关了代理 / 分流规则变化" \
        "   Possible causes: wrong proxy node, proxy disabled in this shell, changed routing rules"
    fi
    prompt=$(_claude_guard_text \
      "   仍要启动 [y] / 中止 [N] / 把 $ip 加入白名单并启动 [a]: " \
      "   Start anyway [y] / abort [N] / add $ip to the allowlist and start [a]: ")
  fi

  # Read the answer from the terminal, not stdin, so `echo x | claude -p` keeps its input.
  if ! { : < "$CLAUDE_GUARD_TTY" } 2>/dev/null; then
    _claude_guard_say \
      "   （没有可交互的终端，已中止；用 CLAUDE_GUARD_SKIP=1 跳过检查）" \
      "   (no terminal to ask on, aborted; set CLAUDE_GUARD_SKIP=1 to skip the check)"
    return 1
  fi
  print -u2 -n -r -- "$prompt"
  # On a terminal, plain `read -k` takes one key without Enter; `-u 0` is for a file.
  {
    if [[ -t 0 ]]; then read -k 1 reply; else read -k 1 -u 0 reply; fi
  } < "$CLAUDE_GUARD_TTY" || reply=
  print -u2 ""

  case $reply in
    [yY]) return 0 ;;
    [aA])
      [[ -n $ip ]] || return 1
      mkdir -p -- "${CLAUDE_GUARD_ALLOWLIST:h}" &&
        print -r -- "$ip" >> "$CLAUDE_GUARD_ALLOWLIST" || return 1
      _claude_guard_say "✅ 已把 $ip 加入 ${(D)CLAUDE_GUARD_ALLOWLIST}" \
        "✅ added $ip to ${(D)CLAUDE_GUARD_ALLOWLIST}"
      return 0 ;;
    *) return 1 ;;
  esac
}

# `claude-guard status`: show what the check sees, without starting claude.
# Exit status: 0 allowed, 1 not allowed, 2 claude.ai not reachable.
_claude_guard_status() {
  local ip proxy n entries secs rc
  zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null
  local -F t0=$EPOCHREALTIME
  ip=$(_claude_guard_exit_ip)
  secs=$(printf '%.1f' $(( EPOCHREALTIME - t0 )))
  entries=$(_claude_guard_entries | paste -sd ' ' -)
  n=$(_claude_guard_entries | grep -c .)
  local unit=entries
  (( n == 1 )) && unit=entry
  proxy=$(_claude_guard_proxy)

  if [[ -n $ip ]]; then
    _claude_guard_text "出口 IP   $ip（$secs 秒，$CLAUDE_GUARD_TRACE_URL）" \
      "egress IP   $ip  ($secs s, $CLAUDE_GUARD_TRACE_URL)"
  else
    _claude_guard_text "出口 IP   无（无法访问 $CLAUDE_GUARD_TRACE_URL，耗时 $secs 秒）" \
      "egress IP   none  (cannot reach $CLAUDE_GUARD_TRACE_URL, $secs s)"
  fi

  if [[ ! -e $CLAUDE_GUARD_ALLOWLIST ]]; then
    _claude_guard_text "白名单    ${(D)CLAUDE_GUARD_ALLOWLIST}（文件不存在）" \
      "allowlist   ${(D)CLAUDE_GUARD_ALLOWLIST}  (file not found)"
  else
    _claude_guard_text "白名单    ${(D)CLAUDE_GUARD_ALLOWLIST}（$n 条${entries:+：$entries}）" \
      "allowlist   ${(D)CLAUDE_GUARD_ALLOWLIST}  ($n $unit${entries:+: $entries})"
  fi

  _claude_guard_text "代理      ${proxy:-未设置代理变量}" "proxy       ${proxy:-no proxy variable set}"

  if [[ -z $ip ]]; then
    rc=2
    _claude_guard_text "结果      无法访问 claude.ai：启动 claude 时会询问" \
      "result      claude.ai not reachable: claude will ask before it starts"
  elif _claude_guard_allowed "$ip"; then
    rc=0
    _claude_guard_text "结果      在白名单：claude 直接启动" \
      "result      allowed: claude starts without asking"
  else
    rc=1
    _claude_guard_text "结果      不在白名单：启动 claude 时会询问" \
      "result      not allowed: claude will ask before it starts"
  fi

  [[ -n $CLAUDE_GUARD_SKIP ]] && _claude_guard_text \
    "注意      已设置 CLAUDE_GUARD_SKIP，claude 启动时跳过检查" \
    "note        CLAUDE_GUARD_SKIP is set, so claude skips the check"
  return rc
}

_claude_guard_usage() {
  _claude_guard_text "用法：claude-guard status   显示出口 IP、白名单和检查结果，不启动 claude
      退出码：0 在白名单，1 不在白名单，2 无法访问 claude.ai" \
    "usage: claude-guard status   show the egress IP, the allowlist and the result, without starting claude
       exit status: 0 allowed, 1 not allowed, 2 claude.ai not reachable"
}

function claude-guard {
  # In the Bash tool of Claude Code, functions starting with "_" are missing.
  if (( ! $+functions[_claude_guard_status] )); then
    print -u2 -r -- "claude-guard: helper functions are not loaded in this shell; run it in your own terminal"
    return 2
  fi
  case ${1:-help} in
    status) _claude_guard_status ;;
    help|-h|--help) _claude_guard_usage ;;
    *) _claude_guard_usage >&2; return 2 ;;
  esac
}

# `function name` syntax: still works when the user has an alias named claude.
function claude {
  case $1 in
    -h|--help|-v|--version) command claude "$@"; return ;;
  esac
  if [[ -n $CLAUDE_GUARD_SKIP ]]; then
    command claude "$@"; return
  fi
  # The Bash tool of Claude Code replays a snapshot of shell functions that keeps
  # claude() but drops functions starting with "_". The parent session already
  # passed the check, so let the call through instead of failing.
  if (( ! $+functions[_claude_guard_check] )); then
    command claude "$@"; return
  fi
  _claude_guard_check || return 1
  command claude "$@"
}
