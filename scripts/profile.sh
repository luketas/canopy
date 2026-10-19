#!/bin/bash
set -euo pipefail
pid="${1:-$(pgrep -x Canopy | head -1)}"
[ -n "$pid" ] || { echo "Run Canopy first." >&2; exit 1; }
command="$(ps -p "$pid" -o comm=)"
case "$command" in */Canopy) ;; *) echo "PID does not belong to Canopy." >&2; exit 1 ;; esac
output="${2:-dist/profile-$(date +%s)}"
mkdir -p "$output"
ps -p "$pid" -o pid=,etime=,%cpu=,rss= > "$output/before.txt"
sample "$pid" 5 -file "$output/sample.txt"
ps -p "$pid" -o pid=,etime=,%cpu=,rss= > "$output/after.txt"
echo "Saved process statistics and a five-second stack sample to $output"
