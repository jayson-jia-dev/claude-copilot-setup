# Claude Code via GitHub Copilot 辅助 alias
# 主命令 claude-cp 是 ~/.local/bin/claude-cp wrapper 脚本，不在这里 alias
alias claude-cp-status='launchctl list | grep claude-copilot-proxy; lsof -nP -iTCP:18080 -sTCP:LISTEN 2>/dev/null'
alias claude-cp-restart='launchctl kickstart -k gui/$(id -u)/com.jayson.claude-copilot-proxy'
alias claude-cp-log='tail -f ~/Library/Logs/claude-copilot-proxy.out.log'
alias claude-cp-detect-models='node ~/claude-code-copilot/scripts/detect-models.mjs && launchctl kickstart -k gui/$(id -u)/com.jayson.claude-copilot-proxy'
