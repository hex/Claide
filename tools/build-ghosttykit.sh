#!/bin/bash
# ABOUTME: Builds GhosttyKit.xcframework from the vendored Ghostty source.
# ABOUTME: Requires Zig 0.14+ and Xcode with macOS SDK.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GHOSTTY_DIR="$PROJECT_DIR/ThirdParty/ghostty"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks"
OUTPUT_FRAMEWORK="$FRAMEWORK_DIR/GhosttyKit.xcframework"

# Pinned Ghostty commit for reproducible builds
GHOSTTY_COMMIT="main"

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

if ! command -v zig &>/dev/null; then
    echo "Error: zig not found. Install with: brew install zig"
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

# Zig build produces the XCFramework at a known location
BUILT_FRAMEWORK="$GHOSTTY_DIR/zig-out/macos/GhosttyKit.xcframework"

if [ ! -d "$BUILT_FRAMEWORK" ]; then
    echo "Error: XCFramework not found at $BUILT_FRAMEWORK"
    echo "Searching for it..."
    find "$GHOSTTY_DIR/zig-out" -name "GhosttyKit.xcframework" -type d 2>/dev/null
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
