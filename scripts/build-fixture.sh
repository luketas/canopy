#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product CanopyFixture
binary_directory="$(swift build --show-bin-path)"
fixture="$(pwd)/dist/CanopyFixture.app"
mkdir -p "$fixture/Contents/MacOS"
cp "$binary_directory/CanopyFixture" "$fixture/Contents/MacOS/CanopyFixture"
cat > "$fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleName</key><string>CanopyFixture</string>
<key>CFBundleIdentifier</key><string>org.canopywm.Fixture</string>
<key>CFBundleExecutable</key><string>CanopyFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$fixture"
echo "Built $fixture"
