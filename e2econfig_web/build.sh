#!/bin/bash
set -e

ODIN=odin

INITIAL_PAGES=2000
MAX_PAGES=65536
INITIAL_BYTES=$((INITIAL_PAGES * 65536))
MAX_BYTES=$((MAX_PAGES * 65536))

echo "Building E2E Config Web..."
$ODIN build . -target:js_wasm32 -out:web/e2econfig.wasm -o:size \
    -extra-linker-flags:"--export-table --import-memory --initial-memory=$INITIAL_BYTES --max-memory=$MAX_BYTES"

ODIN_ROOT=$($ODIN root)
cp "$ODIN_ROOT/core/sys/wasm/js/odin.js" web/odin.js

echo "Build complete!"
echo "Run a local server to test:"
echo "  cd web && python3 -m http.server 8080"
echo "  Then visit http://localhost:8080"
