#!/bin/bash
set -e

# Build OGUI Web Demo to WASM
# Requires Odin compiler with js_wasm32 target support

ODIN=odin

# Memory configuration (in pages, 1 page = 64KB)
INITIAL_PAGES=2000
MAX_PAGES=65536
INITIAL_BYTES=$((INITIAL_PAGES * 65536))
MAX_BYTES=$((MAX_PAGES * 65536))

echo "Building OGUI Web Demo..."
$ODIN build . -target:js_wasm32 -out:web/ogui_demo.wasm -o:size \
    -extra-linker-flags:"--export-table --import-memory --initial-memory=$INITIAL_BYTES --max-memory=$MAX_BYTES"

# Copy Odin JS runtime
ODIN_ROOT=$($ODIN root)
cp "$ODIN_ROOT/core/sys/wasm/js/odin.js" web/odin.js

echo "Build complete!"
echo "Open web/index.html in a browser, or run a local server:"
echo "  cd web && python3 -m http.server 8080"
echo "  Then visit http://localhost:8080"
