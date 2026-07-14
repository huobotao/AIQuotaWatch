#!/bin/zsh
set -euo pipefail

UID_VALUE="$(id -u)"

for label in com.richardhuo.aiquotawatch com.richardhuo.aiquotamenu; do
    plist="$HOME/Library/LaunchAgents/$label.plist"
    launchctl bootout "gui/$UID_VALUE" "$plist" 2>/dev/null || true
    rm -f "$plist"
done

rm -rf "$HOME/Applications/AI 额度观察.app"
rm -rf "$HOME/Applications/AI 额度菜单.app"

echo "Apps and LaunchAgents removed. Runtime data was preserved."
