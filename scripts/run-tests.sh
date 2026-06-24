#!/usr/bin/env bash
set -euo pipefail

# Fuehrt die Unit-Tests im iOS-Simulator aus (headless, ohne Code-Signing).
# Der Simulator wird automatisch gewaehlt (erster verfuegbarer iPhone-Simulator),
# laesst sich aber per IOS_SIM="<Name>" ueberschreiben:
#   IOS_SIM="iPhone 17 Pro" ./scripts/run-tests.sh
#
# DEVELOPER_DIR wird nur fuer diesen Prozess gesetzt, damit die globale
# xcode-select-Konfiguration des Macs unangetastet bleibt.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT_DIR"

# Per Name laesst sich ein Geraet nicht eindeutig waehlen, wenn derselbe
# iPhone-Typ unter mehreren iOS-Runtimes existiert. Deshalb die UDID nehmen.
# IOS_SIM kann eine UDID ODER einen Geraetenamen enthalten.
DEST=""
if [[ -n "${IOS_SIM:-}" ]]; then
  if [[ "$IOS_SIM" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    DEST="platform=iOS Simulator,id=$IOS_SIM"
  else
    DEST="platform=iOS Simulator,name=$IOS_SIM"
  fi
else
  # UDID des ersten verfuegbaren iPhone-Simulators aus der ersten Klammer ziehen.
  UDID="$(xcrun simctl list devices available \
    | grep -E '^[[:space:]]*iPhone' \
    | head -1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
  if [[ -z "$UDID" ]]; then
    echo "Fehler: Kein verfuegbarer iPhone-Simulator gefunden." >&2
    echo "  -> In Xcode einen iPhone-Simulator installieren oder IOS_SIM=\"<UDID|Name>\" setzen." >&2
    exit 1
  fi
  DEST="platform=iOS Simulator,id=$UDID"
fi

echo "==> Unit-Tests im Simulator: $DEST"
xcodebuild test \
  -project BabyMucke.xcodeproj \
  -scheme BabyMucke \
  -destination "$DEST" \
  CODE_SIGNING_ALLOWED=NO
