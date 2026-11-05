#!/bin/zsh
# Builds a local testing archive. This does NOT sign with Developer ID or notarize.
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
APP=build/Build/Products/Release/PhotoShelf.app
python3 scripts/check_release.py "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p build/beta
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "build/beta/PhotoShelf-${VERSION}-unnotarized.zip"
/usr/bin/shasum -a 256 "build/beta/PhotoShelf-${VERSION}-unnotarized.zip" > "build/beta/PhotoShelf-${VERSION}-unnotarized.zip.sha256"
print 'Local testing archive created. Do not add this unverified build to appcast.xml.'
