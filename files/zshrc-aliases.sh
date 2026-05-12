# Claude Code via GitHub Copilot (本地代理，无限额度)
# Daemon: ~/Library/LaunchAgents/com.jayson.claude-copilot-proxy.plist
# Logs:   ~/Library/Logs/claude-copilot-proxy.{out,err}.log
alias claude-cp='ANTHROPIC_BASE_URL=http://localhost:18080 ANTHROPIC_API_KEY=copilot-proxy claude'
alias claude-cp-status='launchctl list | grep claude-copilot-proxy; lsof -nP -iTCP:18080 -sTCP:LISTEN'
alias claude-cp-restart='launchctl kickstart -k gui/$(id -u)/com.jayson.claude-copilot-proxy'
alias claude-cp-log='tail -f ~/Library/Logs/claude-copilot-proxy.out.log'
