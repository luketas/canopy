#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Fixture restriction is embedded before signing, so launching from Finder
# or native UI tools is scoped even when they cannot pass launch arguments.
CANOPY_OUTPUT_DIR="$(pwd)/dist/test" CANOPY_TEST_FIXTURE=1 bash scripts/build-app.sh debug native
bash scripts/build-fixture.sh
