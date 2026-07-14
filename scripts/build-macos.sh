#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
WATCH_PACKAGE="$ROOT/work/AIQuotaWatch"
MENU_SOURCE="$ROOT/work/AIQuotaMenu/main.swift"

WATCH_APP="$DIST/AI 额度观察.app"
MENU_APP="$DIST/AI 额度菜单.app"

rm -rf "$DIST"
mkdir -p "$WATCH_APP/Contents/MacOS" "$WATCH_APP/Contents/Resources"
mkdir -p "$MENU_APP/Contents/MacOS"

swift build --package-path "$WATCH_PACKAGE" -c release
WATCH_BIN_DIR="$(swift build --package-path "$WATCH_PACKAGE" -c release --show-bin-path)"
install -m 755 "$WATCH_BIN_DIR/AIQuotaWatch" "$WATCH_APP/Contents/MacOS/AIQuotaWatch"
install -m 644 "$WATCH_PACKAGE/packaging/Info.plist" "$WATCH_APP/Contents/Info.plist"

swiftc -O -framework AppKit -framework Foundation \
    "$MENU_SOURCE" \
    -o "$MENU_APP/Contents/MacOS/AIQuotaMenu"
install -m 644 "$ROOT/work/AIQuotaMenu/Info.plist" "$MENU_APP/Contents/Info.plist"

for app in "$WATCH_APP" "$MENU_APP"; do
    xattr -cr "$app"
    rm -rf "$app/Contents/_CodeSignature"
    codesign --force --deep --sign - "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
done

echo "Built:"
echo "  $WATCH_APP"
echo "  $MENU_APP"
