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

## Demo GIFs

When messages change, record the GIFs again with [VHS](https://github.com/charmbracelet/vhs) from the repository root. The tape uses the font JetBrains Maple Mono, so Chinese text lines up with the grid.

```sh
vhs docs/demo/demo.tape
DEMO_LANG=zh vhs docs/demo/demo.tape -o docs/demo.zh-CN.gif
```

The demo runs in `zsh -f` with fake `curl` and `claude` and example IPs (see `docs/demo/setup.zsh`).

## Rules

- zsh only. Keep the plugin free of other dependencies than `curl`, `sed`, `grep` and `paste`.
- Every message needs an English and a Chinese text (`_claude_guard_say "中文" "English"`).
- Helper functions start with `_claude_guard_`. The `claude` wrapper must keep working when they are missing (see [docs/design.md](docs/design.md#claude-code-function-snapshots)).
- Use example IPs from RFC 5737 (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) in code, tests, docs and issues. Never commit a real IP.
- Update both READMEs and `CHANGELOG.md` under `[Unreleased]` when settings or behavior change.

## Release

Users install from `main`; a release marks a version and lists its changes.

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new heading `## [X.Y.Z] - YYYY-MM-DD`, update the links at the bottom, set `"version": "X.Y.Z"` in `.claude-plugin/plugin.json`, and merge that through a pull request.
2. Tag the merge commit on `main` and push the tag:

   ```sh
   git tag -a vX.Y.Z -m "claude-guard X.Y.Z" && git push origin vX.Y.Z
   ```

The `Release` workflow then runs the tests and publishes a GitHub release with the `[X.Y.Z]` section of `CHANGELOG.md` plus a compare link to the previous tag. It stops without a release when the tests fail, the section is missing, or the version in `plugin.json` is not `X.Y.Z`.

To check the notes first, run the workflow by hand: **Actions → Release → Run workflow** with the version (or `gh workflow run release.yml -f version=X.Y.Z`). This dry run creates no release. `sh scripts/release-notes.sh X.Y.Z` prints the same section locally.

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

### 演示 GIF

提示语变化时，在仓库根目录用 [VHS](https://github.com/charmbracelet/vhs) 重录 GIF。录制脚本使用字体 JetBrains Maple Mono，中文才能和字符网格对齐。

```sh
vhs docs/demo/demo.tape
DEMO_LANG=zh vhs docs/demo/demo.tape -o docs/demo.zh-CN.gif
```

演示在 `zsh -f` 里运行，使用假的 `curl`、`claude` 和示例 IP（见 `docs/demo/setup.zsh`）。

### 规则

- 只支持 zsh。插件除 `curl`、`sed`、`grep`、`paste` 外不引入其他依赖。
- 每条提示都要有中文和英文（`_claude_guard_say "中文" "English"`）。
- 辅助函数以 `_claude_guard_` 开头。辅助函数缺失时，`claude` 包装函数必须仍能工作（见 [docs/design.md](docs/design.md#claude-code-function-snapshots)）。
- 代码、测试、文档和 issue 里只用 RFC 5737 的示例 IP（`192.0.2.x`、`198.51.100.x`、`203.0.113.x`）。不得提交真实 IP。
- 设置项或行为变化时，同时更新两份 README，并在 `CHANGELOG.md` 的 `[Unreleased]` 下记录。

### 发版

用户直接从 `main` 安装；Release 用来标记版本、列出改动。

1. 把 `CHANGELOG.md` 里 `[Unreleased]` 的条目移到新标题 `## [X.Y.Z] - YYYY-MM-DD` 下，更新底部链接，把 `.claude-plugin/plugin.json` 里的 `"version"` 改成 `X.Y.Z`，通过 PR 合入。
2. 在 `main` 的合并提交上打 tag 并推送：

   ```sh
   git tag -a vX.Y.Z -m "claude-guard X.Y.Z" && git push origin vX.Y.Z
   ```

之后 `Release` 工作流会跑测试，并用 `CHANGELOG.md` 里 `[X.Y.Z]` 那一段加上和上一个 tag 的对比链接，发布 GitHub Release。测试失败、找不到这一段，或 `plugin.json` 的版本不是 `X.Y.Z` 时，工作流中止，不发 Release。

想先看 notes，手动运行工作流：**Actions → Release → Run workflow**，填入版本号（或 `gh workflow run release.yml -f version=X.Y.Z`）。这是 dry run，不会创建 Release。本地运行 `sh scripts/release-notes.sh X.Y.Z` 也能看到同一段内容。
