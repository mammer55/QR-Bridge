#!/bin/bash
#
# Rebuilds and reinstalls the ClipKeyboard app to the connected iPhone, then
# resets the expiry clock. Run this when the free Apple ID provisioning is
# about to expire (or has expired). Phone must be plugged in and unlocked.
#
set -euo pipefail

DIR="/Users/mustafaalbaree/Code/qr-bridge/ios-keyboard"
DEVICE_ID="00008150-000268960E63401C"   # Mustafa's iPhone 17 Pro Max
STATE="$HOME/.clipkeyboard"

cd "$DIR"

echo "==> Checking for device $DEVICE_ID"
if ! xcrun devicectl list devices 2>/dev/null | grep -qi "$DEVICE_ID\|iPhone18,2"; then
  echo "Device not found. Plug in the iPhone, unlock it, and trust this computer, then rerun."
  exit 1
fi

echo "==> Generating project"
xcodegen generate

echo "==> Building"
xcodebuild -project ClipKeyboard.xcodeproj -scheme ClipKeyboard -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" -allowProvisioningUpdates \
  -derivedDataPath build build

echo "==> Installing"
xcrun devicectl device install app --device "$DEVICE_ID" \
  build/Build/Products/Debug-iphoneos/ClipKeyboard.app

echo "==> Resetting expiry clock"
mkdir -p "$STATE"
date +%s > "$STATE/last_install"
rm -f "$STATE/last_reminded"

echo "Done. App reinstalled and the 7 day clock is reset."
