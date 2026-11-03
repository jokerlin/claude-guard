# Changelog

All notable changes to claude-guard. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-03

### Added

- `claude-guard add [IP]` adds an IP to the allowlist with the date as a comment; without IP, it adds the current egress IP. `claude-guard remove IP` removes one and keeps the other lines and comments.
- Claude Code plugin `egress-claude-guard` in the marketplace `jokerlin` (this repository): `/plugin marketplace add jokerlin/claude-guard`, then `/plugin install egress-claude-guard@jokerlin`. It registers the prompt hook and puts the `claude-guard` command on the `PATH` of the Bash tool.

### Changed

- `claude-guard` is now a program in `bin/` instead of a shell function, so it also works inside Claude Code with the `!` prefix. The zsh plugin puts `bin/` on `PATH`.
- The prompt hook suggests `claude-guard add <ip>` instead of an `echo` command.
- Answering `a` at launch writes the IP with a date comment, the same way as `claude-guard add`.

### Fixed

- Adding an IP to an allowlist that does not end with a newline no longer joins it to the last line.
- The README heading "Skip the check" was missing since 1.1.0.

## [1.1.0] - 2026-11-03

### Added

- Prompt hook `claude-guard-hook.zsh` for Claude Code (`UserPromptSubmit`): checks the egress IP before each prompt and blocks the prompt when the IP is not allowed or claude.ai cannot be reached. It also covers Claude Code started from IDE extensions, scripts and other shells. A passed check is reused for `CLAUDE_GUARD_HOOK_TTL` seconds (default 60) with the same proxy variables.
- `claude-guard status` shows the egress IP, the allowlist, the proxy variable and the result without starting claude. Exit status 0 allowed, 1 not allowed, 2 claude.ai not reachable.
- README section "What is not checked": IDE extensions and desktop apps that start claude themselves, scripts, other shells, and proxy changes during a session.
- Demo GIFs in both READMEs, recorded from `docs/demo/demo.tape`.

### Changed

- `y` (start anyway) starts claude with `CLAUDE_GUARD_SKIP=1`, so the prompt hook does not block that session.
- Messages show the allowlist path with `~` for the home directory.
- A user name and password in the proxy URL are shown as `***`. The "cannot reach" message shows `HTTPS_PROXY` or `all_proxy` when `https_proxy` is not set.

## [1.0.0] - 2026-11-03

First public release.

### Added

- `claude` wrapper that checks the egress IP from `https://claude.ai/cdn-cgi/trace` against an allowlist before Claude Code starts, and asks `y` / `a` / `N` on a mismatch.
- Allowlist at `${XDG_CONFIG_HOME:-~/.config}/claude-guard/allowed-ips`, with inline `#` comments.
- Settings `CLAUDE_GUARD_ALLOWLIST`, `CLAUDE_GUARD_TIMEOUT`, `CLAUDE_GUARD_TRACE_URL`, `CLAUDE_GUARD_LANG`, `CLAUDE_GUARD_SKIP`.
- English and Chinese messages, chosen from the locale.
- Loads as a plugin in Oh My Zsh, zinit and antidote (`claude-guard.plugin.zsh`).

[Unreleased]: https://github.com/jokerlin/claude-guard/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/jokerlin/claude-guard/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/jokerlin/claude-guard/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jokerlin/claude-guard/releases/tag/v1.0.0
