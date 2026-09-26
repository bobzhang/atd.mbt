#!/bin/sh
# Regenerate the MoonBit code of the test fixtures from their ATD files.
# Usage: scripts/regen_fixtures.sh
set -eu
cd "$(dirname "$0")/.."
moon build --target native
ATDMBT="$PWD/_build/native/debug/build/cmd/atdmbt/atdmbt.exe"
for atd in src/tests/*/*.atd; do
  dir=$(dirname "$atd")
  (cd "$dir" && "$ATDMBT" "$(basename "$atd")")
done
moon fmt
