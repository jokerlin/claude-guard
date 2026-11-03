#!/usr/bin/env zsh
# claude-guard hook for Claude Code: checks the egress IP before each prompt.
# Add it to ~/.claude/settings.json as a UserPromptSubmit command hook (see README).
#
# Exit 0 lets the prompt through; exit 2 blocks it and Claude Code shows stderr.
# The hook runs with the environment of the claude process, so it sees the same
# proxy variables as claude.
emulate zsh
cat > /dev/null   # the hook input (JSON) is not needed
source "${0:A:h}/claude-guard.plugin.zsh"
_claude_guard_hook
