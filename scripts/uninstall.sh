#!/bin/bash
set -euo pipefail
application="${1:-$HOME/Applications/Canopy.app}"
if pgrep -x Canopy >/dev/null; then echo "Quit Canopy first so it can restore windows." >&2; exit 1; fi
[ -d "$application" ] || { echo "Canopy is not installed at $application" >&2; exit 1; }
identifier="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$application/Contents/Info.plist")"
[ "$identifier" = "org.canopywm.Canopy" ] || { echo "This is not a Canopy app." >&2; exit 1; }
mkdir -p "$HOME/.Trash"
mv "$application" "$HOME/.Trash/Canopy-$(date +%s).app"
echo "Moved Canopy to Trash. Workspace data and backups are preserved. Disable Launch at Login in Settings before uninstalling."
