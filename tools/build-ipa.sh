#!/bin/zsh
# Builds a signed development IPA at build/ipa/ZapretiOS.ipa.
#   tools/build-ipa.sh            build the IPA
#   tools/build-ipa.sh --install  also install it on the connected iPhone
# Signs with your Apple Development certificate's team (or TEAM_ID=...).
# Building under your own bundle ID: ZAPRET_BUNDLE_ID=com.example.zapret tools/build-ipa.sh
set -euo pipefail
cd ${0:A:h:h}
team=${TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -oE "OU ?= ?[A-Z0-9]{10}" | grep -oE "[A-Z0-9]{10}$" || true)}
[[ -n $team ]] || { echo "No Apple Development certificate found. Add your account in Xcode > Settings > Accounts, or set TEAM_ID."; exit 1; }
extra=(DEVELOPMENT_TEAM=$team)
[[ -n ${ZAPRET_BUNDLE_ID:-} ]] && extra+=(ZAPRET_BUNDLE_ID=$ZAPRET_BUNDLE_ID)
xcodegen generate -q
xcodebuild -project ZapretiOS.xcodeproj -scheme ZapretiOS -configuration Release "${extra[@]}" \
  -destination 'generic/platform=iOS' -archivePath build/ZapretiOS.xcarchive \
  -derivedDataPath build/DD-device -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  archive -quiet
rm -rf build/ipa
xcodebuild -exportArchive -archivePath build/ZapretiOS.xcarchive -exportPath build/ipa \
  -exportOptionsPlist tools/ExportOptions.plist -allowProvisioningUpdates -quiet
echo "IPA: $PWD/build/ipa/ZapretiOS.ipa"
if [[ ${1:-} == --install ]]; then
  device=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ && /iPhone/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-/) {print $i; exit}}')
  [[ -n $device ]] || { echo "No connected iPhone"; exit 1; }
  xcrun devicectl device install app --device "$device" build/ipa/ZapretiOS.ipa >/dev/null
  echo "Installed on $device"
fi
