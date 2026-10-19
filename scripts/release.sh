#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
notarize=false
if [ "${1:-}" = "--notarize" ]; then
  notarize=true
  : "${CANOPY_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
  : "${CANOPY_NOTARY_PROFILE:?Set the name of your existing notarytool keychain profile}"
elif [ -n "${1:-}" ]; then echo "Usage: $0 [--notarize]" >&2; exit 2; fi
release_directory="${CANOPY_OUTPUT_DIR:-$(pwd)/dist}"
mkdir -p "$release_directory"
release_directory="$(cd "$release_directory" && pwd)"
CANOPY_OUTPUT_DIR="$release_directory" CANOPY_TEST_FIXTURE=0 bash scripts/build-app.sh release universal
app="$release_directory/Canopy.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$release_directory/Canopy-$version-macos-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
if $notarize; then
  xcrun notarytool submit "$archive" --keychain-profile "$CANOPY_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  ditto -c -k --keepParent "$app" "$archive"
  spctl --assess --type execute --verbose "$app"
fi
tar -czf "$release_directory/Canopy-$version-source.tar.gz" Package.swift LICENSE README.md CONTRIBUTING.md CHANGELOG.md DESIGN.md PRODUCT.md .gitignore .github .impeccable Resources Sources Tests scripts docs
(cd "$release_directory" && shasum -a 256 "Canopy-$version-macos-universal.zip" "Canopy-$version-source.tar.gz" > SHA256SUMS)
echo "Prepared $archive and source archive"
