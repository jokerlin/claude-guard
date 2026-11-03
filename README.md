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

## Check without starting claude

```
$ claude-guard status
egress IP   192.0.2.9  (0.4 s, https://claude.ai/cdn-cgi/trace)
allowlist   ~/.config/claude-guard/allowed-ips  (1 entry: 203.0.113.7)
proxy       https_proxy=http://127.0.0.1:7890
result      not allowed: claude will ask before it starts
```

The exit status is 0 when the IP is allowed, 1 when it is not, and 2 when claude.ai cannot be reached, so scripts can use it too. A user name and password in the proxy URL are shown as `***`.

## Skip the check

```sh
CLAUDE_GUARD_SKIP=1 claude ...   # skip once
command claude ...               # call the real binary
```

Inside a Claude Code session, the Bash tool replays your shell functions without claude-guard's helper functions. In that case the wrapper lets `claude` through, because the parent session already passed the check.

## What is not checked

claude-guard wraps `claude` in interactive zsh only. Claude Code started in these ways does not go through the check:

- IDE extensions and desktop apps that start the claude binary themselves, instead of typing `claude` into a terminal
- scripts, cron jobs and `ssh host 'claude ...'` (no interactive zsh)
- bash, fish and other shells
- `command claude` and `CLAUDE_GUARD_SKIP=1`, which skip the check on purpose

In these cases, run `claude-guard status` first to see the IP that claude.ai will see.

The check also runs once, at launch. If the proxy changes while a session is open, claude-guard does not notice.

## Settings

Set these in `~/.zshrc` before the plugin is loaded.

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_GUARD_ALLOWLIST` | `${XDG_CONFIG_HOME:-~/.config}/claude-guard/allowed-ips` | Path of the allowlist |
| `CLAUDE_GUARD_TIMEOUT` | `10` | Seconds to wait for claude.ai. Slow proxies can need 6 s or more |
| `CLAUDE_GUARD_TRACE_URL` | `https://claude.ai/cdn-cgi/trace` | URL that returns an `ip=` line |
| `CLAUDE_GUARD_LANG` | from `LC_ALL`, `LC_MESSAGES`, `LANG` | `zh` for Chinese messages, `en` for English |
| `CLAUDE_GUARD_SKIP` | unset | Any value skips the check |

## Privacy

Each launch makes one HTTPS request to `claude.ai`. claude-guard sends nothing anywhere else and stores nothing except the allowlist file.

## Uninstall

Remove the `source` line (or the plugin entry) from `~/.zshrc`, then delete the cloned directory and `~/.config/claude-guard`.

## More

- [Design notes](docs/design.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE)
