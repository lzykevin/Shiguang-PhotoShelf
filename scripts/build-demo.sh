#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/PhotoShelf Demo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Samples"
cp output/示例照片/2026/秋日旅行/*.jpg "$APP/Contents/Resources/Samples/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -parse-as-library Demo/Sources/*.swift -o "$APP/Contents/MacOS/PhotoShelfDemo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PhotoShelfDemo</string>
<key>CFBundleIdentifier</key><string>com.photoshelf.interaction-demo</string>
<key>CFBundleName</key><string>拾光 Demo</string>
<key>CFBundleDisplayName</key><string>拾光 Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
