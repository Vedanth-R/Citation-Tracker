#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/CiteKit.app"
SERVER="$PWD/.build/zotero-server"
RUNTIME="$PWD/.build/node-v24.21.0-darwin-arm64"
if [[ ! -x "$RUNTIME/bin/node" || ! -d "$SERVER/node_modules" ]]; then
    echo 'Missing Zotero build dependencies. See README.md (Build and run).' >&2
    exit 1
fi
DEST="$APP/Contents/Resources/Zotero"
mkdir -p "$DEST/server" "$APP/Contents/Helpers"
for folder in src config modules node_modules; do
    rsync -a --delete --exclude='.git' "$SERVER/$folder/" "$DEST/server/$folder/"
done
cp "$SERVER/package.json" "$SERVER/package-lock.json" "$SERVER/COPYING" "$DEST/server/"
cp "$RUNTIME/bin/node" "$APP/Contents/Helpers/node"
cp "$RUNTIME/LICENSE" "$DEST/NODE-LICENSE"
cp Support/Zotero/managed-server.cjs "$DEST/managed-server.cjs"
codesign --force --sign - "$APP/Contents/Helpers/node"
