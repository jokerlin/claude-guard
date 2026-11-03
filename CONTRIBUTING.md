# Contributing

English | [简体中文](#简体中文)

Bug reports, fixes and small features are welcome. For a larger change, open an issue first so we can agree on the approach.

## Develop

The plugin is one file, `claude-guard.plugin.zsh`. Try a change in a fresh shell:

```sh
zsh -f -c 'source ./claude-guard.plugin.zsh; claude --version'
```

## Test

```sh
zsh -n claude-guard.plugin.zsh   # syntax check
zsh tests/run.zsh                # all tests
```

The tests use fake `curl` and `claude` commands and make no network requests. `CLAUDE_GUARD_TTY` points the y/N/a prompt at a file, so tests can answer it. CI runs the same commands on Ubuntu and macOS.

Add a test for every behavior you change.

## Rules

- zsh only. Keep the plugin free of other dependencies than `curl`, `sed`, `grep` and `paste`.
- Every message needs an English and a Chinese text (`_claude_guard_say "中文" "English"`).
- Helper functions start with `_claude_guard_`. The `claude` wrapper must keep working when they are missing (see [docs/design.md](docs/design.md#claude-code-function-snapshots)).
- Use example IPs from RFC 5737 (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) in code, tests, docs and issues. Never commit a real IP.
- Update both READMEs and `CHANGELOG.md` under `[Unreleased]` when settings or behavior change.

## Release

There are no binary releases; users install from `main`. To mark a version, move the `[Unreleased]` entries in `CHANGELOG.md` under a new version heading, commit, and push a `vX.Y.Z` tag.

---

## 简体中文

欢迎报告 bug、提交修复和小功能。较大的改动请先开 issue，商定做法后再动手。

### 开发

插件只有一个文件 `claude-guard.plugin.zsh`。在干净的 shell 里试改动：

```sh
zsh -f -c 'source ./claude-guard.plugin.zsh; claude --version'
```

### 测试

```sh
zsh -n claude-guard.plugin.zsh   # 语法检查
zsh tests/run.zsh                # 全部测试
```

测试使用假的 `curl` 和 `claude`，不访问网络。`CLAUDE_GUARD_TTY` 把 y/N/a 的询问指向一个文件，测试借此作答。CI 在 Ubuntu 和 macOS 上运行同样的命令。

每个改动的行为都要加测试。

### 规则

- 只支持 zsh。插件除 `curl`、`sed`、`grep`、`paste` 外不引入其他依赖。
- 每条提示都要有中文和英文（`_claude_guard_say "中文" "English"`）。
- 辅助函数以 `_claude_guard_` 开头。辅助函数缺失时，`claude` 包装函数必须仍能工作（见 [docs/design.md](docs/design.md#claude-code-function-snapshots)）。
- 代码、测试、文档和 issue 里只用 RFC 5737 的示例 IP（`192.0.2.x`、`198.51.100.x`、`203.0.113.x`）。不得提交真实 IP。
- 设置项或行为变化时，同时更新两份 README，并在 `CHANGELOG.md` 的 `[Unreleased]` 下记录。

### 发版

不发二进制 release，用户直接从 `main` 安装。标记版本时，把 `CHANGELOG.md` 里 `[Unreleased]` 的条目移到新版本标题下，提交后推送 `vX.Y.Z` tag。
