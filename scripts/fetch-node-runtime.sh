#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pinned official arm64 build; runtime is part of the app, never downloaded at launch.
mkdir -p .build
ARCHIVE=node-v24.21.0-darwin-arm64.tar.gz
EXPECTED=bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057
curl -fsSL --max-time 120 "https://nodejs.org/dist/v24.21.0/$ARCHIVE" -o ".build/$ARCHIVE"
ACTUAL="$(shasum -a 256 ".build/$ARCHIVE" | cut -d ' ' -f 1)"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo 'Node runtime checksum mismatch; refusing to extract.' >&2
    exit 1
fi
tar -xzf ".build/$ARCHIVE" -C .build
