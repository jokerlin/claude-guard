# claude-guard

[English](README.md) | 简体中文

一个 zsh 插件：在 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 启动前校验出口 IP。claude.ai 看到的 IP 不在白名单时，`claude` 先停下来询问，不会直接连接。

![claude-guard 在出口 IP 不在白名单时拦下 claude，按一个键把它加入白名单](docs/demo.zh-CN.gif)

## 为什么需要

你可能让 Claude Code 固定走某个出口：代理、VPN 或公司网关。代理没开、节点选错、或者某个 shell 里清掉了代理变量时，claude 会从一个意料之外的 IP 连接。claude-guard 在 claude 发出第一个请求前发现这个问题。

- **和 claude 走同一条路。** 检查请求 `https://claude.ai/cdn-cgi/trace`，用的代理变量和 claude 相同，分流规则给出的结果也相同。换成其他域名的 IP 回显服务，可能走另一个代理节点。
- **在启动前检查。** Claude Code 的 hook 在 claude 启动后才运行，那时可能已经发出请求。claude-guard 包装 `claude` 命令，检查通过前什么都不启动。
- **不干扰正常用法。** 回答从终端读取，不读 stdin，所以 `echo x | claude -p` 照常可用。脚本和 cron 不经过交互式 zsh 调用 claude，不受影响。

## 环境要求

- zsh 5.x（macOS 默认 shell，或装了 zsh 的 Linux）
- `curl`

## 安装

任选一种。

**直接 source**

```sh
git clone https://github.com/jokerlin/claude-guard.git ~/.claude-guard
echo 'source ~/.claude-guard/claude-guard.plugin.zsh' >> ~/.zshrc
```

**Oh My Zsh**

```sh
git clone https://github.com/jokerlin/claude-guard.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/claude-guard
```

然后在 `~/.zshrc` 的 `plugins=(...)` 里加上 `claude-guard`。

**zinit / antidote**

```sh
zinit light jokerlin/claude-guard        # zinit
echo jokerlin/claude-guard >> ~/.zsh_plugins.txt   # antidote
```

装完后新开一个终端。

## 配置白名单

白名单是文本文件，一行一个 IP，`#` 开头为注释。

```sh
mkdir -p ~/.config/claude-guard
cp allowed-ips.example ~/.config/claude-guard/allowed-ips   # 然后编辑
```

也可以跳过这一步：第一次运行时白名单为空，按 `a` 把当前 IP 加进去。

查看当前出口 IP：

```sh
curl -s https://claude.ai/cdn-cgi/trace | grep ^ip=
```

白名单按完整字符串匹配，不支持 IP 段（CIDR）。

## 启动时的行为

| 场景 | 结果 |
|---|---|
| 出口 IP 在白名单 | 直接启动 claude |
| 出口 IP 不在白名单 | 询问：`y` 仍要启动，`a` 加入白名单并启动，`N`（默认）中止 |
| 访问 claude.ai 失败（代理没开、超时） | 询问：`y` 仍要启动，`N`（默认）中止 |
| 没有可交互的终端（例如管道里拿不到 tty） | 中止 |

`claude -h`、`--help`、`-v`、`--version` 不联网，跳过检查。

## 不启动 claude，只看检查结果

```
$ claude-guard status
出口 IP   192.0.2.9（0.4 秒，https://claude.ai/cdn-cgi/trace）
白名单    ~/.config/claude-guard/allowed-ips（1 条：203.0.113.7）
代理      https_proxy=http://127.0.0.1:7890
结果      不在白名单：启动 claude 时会询问
```

退出码：在白名单为 0，不在为 1，无法访问 claude.ai 为 2，脚本里也能用。代理地址里的用户名和密码显示为 `***`。

## 跳过检查

```sh
CLAUDE_GUARD_SKIP=1 claude ...   # 跳过一次
command claude ...               # 直接调用真正的 claude
```

在 Claude Code 会话里，Bash 工具会重放你的 shell 函数，但不带 claude-guard 的辅助函数。这种情况下包装函数直接放行，因为父会话启动时已经通过了检查。

## 不受检查的情况

claude-guard 只在交互式 zsh 里包装 `claude`。用下面这些方式启动 Claude Code 时，不经过检查：

- IDE 扩展和桌面 App 自己启动 claude 程序，而不是在终端里输入 `claude`
- 脚本、cron 和 `ssh host 'claude ...'`（没有交互式 zsh）
- bash、fish 等其他 shell
- `command claude` 和 `CLAUDE_GUARD_SKIP=1`，它们按设计跳过检查

这些情况下，先运行 `claude-guard status`，看 claude.ai 将会看到的 IP。

检查只在启动时运行一次。会话进行中代理变了，claude-guard 发现不了。

## 设置项

在 `~/.zshrc` 里、加载插件之前设置。

| 变量 | 默认值 | 含义 |
|---|---|---|
| `CLAUDE_GUARD_ALLOWLIST` | `${XDG_CONFIG_HOME:-~/.config}/claude-guard/allowed-ips` | 白名单路径 |
| `CLAUDE_GUARD_TIMEOUT` | `10` | 等待 claude.ai 的秒数。慢代理可能要 6 秒以上 |
| `CLAUDE_GUARD_TRACE_URL` | `https://claude.ai/cdn-cgi/trace` | 返回 `ip=` 行的地址 |
| `CLAUDE_GUARD_LANG` | 取自 `LC_ALL`、`LC_MESSAGES`、`LANG` | `zh` 显示中文，`en` 显示英文 |
| `CLAUDE_GUARD_SKIP` | 未设置 | 设为任意值即跳过检查 |

注意：`LC_ALL` 优先于 `LANG`。如果你设了 `LC_ALL=en_US.UTF-8` 又想看中文，设置 `CLAUDE_GUARD_LANG=zh`。

## 隐私

每次启动向 `claude.ai` 发一个 HTTPS 请求。claude-guard 不向其他地方发送任何数据，除了白名单文件不存储任何东西。

## 卸载

从 `~/.zshrc` 删掉 `source` 行（或插件条目），再删除克隆的目录和 `~/.config/claude-guard`。

## 更多

- [设计说明](docs/design.md)（英文）
- [贡献指南](CONTRIBUTING.md#简体中文)
- [安全策略](SECURITY.md#简体中文)
- [更新日志](CHANGELOG.md)

## 许可证

[MIT](LICENSE)
