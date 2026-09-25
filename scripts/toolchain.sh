# Shared local build configuration; source from the repository root.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
CITEKIT_FLAGS=()
CITEKIT_DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$CITEKIT_DEVELOPER_DIR" == */CommandLineTools && -d "$CITEKIT_DEVELOPER_DIR/SDKs/MacOSX26.5.sdk" ]]; then
    CITEKIT_FLAGS+=(--sdk "$CITEKIT_DEVELOPER_DIR/SDKs/MacOSX26.5.sdk")
fi

if [[ -d "$CITEKIT_DEVELOPER_DIR/usr/lib/swift/host/plugins/testing" ]]; then
    CITEKIT_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$CITEKIT_DEVELOPER_DIR/usr/lib/swift/host/plugins/testing")
fi
