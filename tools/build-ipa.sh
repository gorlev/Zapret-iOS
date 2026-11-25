#!/bin/zsh
# Builds a signed development IPA at build/ipa/ZapretiOS.ipa.
#   tools/build-ipa.sh            build the IPA
#   tools/build-ipa.sh --install  also install it on the connected iPhone
set -euo pipefail
cd ${0:A:h:h}
xcodegen generate -q
xcodebuild -project ZapretiOS.xcodeproj -scheme ZapretiOS -configuration Release \
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
