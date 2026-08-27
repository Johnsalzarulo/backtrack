#!/bin/bash
# Build BackTrackPad and launch it in the iPad simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SIM_NAME="${SIM_NAME:-iPad mini (A17 Pro)}"
DERIVED="$ROOT/.build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/BackTrackPad.app"
BUNDLE_ID="com.backtrack.pad"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required. Install from the App Store, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "  sudo xcodebuild -license accept"
  exit 1
fi

if ! xcrun simctl list devices available >/dev/null 2>&1; then
  echo "Accept the Xcode license first:"
  echo "  sudo xcodebuild -license accept"
  exit 1
fi

RUNTIME_COUNT="$(xcrun simctl list runtimes available 2>/dev/null | grep -c "iOS" || true)"
if [[ "$RUNTIME_COUNT" -eq 0 ]]; then
  echo "No iOS Simulator runtime is installed."
  echo "Xcode → Settings → Platforms → download iOS Simulator, then re-run."
  exit 1
fi

cd "$ROOT"

# Resolve simulator UDID first so build + install target the same device.
UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')"
if [[ -z "$UDID" ]]; then
  FALLBACK="$(xcrun simctl list devices available | grep -i "ipad mini" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')"
  if [[ -z "$FALLBACK" ]]; then
    FALLBACK="$(xcrun simctl list devices available | grep -i "ipad" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')"
  fi
  if [[ -z "$FALLBACK" ]]; then
    echo "No iPad simulator found. Install the iOS Simulator runtime in Xcode → Settings → Platforms."
    exit 1
  fi
  UDID="$FALLBACK"
  SIM_NAME="$(xcrun simctl list devices available | grep "$UDID" | sed -E 's/^[[:space:]]+([^(]+)\(.*/\1/' | sed 's/[[:space:]]*$//')"
  echo "Using simulator: $SIM_NAME ($UDID)"
fi

echo "Building BackTrackPad for $SIM_NAME..."
xcodebuild \
  -project BackTrack.xcodeproj \
  -scheme BackTrackPad \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  build

if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but app bundle not found at:"
  echo "  $APP"
  exit 1
fi

echo "Booting simulator $SIM_NAME ($UDID)..."
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"
sleep 2

echo "Installing app..."
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

if ! xcrun simctl listapps "$UDID" | grep -q "$BUNDLE_ID"; then
  echo "Install failed — $BUNDLE_ID not registered on this simulator."
  exit 1
fi

echo "Launching BackTrackPad..."
if ! xcrun simctl launch "$UDID" "$BUNDLE_ID"; then
  echo "Launch failed. Waiting for SpringBoard and retrying..."
  sleep 3
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
fi

echo "Done."
echo "Look for the BackTrack icon on: $SIM_NAME"
echo "Tip: in Xcode use Product → Run (⌘R) with destination iPad mini (A17 Pro)."
