# Design notes

## Goal

Stop `claude` from starting when the egress IP that claude.ai sees is not one the user approved. The check must run before claude sends any request.

## How the IP is measured

claude-guard requests `https://claude.ai/cdn-cgi/trace` (a Cloudflare endpoint that echoes the client) and reads the `ip=` line.

This request uses the same proxy environment variables as claude and goes to the same domain, so proxy routing rules (for example, Clash or mihomo rules by domain) send it through the same node. An echo service on another domain, such as ipinfo.io, can match a different rule and report a different IP.

## Why a shell function

```
interactive zsh
  └─ claude()                     wrapper function from the plugin
       ├─ -h/--help/-v/--version  → command claude
       ├─ CLAUDE_GUARD_SKIP set   → command claude
       ├─ helpers missing         → command claude   (function snapshot, see below)
       └─ _claude_guard_check
            ├─ pass               → command claude
            └─ fail               → return 1
```

Options that were ruled out:

- **A standalone script on PATH.** It still needs a shell function or alias to shadow `claude`, so it adds a layer without removing one.
- **A Claude Code `SessionStart` hook.** The hook runs after claude has started, and claude may already have connected. It cannot block in advance.

The code has a pure core (read the IP, read the allowlist, match) and a thin shell around it (ask the user, append to the allowlist, start claude).

## Decisions

- **Answer from the terminal.** The y/N/a answer is read from `/dev/tty` with `read -k 1`, one key and no Enter. Stdin is left alone, so `echo x | claude -p ...` keeps its input.
- **No terminal means abort.** When `/dev/tty` cannot be opened, the check fails closed and tells the user about `CLAUDE_GUARD_SKIP=1`.
- **`a` only with an IP.** When the request fails there is no IP to add, so `a` aborts.
- **Allowlist outside the repo.** The list is personal data and lives in `${XDG_CONFIG_HOME:-~/.config}/claude-guard/allowed-ips`. The repo ships `allowed-ips.example`.
- **Exact match.** Entries are compared as whole strings. Inline `#` comments and spaces are stripped.
- **Timeout 10 s.** Through some proxies, claude.ai takes about 6 s to answer; 5 s caused false "cannot reach" results.
- **`function claude` syntax.** With `claude() { ... }`, zsh expands an existing alias named `claude` first and fails. `function claude { ... }` does not expand aliases.

## Claude Code function snapshots

When Claude Code runs its Bash tool, it replays a snapshot of the user's shell functions. The snapshot keeps `claude()` but drops functions whose names start with `_`. Without its helpers, the wrapper would fail with "command not found". The wrapper checks for `_claude_guard_check` and lets the call through when it is missing: the parent session passed the check when it started.

## Scope

- Only interactive zsh. Scripts, cron jobs, other shells, and IDE extensions or desktop apps that start the claude binary themselves call the real `claude` directly. `claude-guard status` shows what the check would see, for these cases and for debugging a proxy.
- Only at launch. A proxy change during a session is not noticed.
- No CIDR ranges, no IPv4/IPv6 normalization.
