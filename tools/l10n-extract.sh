#!/bin/zsh
# Rebuilds Localization/en.json from every string the compiler sees as localizable
# (a build of the app, widget and tunnel for the simulator, with the compiler's
# string extraction on), then lists what each language is still missing.
# DebugTamperCard.swift and non-UI keys are skipped through Localization/notes.json.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
dd="$repo/build/L10N-DD"
cd "$repo"
xcodegen generate >/dev/null
rm -rf "$dd/Build/Intermediates.noindex"
xcodebuild -project ZapretiOS.xcodeproj -scheme ZapretiOS -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath "$dd" \
  CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
python3 "$here/l10n_extract.py" "$dd/Build/Intermediates.noindex"
python3 "$here/l10n.py" status || true
