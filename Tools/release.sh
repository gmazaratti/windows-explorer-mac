#!/bin/bash
# Signs, notarizes and staples a release build.
#
# One-time setup:
#   1. Create a "Developer ID Application" certificate:
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#      (or download it from developer.apple.com/account/resources/certificates)
#   2. Store notarization credentials in the keychain, which prompts for an
#      app-specific password from appleid.apple.com:
#      xcrun notarytool store-credentials winexp-notary \
#          --apple-id you@example.com --team-id YOURTEAMID
#
# Then:  ./Tools/release.sh 1.0.1
set -e
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version>}"
PROFILE="${NOTARY_PROFILE:-winexp-notary}"
APP="build/File Explorer.app"
ZIP="build/FileExplorer-$VERSION-macOS-universal.zip"

IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application certificate found in the keychain."
    echo "See the setup notes at the top of this script."
    exit 1
fi
echo "==> Signing as: $IDENTITY"

./build.sh --universal

codesign --force --deep --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (this takes a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Ready: $ZIP"
echo "    gh release create v$VERSION --title \"File Explorer for Mac $VERSION\" \"$ZIP\""
