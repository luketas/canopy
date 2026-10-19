#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
architecture="${2:-native}"
signing_identity="${CANOPY_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ] && [ -f .canopy-signing-identity ]; then
  IFS= read -r signing_identity < .canopy-signing-identity || true
fi
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release] [native|universal]" >&2; exit 1 ;; esac
architecture_flags=(--arch "$(uname -m)")
case "$architecture" in native) ;; universal) architecture_flags=(--arch arm64 --arch x86_64) ;; *) echo "Unknown architecture: $architecture" >&2; exit 1 ;; esac
swift build -c "$configuration" --product Canopy "${architecture_flags[@]}"
binary_directory="$(swift build -c "$configuration" --show-bin-path "${architecture_flags[@]}")"
output_directory="${CANOPY_OUTPUT_DIR:-$(pwd)/dist}"
app_name="Canopy"
bundle_identifier="org.canopywm.Canopy"
if [ "${CANOPY_TEST_FIXTURE:-0}" = "1" ]; then
  app_name="Canopy Test"
  bundle_identifier="org.canopywm.Canopy.Test"
fi
app="$output_directory/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/Canopy" "$app/Contents/MacOS/Canopy"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ "${CANOPY_TEST_FIXTURE:-0}" = "1" ]; then
  /usr/libexec/PlistBuddy -c "Add :CanopyFixtureTesting bool true" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Canopy Test" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Canopy Test" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$app/Contents/Info.plist"
fi
swift scripts/make-icon.swift "$output_directory/Canopy.iconset"
iconutil -c icns "$output_directory/Canopy.iconset" -o "$app/Contents/Resources/Canopy.icns"
if [ -n "$signing_identity" ]; then
  codesign --force --options runtime --timestamp --sign "$signing_identity" --identifier "$bundle_identifier" "$app"
else
  codesign --force --sign - --identifier "$bundle_identifier" "$app"
fi
codesign --verify --deep --strict "$app"
echo "Built $app"
