#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

DEVICE_ID="${1:-6E1DB110-95A8-51D7-9DA0-A0E2943675D0}"
BUNDLE_ID="com.richardhuo.aiquotaphone"

echo "Building AIQuotaPhone for device: $DEVICE_ID"
xcodebuild \
  -project AIQuotaPhone.xcodeproj \
  -scheme AIQuotaPhone \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/Debug-iphoneos/AIQuotaPhone.app" -type d -print | sort | tail -1)"
if [[ -z "$APP_PATH" ]]; then
  echo "Could not find built AIQuotaPhone.app" >&2
  exit 1
fi

echo "Installing $APP_PATH"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"

echo "Done."
