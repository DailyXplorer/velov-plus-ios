#!/bin/zsh
# Renders the key screens with sample data: boots a dedicated simulator, launches the app once per screen and takes a PNG.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/snapshots"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/VelovCompagnon.app"
BUNDLE=io.github.dailyxplorer.velov
mkdir -p "$OUT"

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"]]; print(r[-1]["identifier"] if r else "")')
[[ -n "$RUNTIME" ]] || { echo "no iOS simulator runtime installed"; exit 1; }
UDID=$(xcrun simctl list devices -j | python3 -c "import json,sys; d=[x['udid'] for v in json.load(sys.stdin)['devices'].values() for x in v if x['name']=='$SIM_NAME' and x['isAvailable']]; print(d[0] if d else '')")
[[ -n "$UDID" ]] || UDID=$(xcrun simctl create "$SIM_NAME" "$SIM_TYPE" "$RUNTIME")
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui "$UDID" appearance light
xcrun simctl install "$UDID" "$APP"

shot() {
  local screen=$1 file=$2 wait=${3:-5}
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -VelovSample YES -VelovScreen "$screen" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$file.png" >/dev/null 2>&1
  echo "snapshots/$file.png"
}

shot overview 01-overview 7
shot overviewMap 01b-overview-map 8
shot trips 02-trips
shot tripSheet 03-trip-sheet 6
shot stations 04a-stations 8
shot stationSheet 04-stations-sheet 9
shot bikeList 05-bike-list 9
shot bikeSheet 06-bike-sheet 10
shot points 07-points
shot account 08-account
shot accountEnd 08b-account-end 7
shot bookingBanner 09-booking-banner 6
shot liveActivityLock 10-live-activity-lock 5
shot liveActivityIsland 11-live-activity-island 5
shot unlockConfirm 12-unlock-confirm 7
shot unlockSuccess 13-unlock-success 8
shot rateCard 14-rate-card 6
shot accountEdit 15-account-edit 6
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
