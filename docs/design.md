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

## Prompt hook

The wrapper checks once. A `UserPromptSubmit` hook (`claude-guard-hook.zsh`) checks again before each prompt. Facts it relies on, checked against Claude Code 2.1.317 on 2026-11-03:

- Exit 2 from a `UserPromptSubmit` hook blocks the prompt; Claude Code shows stderr to the user and keeps it out of the model context. The block message ends with the original prompt, and the prompt goes back to the input box.
- The hook inherits the environment of the claude process, including variables set under `env` in `settings.json`. So the hook's request uses the same proxy variables as claude.
- With `"onFailure": "block"` (Claude Code 2.1.295+), a hook that crashes or times out blocks the prompt instead of letting it through.
- With `claude -p`, a blocked prompt prints the reason and exits 0.

```
prompt ──► hook
            ├─ CLAUDE_GUARD_SKIP set                      → pass
            ├─ cache: passed < TTL ago, same proxy vars,
            │         IP still on the allowlist           → pass (no request)
            ├─ request trace URL
            │    ├─ IP allowed       → pass, write cache
            │    ├─ IP not allowed   → exit 2 + command to allow it
            │    └─ request failed   → exit 2
            └─ hook fails / times out → blocked by onFailure
```

Decisions:

- **Cache only passes.** `${XDG_CACHE_HOME:-~/.cache}/claude-guard/last-ok` holds `<epoch> <ip> <cksum of proxy variables>`. The wrapper writes it too, so the first prompt after launch needs no request. The checksum keeps a session with other proxy variables from reusing it, without writing a proxy password to disk. The IP is checked against the allowlist again, so removing it takes effect at once.
- **Fail closed.** If claude.ai cannot be reached, the prompt is blocked: claude would not get through that proxy either.
- **"Start anyway" skips the hook.** `y` at launch starts claude with `CLAUDE_GUARD_SKIP=1`; otherwise the hook would block every prompt of that session.
- **A pasteable fix.** The block message ends with `claude-guard add <ip>`, to run with the `!` prefix in Claude Code. It shows the bare name when the user's own `PATH` (before the plugin changed it) finds this copy, or when the hook runs from the Claude Code plugin, whose `bin/` is on the `PATH` of the Bash tool. Otherwise it shows the full path.
- **Exit 2 instead of JSON.** stderr becomes the block message, so no JSON escaping is needed.

Limits: requests within a turn (between tool calls), background requests and the requests at session start do not pass through the hook.

## The claude-guard command

`claude-guard` (`status`, `add`, `remove`) is a program in `bin/` that sources the plugin, not a shell function. The Bash tool of Claude Code keeps `PATH` and exported variables but drops functions whose names start with `_`, so a function would fail there. The zsh plugin appends `bin/` to `PATH`; the Claude Code plugin gets `bin/` on the `PATH` of the Bash tool from Claude Code.

- `add` without an IP adds the egress IP and writes the cache, so the next prompt passes without a request. With an IP, it checks the format (IPv4 with parts 0-255, or IPv6) and lowercases it.
- `add` writes `<ip>    # added YYYY-MM-DD`, and starts a new line first when the file does not end with one.
- `remove` needs an explicit IP and deletes only the lines whose entry is that IP. It writes a temporary file and renames it.
- The `a` answer at launch uses the same code as `add`.

## Claude Code plugin

The repository is also a Claude Code plugin and its own marketplace:

- `.claude-plugin/plugin.json`: the plugin `egress-claude-guard`. `claude plugin validate` rejects names that start with `claude-`, and warns that a name with `claude` in it reads as one of Anthropic's own.
- `.claude-plugin/marketplace.json`: the marketplace `jokerlin`, with one entry whose source is `./`.
- `hooks/hooks.json`: the `UserPromptSubmit` hook, `zsh "${CLAUDE_PLUGIN_ROOT}/claude-guard-hook.zsh"`, timeout 15, `onFailure: block`.
- `bin/claude-guard`: on the `PATH` of the Bash tool while the plugin is enabled.

The plugin cannot change the user's shell, so the launch check still needs the zsh plugin. The release workflow refuses a tag whose version differs from `plugin.json`.

Seen in Claude Code 2.1.317: a line that starts with `!` runs the command, and Claude then answers its output without a `UserPromptSubmit` event, so the prompt hook does not check that model call.

## Claude Code function snapshots

When Claude Code runs its Bash tool, it replays a snapshot of the user's shell functions. The snapshot keeps `claude()` but drops functions whose names start with `_`. Without its helpers, the wrapper would fail with "command not found". The wrapper checks for `_claude_guard_check` and lets the call through when it is missing: the parent session passed the check when it started. The `claude-guard` command is not affected, because it is a separate program.

## Scope

- Only interactive zsh. Scripts, cron jobs, other shells, and IDE extensions or desktop apps that start the claude binary themselves call the real `claude` directly. `claude-guard status` shows what the check would see, for these cases and for debugging a proxy.
- The wrapper checks only at launch; the optional prompt hook checks before each prompt, with the limits above.
- No CIDR ranges, no IPv4/IPv6 normalization.
