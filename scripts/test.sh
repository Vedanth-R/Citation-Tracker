#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift test "${CITEKIT_FLAGS[@]}" --disable-xctest "$@"
