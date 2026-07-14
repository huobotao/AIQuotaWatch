#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UID_VALUE="$(id -u)"
APPS_DIR="$HOME/Applications"
AGENTS_DIR="$HOME/Library/LaunchAgents"
BACKUP_DIR="/tmp/AIQuotaWatch-backup-$(date +%Y%m%d-%H%M%S)"

"$ROOT/scripts/build-macos.sh"
mkdir -p "$APPS_DIR" "$AGENTS_DIR" "$HOME/Library/Logs"

for name in "AI 额度观察.app" "AI 额度菜单.app"; do
    if [[ -e "$APPS_DIR/$name" ]]; then
        mkdir -p "$BACKUP_DIR"
        ditto "$APPS_DIR/$name" "$BACKUP_DIR/$name"
    fi
    rm -rf "$APPS_DIR/$name"
    ditto "$ROOT/dist/$name" "$APPS_DIR/$name"
    xattr -cr "$APPS_DIR/$name"
    codesign --verify --deep --strict --verbose=2 "$APPS_DIR/$name"
done

for label in com.richardhuo.aiquotawatch com.richardhuo.aiquotamenu; do
    template="$ROOT/packaging/LaunchAgents/$label.plist"
    destination="$AGENTS_DIR/$label.plist"
    sed "s|__HOME__|$HOME|g" "$template" > "$destination"
    plutil -lint "$destination"
    launchctl bootout "gui/$UID_VALUE" "$destination" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_VALUE" "$destination"
    launchctl kickstart -k "gui/$UID_VALUE/$label"
done

sleep 3
launchctl print "gui/$UID_VALUE/com.richardhuo.aiquotawatch" | grep -E 'state =|pid =|job state'
launchctl print "gui/$UID_VALUE/com.richardhuo.aiquotamenu" | grep -E 'state =|pid =|job state'

open "$APPS_DIR/AI 额度观察.app"
echo "Installed to $APPS_DIR"
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Previous apps backed up to $BACKUP_DIR"
fi
