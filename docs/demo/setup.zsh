# Demo environment for the README GIFs. Sourced by demo.tape inside `zsh -f`.
# Fake curl and claude, a temporary HOME, and RFC 5737 example IPs only.
# Usage: source docs/demo/setup.zsh <en|zh>
emulate -L zsh
local root=${${(%):-%x}:A:h:h:h}
DEMO=$(mktemp -d)
mkdir -p $DEMO/bin $DEMO/home/.config/claude-guard
# The egress IP that the fake trace endpoint reports (a "wrong" proxy node).
cat > $DEMO/bin/curl <<'EOS'
#!/bin/sh
sleep 0.6
printf 'fl=1\nh=claude.ai\nip=192.0.2.9\nts=1\n'
EOS
cat > $DEMO/bin/claude <<'EOS'
#!/bin/sh
printf '\033[38;5;173m✻\033[0m claude started\n'
EOS
chmod +x $DEMO/bin/curl $DEMO/bin/claude
print '203.0.113.7    # home connection' > $DEMO/home/.config/claude-guard/allowed-ips
export HOME=$DEMO/home PATH=$DEMO/bin:/usr/bin:/bin CLAUDE_GUARD_LANG=${1:-en}
unset CLAUDE_GUARD_ALLOWLIST
source $root/claude-guard.plugin.zsh
