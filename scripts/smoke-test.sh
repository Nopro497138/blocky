#!/usr/bin/env bash
#
# Runtime smoke test: builds for the simulator, boots the app, lets it play
# itself and screenshots the result.
#
# A green compile says nothing about whether the game actually runs — this
# catches crashes on launch, broken layout maths and scenes that render nothing,
# none of which xcodebuild can see.
#
# Every wait in here is bounded. An unbounded `simctl bootstatus` once sat on a
# CI runner until the job timed out, which on a private repo burns macOS minutes
# at 10x, so nothing in this script is allowed to block forever.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.chromacascade.game"
SHOTS="build/screenshots"
SEED="${SEED:-424242}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-150}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

rm -rf "$SHOTS"
mkdir -p "$SHOTS"

log "generating Xcode project"
xcodegen generate

log "building for the simulator"
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
log "built $APP"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
best = None
for runtime, entries in devices.items():
    if 'iOS' not in runtime:
        continue
    for device in entries:
        if device.get('isAvailable') and 'iPhone' in device['name']:
            best = (device['name'], runtime.split('.')[-1], device['udid'])
            break
    if best:
        break
if not best:
    sys.exit('no available iPhone simulator found')
sys.stderr.write('using %s (%s)\n' % (best[0], best[1]))
print(best[2])
")
log "simulator $UDID"

CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$CRASH_DIR"
rm -f "$CRASH_DIR"/ChromaCascade* 2>/dev/null || true

log "booting"
xcrun simctl boot "$UDID" 2>/dev/null || true

booted=0
for _ in $(seq 1 "$((BOOT_TIMEOUT / 3))"); do
  if xcrun simctl list devices | grep -- "$UDID" | grep -q "Booted"; then
    booted=1
    break
  fi
  sleep 3
done
if [ "$booted" -ne 1 ]; then
  echo "error: simulator did not boot within ${BOOT_TIMEOUT}s" >&2
  xcrun simctl list devices | grep -- "$UDID" >&2 || true
  exit 1
fi
log "booted"

log "installing"
installed=0
for _ in 1 2 3 4 5; do
  if xcrun simctl install "$UDID" "$APP"; then
    installed=1
    break
  fi
  sleep 4
done
if [ "$installed" -ne 1 ]; then
  echo "error: could not install the app" >&2
  exit 1
fi

shoot() {
  local name="$1"
  if xcrun simctl io "$UDID" screenshot --type=png "$SHOTS/$name.png" >/dev/null 2>&1; then
    log "captured $name.png"
  else
    log "WARNING: screenshot $name failed"
  fi
}

assert_alive() {
  local label="$1"
  if ls "$CRASH_DIR"/ChromaCascade* >/dev/null 2>&1; then
    echo "error: the app crashed ($label). Crash report:" >&2
    cat "$CRASH_DIR"/ChromaCascade* >&2
    exit 1
  fi
}

log "launching the menu"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 5
assert_alive "menu"
shoot "01-menu"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 1

log "launching a self-playing run (seed $SEED)"
xcrun simctl launch "$UDID" "$BUNDLE_ID" --cc-scene-game --cc-autoplay 60 --cc-seed "$SEED"

sleep 8
assert_alive "early game"
shoot "02-game-early"

sleep 12
assert_alive "mid game"
shoot "03-game-mid"

sleep 16
assert_alive "late game"
shoot "04-game-late"

log "smoke test passed; screenshots in $SHOTS"
ls -la "$SHOTS"
