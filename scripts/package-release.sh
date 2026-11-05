#!/bin/zsh
# Packages the app. Developer ID signing and notarization are separate release steps.
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
APP=build/Build/Products/Release/PhotoShelf.app
python3 scripts/check_release.py "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p build/release
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "build/release/PhotoShelf-${VERSION}.zip"
/usr/bin/shasum -a 256 "build/release/PhotoShelf-${VERSION}.zip" > "build/release/PhotoShelf-${VERSION}.zip.sha256"
print 'Release archive created.'
