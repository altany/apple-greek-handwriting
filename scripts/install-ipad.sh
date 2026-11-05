#!/bin/sh
# Build GreekInk with the Personal Team (from Local.xcconfig), install it on the
# connected iPad and launch it. Re-run this every 7 days (free-team expiry).
#
# Usage: scripts/install-ipad.sh [device-id]
# The device id is the one xcodebuild -showdestinations prints; auto-detected if omitted.
set -eu
cd "$(dirname "$0")/.."

WS=GreekInk.xcworkspace
SCHEME=GreekInk
DD=build/DerivedData
APP="$DD/Build/Products/Debug-iphoneos/GreekInk.app"

[ -f Local.xcconfig ] || { echo "Local.xcconfig missing: cp Local.xcconfig.example Local.xcconfig and fill in DEVELOPMENT_TEAM"; exit 1; }
grep -q 'DEVELOPMENT_TEAM = X' Local.xcconfig && { echo "Local.xcconfig still has the placeholder DEVELOPMENT_TEAM"; exit 1; }

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcodebuild -workspace "$WS" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep -E 'platform:iOS,' | grep -vE 'placeholder|Simulator' | head -1 \
    | sed -E 's/.*id:([^,} ]+).*/\1/')
fi
[ -n "$DEVICE" ] || { echo "No iPad found. Plug it in by USB, unlock it, tap Trust, then retry."; exit 1; }
echo "==> Device: $DEVICE"

echo "==> Building (automatic signing, team from Local.xcconfig)"
xcodebuild -workspace "$WS" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build \
  | grep -E 'error:|warning: .*(sign|provision|entitle)|Signing Identity|BUILD ' || true
[ -d "$APP" ] || { echo "Build failed (no .app produced)"; exit 1; }

BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
echo "==> Installing $BUNDLE_ID"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "==> Launching"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"
echo "==> Done. If the icon is greyed out: Settings > General > VPN & Device Management > trust your Apple ID."
