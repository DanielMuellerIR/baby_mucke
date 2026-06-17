#!/usr/bin/env bash
set -euo pipefail

# Baut die iOS-App signiert fuer ein angeschlossenes iPhone und installiert sie.
#
# Die Team-ID landet bewusst NICHT im Repo (kann oeffentlich/App Store werden).
# Sie kommt aus der Umgebung oder aus einer gitignored `.env` (siehe .env.example):
#
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-device.sh
#   # oder: Wert in .env eintragen, dann einfach:
#   ./scripts/build-device.sh
#
# Optional Geraet festlegen (Name oder UDID), sonst wird das einzige
# angeschlossene Geraet automatisch gewaehlt:
#   IOS_DEVICE="Daniels iPhone" ./scripts/build-device.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT_DIR"

# Team-ID aus .env nachladen, falls nicht schon in der Umgebung.
if [[ -z "${DEVELOPMENT_TEAM:-}" && -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Fehler: DEVELOPMENT_TEAM ist nicht gesetzt." >&2
  echo "  -> In .env eintragen (Vorlage: .env.example) oder als Variable uebergeben." >&2
  exit 1
fi

DERIVED="build/device"

echo "==> Baue + signiere fuer iOS-Geraet (Team $DEVELOPMENT_TEAM) ..."
xcodebuild \
  -project BabyMucke.xcodeproj \
  -scheme BabyMucke \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/BabyMucke.app"
if [[ ! -d "$APP" ]]; then
  echo "Fehler: Gebaute App nicht gefunden unter $APP" >&2
  exit 1
fi
echo "==> Gebaut: $APP"

# Zielgeraet bestimmen: explizit via IOS_DEVICE, sonst einziges angeschlossenes.
DEVICE="${IOS_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
  DEVICE="$(python3 - "$JSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
devs = data.get("result", {}).get("devices", [])
connected = []
for d in devs:
    conn = d.get("connectionProperties", {})
    # Aktuell verbundene Geraete haben einen transportType (wired/wireless).
    # pairingState ist absichtlich KEIN Filter: ein frisch angestecktes iPhone
    # meldet oft "unpaired", laesst sich aber dennoch bespielen.
    if not conn.get("transportType"):
        continue
    ident = d.get("identifier") or d.get("hardwareProperties", {}).get("udid", "")
    name = d.get("deviceProperties", {}).get("name", "?")
    if ident:
        connected.append((ident, name))
if len(connected) == 1:
    print(connected[0][0])
elif len(connected) > 1:
    sys.stderr.write("Mehrere Geraete angeschlossen:\n")
    for ident, name in connected:
        sys.stderr.write(f"  {name}  ({ident})\n")
PY
)"
fi

if [[ -z "$DEVICE" ]]; then
  echo "==> Kein eindeutiges Geraet gefunden."
  echo "    iPhone anschliessen/entsperren und ggf. IOS_DEVICE=\"<Name|UDID>\" setzen,"
  echo "    oder manuell installieren:"
  echo "      xcrun devicectl device install app --device <UDID> \"$APP\""
  exit 0
fi

echo "==> Installiere auf Geraet: $DEVICE"
if ! xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  echo "" >&2
  echo "Installation fehlgeschlagen. Haeufigste Ursache: iPhone noch nicht gekoppelt." >&2
  echo "  1. iPhone per Kabel verbinden und entsperren." >&2
  echo "  2. Beim Dialog 'Diesem Computer vertrauen?' auf VERTRAUEN tippen (Code eingeben)." >&2
  echo "  3. Entwicklermodus aktivieren: Einstellungen > Datenschutz & Sicherheit >" >&2
  echo "     Entwicklermodus > an > Neustart." >&2
  echo "  Kommt kein Vertrauen-Dialog: einmal Xcode > Window > Devices and Simulators" >&2
  echo "  oeffnen, dort das iPhone koppeln. Danach dieses Skript erneut ausfuehren." >&2
  exit 1
fi
echo "==> Fertig. App auf dem iPhone starten."
