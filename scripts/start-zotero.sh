#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CITEKIT_ZOTERO_DIR="$PWD/.build/zotero-server"
if [[ ! -d "$CITEKIT_ZOTERO_DIR/node_modules" ]]; then
    echo "Zotero Translation Server dependencies are missing. See README.md (Build and run)." >&2
    exit 1
fi
cd "$CITEKIT_ZOTERO_DIR"
export NODE_CONFIG='{"host":"127.0.0.1","port":1969}'
exec node src/server.js
