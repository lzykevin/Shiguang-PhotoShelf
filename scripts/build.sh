#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ ! -f Resources/AppIcon.icns ]]; then
  mkdir -p build/AppIcon.iconset
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
# Local ad-hoc builds cannot satisfy library validation for embedded frameworks.
# Distribution builds must override ENABLE_HARDENED_RUNTIME=YES and sign all code
# with Developer ID through Archive/Export; see docs/publishing.md.
python3 scripts/create_xcode_project.py
xcodebuild -project PhotoShelf.xcodeproj -scheme PhotoShelf -configuration Release -derivedDataPath build build ENABLE_HARDENED_RUNTIME=NO "$@"
print "应用已生成：${PWD}/build/Build/Products/Release/PhotoShelf.app"
