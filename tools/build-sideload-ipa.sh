#!/bin/zsh
# Builds the IPA for GitHub releases: build/release/Zapret-iOS-<version>.ipa.
#
# It is signed ad hoc, with no certificate, team, or provisioning profile, so it
# carries nothing personal. The ad hoc signature keeps the entitlements (Network
# Extension and App Group), which tools like AltStore, Feather, and Sideloadly
# read when they re-sign the app with the user's own certificate.
#   tools/build-sideload-ipa.sh
set -euo pipefail
cd ${0:A:h:h}
root=$PWD
version=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)
bundle=$(awk '/ZAPRET_BUNDLE_ID:/ {print $2; exit}' project.yml)
work=build/sideload
out=build/release/Zapret-iOS-$version.ipa
rm -rf $work && mkdir -p $work build/release

xcodegen generate -q
xcodebuild -project ZapretiOS.xcodeproj -scheme ZapretiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $work/ZapretiOS.xcarchive \
  -derivedDataPath build/DD-sideload CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  archive -quiet

app=$work/Payload/ZapretiOS.app
mkdir -p $work/Payload
cp -R $work/ZapretiOS.xcarchive/Products/Applications/ZapretiOS.app $app

# The entitlements files with the build variable filled in, without get-task-allow.
entitlements() {
  local file=$work/${1:t:r}.entitlements
  sed "s/\$(ZAPRET_BUNDLE_ID)/$bundle/g" $1 > $file
  echo $file
}

# Inside out: the extensions first, then the app.
codesign --force --sign - --timestamp=none --entitlements $(entitlements Tunnel/ZapretTunnel.entitlements) $app/PlugIns/ZapretTunnel.appex
codesign --force --sign - --timestamp=none --entitlements $(entitlements Widgets/ZapretWidgets.entitlements) $app/PlugIns/ZapretWidgets.appex
codesign --force --sign - --timestamp=none --entitlements $(entitlements App/ZapretiOS.entitlements) $app

# Nothing personal may ship: no team, certificate, profile, or home-folder path.
leaks=$(grep -rIl -E "$HOME|/Users/|/private/var/folders" $app 2>/dev/null || true)
binaries=($app/ZapretiOS $app/PlugIns/*.appex/*(.x))
for b in $binaries; do
  strings -a $b | grep -qE "/Users/|$HOME" && leaks+=" $b"
done
[[ -z ${leaks// /} ]] || { echo "Personal paths found in: $leaks"; exit 1; }
[[ -z $(find $app -name embedded.mobileprovision) ]] || { echo "A provisioning profile slipped in"; exit 1; }

rm -f $out
(cd $work && zip -qr -X $root/$out Payload)
echo "IPA: $root/$out ($(du -h $out | cut -f1))"
