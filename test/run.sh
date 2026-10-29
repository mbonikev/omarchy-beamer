#!/bin/bash
# Runs both suites. Neither touches the running compositor.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== engine"
"$HERE/engine.test.sh"

echo
echo "== model"
cd "$HERE"
# Capture state documents from the fixtures to feed the model its real input.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for fixture in two-heads three-heads scaled-head one-head-plus-virtual no-heads; do
  HOME="$WORK/$fixture" PATH="$HERE/stub:$PATH" LC_ALL=C \
    OMARCHY_DISPLAYS_HW_JSON="$(cat "$HERE/fixtures/$fixture.json")" \
    "$HERE/../bin/omarchy-displays" state >"$WORK/$fixture.json"
done
node model.test.js "$WORK"/*.json
