#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$(pwd)/dist/Canopy.app"
destination="${1:-$HOME/Applications/Canopy.app}"
[ -d "$source_app" ] || { echo "Build the app first." >&2; exit 1; }
fixture_mode="$(/usr/libexec/PlistBuddy -c 'Print :CanopyFixtureTesting' "$source_app/Contents/Info.plist" 2>/dev/null || true)"
[ "$fixture_mode" != "true" ] || { echo "Refusing to install a fixture-only test build. Build the full app with scripts/release.sh first." >&2; exit 1; }
if pgrep -x Canopy >/dev/null; then echo "Quit Canopy before installing." >&2; exit 1; fi
if [ -e "$destination" ]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
  [ "$existing_id" = "org.canopywm.Canopy" ] || { echo "Destination is not a Canopy app; refusing to replace it." >&2; exit 1; }
  mv "$destination" "${destination%.app}.previous-$(date +%s).app"
fi
mkdir -p "$(dirname "$destination")"
ditto "$source_app" "$destination"
echo "Installed $destination"
