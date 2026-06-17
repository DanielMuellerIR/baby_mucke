#!/usr/bin/env bash
set -euo pipefail

# Baut die iOS-App fuer den Simulator, ohne Code Signing zu verlangen.
# DEVELOPER_DIR wird nur fuer diesen Prozess gesetzt, damit die globale
# xcode-select-Konfiguration des Macs unangetastet bleibt.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT_DIR"
xcodebuild \
  -project BabyMucke.xcodeproj \
  -scheme BabyMucke \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
