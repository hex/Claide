#!/bin/bash
# ABOUTME: Builds GhosttyKit.xcframework from the vendored Ghostty source.
# ABOUTME: Requires Zig 0.14+ and Xcode with macOS SDK.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$PROJECT_DIR/ThirdParty/ghostty"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks"
OUTPUT_FRAMEWORK="$FRAMEWORK_DIR/GhosttyKit.xcframework"

# Pinned Ghostty version for reproducible builds
GHOSTTY_COMMIT="v1.2.3"

usage() {
    echo "Usage: $0 [--clean] [--commit <sha>]"
    echo "  --clean    Remove cached build artifacts before building"
    echo "  --commit   Override the pinned Ghostty commit"
    exit 1
}

CLEAN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN=true; shift ;;
        --commit) GHOSTTY_COMMIT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# --- Preflight checks ---

# Use local Zig from ThirdParty if available, otherwise fall back to PATH
LOCAL_ZIG="$PROJECT_DIR/ThirdParty/zig/zig"
if [ -x "$LOCAL_ZIG" ]; then
    export PATH="$(dirname "$LOCAL_ZIG"):$PATH"
elif ! command -v zig &>/dev/null; then
    echo "Error: zig not found."
    echo "  Option 1: Extract Zig 0.14+ to ThirdParty/zig/"
    echo "  Option 2: Install with: brew install zig"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "Using Zig $ZIG_VERSION"

if ! command -v xcodebuild &>/dev/null; then
    echo "Error: xcodebuild not found. Install Xcode command line tools."
    exit 1
fi

# --- Clone or update Ghostty ---

if [ ! -d "$GHOSTTY_DIR" ]; then
    echo "Cloning Ghostty..."
    mkdir -p "$(dirname "$GHOSTTY_DIR")"
    git clone https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
fi

cd "$GHOSTTY_DIR"

CURRENT_COMMIT=$(git rev-parse HEAD)
TARGET_COMMIT=$(git rev-parse "$GHOSTTY_COMMIT")

if [ "$CURRENT_COMMIT" != "$TARGET_COMMIT" ]; then
    echo "Checking out Ghostty $GHOSTTY_COMMIT..."
    git fetch origin
    git checkout "$GHOSTTY_COMMIT"
fi

echo "Ghostty at $(git rev-parse --short HEAD)"

# --- Apply patches ---

PATCHES_DIR="$PROJECT_DIR/tools/patches"
if [ -d "$PATCHES_DIR" ] && ls "$PATCHES_DIR"/*.patch &>/dev/null; then
    for patch in "$PATCHES_DIR"/*.patch; do
        if ! git apply --check "$patch" 2>/dev/null; then
            echo "Patch already applied: $(basename "$patch")"
        else
            echo "Applying patch: $(basename "$patch")"
            git apply "$patch"
        fi
    done
fi

# --- Build ---

if [ "$CLEAN" = true ]; then
    echo "Cleaning previous build..."
    rm -rf zig-out zig-cache .zig-cache
fi

echo "Building GhosttyKit (this takes a few minutes)..."
zig build \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=none \
    -Dsentry=false

# --- Locate and install XCFramework ---

# Ghostty's build system places the XCFramework at macos/ (used as an
# intermediate by xcodebuild), not inside zig-out/.
BUILT_FRAMEWORK="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"

if [ ! -d "$BUILT_FRAMEWORK" ]; then
    echo "Error: XCFramework not found at $BUILT_FRAMEWORK"
    echo "Searching for it..."
    find "$GHOSTTY_DIR" -name "GhosttyKit.xcframework" -type d 2>/dev/null
    exit 1
fi

echo "Installing XCFramework..."
mkdir -p "$FRAMEWORK_DIR"
rm -rf "$OUTPUT_FRAMEWORK"
cp -R "$BUILT_FRAMEWORK" "$OUTPUT_FRAMEWORK"

echo ""
echo "GhosttyKit.xcframework installed at:"
echo "  $OUTPUT_FRAMEWORK"
echo ""
echo "Contents:"
find "$OUTPUT_FRAMEWORK" -maxdepth 3 -type f | head -20
