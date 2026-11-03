# Security policy

English | [简体中文](#简体中文)

## Report a vulnerability

Do not open a public issue for a security problem. Report it privately: open the repository's **Security** tab and click **Report a vulnerability** ([direct link](https://github.com/jokerlin/claude-guard/security/advisories/new)).

Include what an attacker can do and the steps to reproduce. You should get a reply within 7 days.

## Scope

In scope:

- Ways to make the check pass when the egress IP is not on the allowlist.
- Input from the trace response or the allowlist file that makes the plugin run commands or write files it should not.

Out of scope:

- An attacker who can already edit your `~/.zshrc`, the plugin file or the allowlist.
- `CLAUDE_GUARD_SKIP` and `command claude`: they skip the check by design.
- claude-guard is a guard against mistakes, not a sandbox. Anything that runs `claude` without your interactive zsh is not checked.

---

## 简体中文

### 报告漏洞

安全问题不要开公开 issue。请私下报告：打开仓库的 **Security** 标签页，点击 **Report a vulnerability**（[直达链接](https://github.com/jokerlin/claude-guard/security/advisories/new)）。

写明攻击者能做什么，以及复现步骤。7 天内会有回复。

### 范围

属于范围内：

- 出口 IP 不在白名单时，仍能让检查通过的方法。
- trace 响应或白名单文件中的内容，导致插件执行了不该执行的命令或写了不该写的文件。

不属于范围内：

- 攻击者已经能修改你的 `~/.zshrc`、插件文件或白名单。
- `CLAUDE_GUARD_SKIP` 和 `command claude`：它们按设计跳过检查。
- claude-guard 用来防止失误，不是沙箱。不经过你的交互式 zsh 运行的 `claude` 不受检查。
