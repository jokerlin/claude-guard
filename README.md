# claude-guard

English | [简体中文](README.zh-CN.md)

A zsh plugin that checks your egress IP before [Claude Code](https://docs.anthropic.com/en/docs/claude-code) starts. If the IP that claude.ai sees is not on your allowlist, `claude` stops and asks before it connects.

![claude-guard stops claude on an unknown egress IP, then adds it to the allowlist with one key](docs/demo.gif)

## Why

You may send Claude Code through a fixed egress: a proxy, a VPN, or a company gateway. When the proxy is off, the wrong node is selected, or a shell has the proxy variables unset, claude connects from an IP you did not expect. claude-guard catches this before claude sends its first request.

- **Same path as claude.** The check requests `https://claude.ai/cdn-cgi/trace` with the same proxy variables as claude, so proxy routing rules give the same answer. An IP echo service on another domain can go through a different proxy node.
- **Before launch.** A Claude Code hook runs after claude has started and may already have sent requests. claude-guard wraps the `claude` command, so nothing starts until the check passes.
- **Stays out of the way.** The answer is read from the terminal, not stdin, so `echo x | claude -p` still works. Scripts and cron jobs that run claude without an interactive zsh are not affected.

## Requirements

- zsh 5.x (macOS default shell, or any Linux with zsh)
- `curl`

## Install

Pick one.

**Plain zsh**

```sh
git clone https://github.com/jokerlin/claude-guard.git ~/.claude-guard
echo 'source ~/.claude-guard/claude-guard.plugin.zsh' >> ~/.zshrc
```

**Oh My Zsh**

```sh
git clone https://github.com/jokerlin/claude-guard.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/claude-guard
```

Then add `claude-guard` to `plugins=(...)` in `~/.zshrc`.

**zinit / antidote**

```sh
zinit light jokerlin/claude-guard        # zinit
echo jokerlin/claude-guard >> ~/.zsh_plugins.txt   # antidote
```

Open a new terminal after you install.

## Set up the allowlist

The allowlist is a text file with one IP per line. `#` starts a comment.

```sh
mkdir -p ~/.config/claude-guard
cp allowed-ips.example ~/.config/claude-guard/allowed-ips   # then edit it
```

You can also skip this step: on the first run, the list is empty, and you press `a` to add the current IP.

To see your current egress IP:

```sh
curl -s https://claude.ai/cdn-cgi/trace | grep ^ip=
```

Entries must match exactly. IP ranges (CIDR) are not supported.

## What happens on launch

| Situation | Result |
|---|---|
| Egress IP is on the allowlist | claude starts |
| Egress IP is not on the allowlist | Asks: `y` start anyway, `a` add the IP and start, `N` (default) abort |
| The request to claude.ai fails (proxy down, timeout) | Asks: `y` start anyway, `N` (default) abort |
| No terminal to ask on (for example, inside a pipeline without a tty) | Aborts |

`claude -h`, `--help`, `-v` and `--version` skip the check, because they do not connect.

`y` starts the session with `CLAUDE_GUARD_SKIP=1`, so the [prompt hook](#check-every-prompt-claude-code-hook) does not block it either.

## Check without starting claude

```
$ claude-guard status
egress IP   192.0.2.9  (0.4 s, https://claude.ai/cdn-cgi/trace)
allowlist   ~/.config/claude-guard/allowed-ips  (1 entry: 203.0.113.7)
proxy       https_proxy=http://127.0.0.1:7890
result      not allowed: claude will ask before it starts
```

The exit status is 0 when the IP is allowed, 1 when it is not, and 2 when claude.ai cannot be reached, so scripts can use it too. A user name and password in the proxy URL are shown as `***`.

## Check every prompt (Claude Code hook)

The wrapper checks once, at launch. To also check before each prompt, add the hook to `~/.claude/settings.json`. Use the path where you cloned claude-guard:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "zsh ~/.claude-guard/claude-guard-hook.zsh",
            "timeout": 15,
            "onFailure": "block"
          }
        ]
      }
    ]
  }
}
```

Before each prompt, the hook checks the egress IP the same way as the wrapper. When the IP is not on the allowlist, or claude.ai cannot be reached, Claude Code does not send the prompt and shows why, with a command to allow the IP:

```
claude-guard: egress IP 192.0.2.9 is not in the allowlist (203.0.113.7). The prompt was not sent.
Fix the proxy and send the prompt again, or allow this IP:
  echo 192.0.2.9 >> ~/.config/claude-guard/allowed-ips
