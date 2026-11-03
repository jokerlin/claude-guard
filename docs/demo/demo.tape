# Records docs/demo.gif (English) or docs/demo.zh-CN.gif (Chinese).
# Run from the repository root:
#   vhs docs/demo/demo.tape                         (English)
#   DEMO_LANG=zh vhs docs/demo/demo.tape -o docs/demo.zh-CN.gif
Output docs/demo.gif

Set Shell zsh
Set FontSize 18
Set FontFamily "JetBrains Maple Mono"
Set Width 1240
Set Height 360
Set Padding 24
Set WindowBar Colorful
Set TypingSpeed 60ms
Set Theme "Catppuccin Mocha"

Hide
Type `exec env -i TERM=xterm-256color LANG=en_US.UTF-8 DEMO_LANG=${DEMO_LANG:-en} PS1='%F{blue}$%f ' /bin/zsh -f`
Enter
Type `source docs/demo/setup.zsh $DEMO_LANG && clear`
Enter
Sleep 500ms
Show

Type "cat ~/.config/claude-guard/allowed-ips"
Sleep 300ms
Enter
Sleep 1.2s

Type "claude"
Sleep 300ms
Enter
Sleep 3s
Type "a"
Sleep 2.5s

Type "claude"
Sleep 300ms
Enter
Sleep 2.5s
