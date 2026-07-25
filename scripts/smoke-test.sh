#!/usr/bin/env bash
#
# Runtime smoke test: builds for the simulator, boots the app, lets it play
# itself and screenshots the result.
#
# A green compile says nothing about whether the game actually runs — this
# catches crashes on launch, broken layout maths and scenes that render nothing,
# none of which xcodebuild can see.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.chromacascade.game"
SHOTS="build/screenshots"
SEED="${SEED:-424242}"

rm -rf "$SHOTS"
mkdir -p "$SHOTS"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building for the simulator"
xcodebuild \
  -project ChromaCascade.xcodeproj \
  -scheme ChromaCascade \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath build/SimDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="build/SimDerivedData/Build/Products/Debug-iphonesimulator/ChromaCascade.app"
if [ ! -d "$APP" ]; then
  echo "error: simulator app not found at $APP" >&2
  exit 1
fi

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, entries in devices.items():
    if 'iOS' not in runtime:
        continue
    for device in entries:
        if device.get('isAvailable') and 'iPhone' in device['name']:
            sys.stderr.write('using %s (%s)\n' % (device['name'], runtime.split('.')[-1]))
            print(device['udid'])
            raise SystemExit(0)
sys.exit('no available iPhone simulator found')
")

CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$CRASH_DIR"
rm -f "$CRASH_DIR"/ChromaCascade* 2>/dev/null || true

echo "==> Booting simulator $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Installing"
xcrun simctl install "$UDID" "$APP"

shoot() {
  local name="$1"
  xcrun simctl io "$UDID" screenshot --type=png "$SHOTS/$name.png" >/dev/null 2>&1
  echo "    captured $name.png"
}

assert_alive() {
  local label="$1"
  if ls "$CRASH_DIR"/ChromaCascade* >/dev/null 2>&1; then
    echo "error: the app crashed ($label). Crash report:" >&2
    cat "$CRASH_DIR"/ChromaCascade* >&2
    exit 1
  fi
}

echo "==> Launching the menu"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 6
assert_alive "menu"
shoot "01-menu"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 1

echo "==> Launching a self-playing run (seed $SEED)"
xcrun simctl launch "$UDID" "$BUNDLE_ID" --cc-scene-game --cc-autoplay 60 --cc-seed "$SEED"

sleep 8
assert_alive "early game"
shoot "02-game-early"

sleep 14
assert_alive "mid game"
shoot "03-game-mid"

sleep 18
assert_alive "late game"
shoot "04-game-late"

sleep 14
assert_alive "end of autoplay"
shoot "05-game-end"

echo "==> Smoke test passed; screenshots in $SHOTS"
ls -la "$SHOTS"