```

You can run that command inside Claude Code with the `!` prefix, then send the prompt again.

- A passed check is reused for 60 seconds (`CLAUDE_GUARD_HOOK_TTL`), so most prompts wait for no request. The wrapper's check at launch counts too. A session with other proxy variables does not reuse it.
- `"onFailure": "block"` blocks the prompt if the hook itself fails or times out. It needs Claude Code 2.1.295 or later.
- The hook runs with the environment of the claude process. Settings in `~/.zshrc` reach it only when they are exported (`export CLAUDE_GUARD_LANG=zh`), or set them under `env` in `settings.json`.
- The hook works wherever Claude Code runs, also in IDE extensions, scripts and other shells. It needs zsh to be installed.


```sh
CLAUDE_GUARD_SKIP=1 claude ...   # skip once
command claude ...               # call the real binary
```

Inside a Claude Code session, the Bash tool replays your shell functions without claude-guard's helper functions. In that case the wrapper lets `claude` through, because the parent session already passed the check.

## What is not checked

The wrapper works in interactive zsh only. Claude Code started in these ways does not go through the launch check:

- IDE extensions and desktop apps that start the claude binary themselves, instead of typing `claude` into a terminal
- scripts, cron jobs and `ssh host 'claude ...'` (no interactive zsh)
- bash, fish and other shells
- `command claude` and `CLAUDE_GUARD_SKIP=1`, which skip the check on purpose

The [prompt hook](#check-every-prompt-claude-code-hook) covers the first three before each prompt. Without the hook, run `claude-guard status` first to see the IP that claude.ai will see.

Even with the hook, some requests are not checked:

- requests during a turn: Claude sends requests between tool calls without a new prompt, so a proxy change in the middle of a turn is caught at the next prompt
- requests that Claude Code makes in the background, and the requests at session start (only the wrapper covers those)
- up to 60 seconds after a passed check (`CLAUDE_GUARD_HOOK_TTL`)

With `claude -p`, a blocked prompt prints the reason but the exit status is still 0. Scripts cannot tell a blocked prompt from the exit status.

## Settings

Set these in `~/.zshrc` before the plugin is loaded. For the prompt hook, export them or set them under `env` in `~/.claude/settings.json`.

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_GUARD_ALLOWLIST` | `${XDG_CONFIG_HOME:-~/.config}/claude-guard/allowed-ips` | Path of the allowlist |
| `CLAUDE_GUARD_TIMEOUT` | `10` | Seconds to wait for claude.ai. Slow proxies can need 6 s or more |
| `CLAUDE_GUARD_TRACE_URL` | `https://claude.ai/cdn-cgi/trace` | URL that returns an `ip=` line |
| `CLAUDE_GUARD_LANG` | from `LC_ALL`, `LC_MESSAGES`, `LANG` | `zh` for Chinese messages, `en` for English |
| `CLAUDE_GUARD_HOOK_TTL` | `60` | Seconds the prompt hook reuses a passed check. `0` checks every prompt |
| `CLAUDE_GUARD_SKIP` | unset | Any value skips the check and the prompt hook |

## Privacy

Each check makes one HTTPS request to `claude.ai`. claude-guard sends nothing anywhere else. It stores the allowlist, and the time, IP and a checksum of the proxy variables of the last passed check in `${XDG_CACHE_HOME:-~/.cache}/claude-guard/last-ok`.

## Uninstall

Remove the `source` line (or the plugin entry) from `~/.zshrc` and the hook from `~/.claude/settings.json`, then delete the cloned directory, `~/.config/claude-guard` and `~/.cache/claude-guard`.

## More

- [Design notes](docs/design.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE)
