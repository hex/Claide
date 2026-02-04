#!/bin/bash
# ABOUTME: Builds the claide-terminal Rust static library for the current architecture.
# ABOUTME: Called as an Xcode pre-build script phase.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CARGO_DIR="$SCRIPT_DIR"
OUT_DIR="$SCRIPT_DIR/target/lib"

mkdir -p "$OUT_DIR"

# Determine build profile from Xcode configuration
if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    PROFILE="release"
    CARGO_FLAGS="--release"
else
    PROFILE="debug"
    CARGO_FLAGS=""
fi

NATIVE_ARCH="$(uname -m)"
case "$NATIVE_ARCH" in
    arm64) RUST_TARGET="aarch64-apple-darwin" ;;
    x86_64) RUST_TARGET="x86_64-apple-darwin" ;;
    *) echo "error: unsupported architecture: $NATIVE_ARCH" >&2; exit 1 ;;
esac

echo "Building claide-terminal for $RUST_TARGET ($PROFILE)..."
cargo build $CARGO_FLAGS --manifest-path "$CARGO_DIR/Cargo.toml" -p claide-terminal

# Copy the static library to a stable output location
LIB_PATH="$CARGO_DIR/target/$PROFILE/libclaide_terminal.a"
if [ ! -f "$LIB_PATH" ]; then
    echo "error: expected library not found at $LIB_PATH" >&2
    exit 1
fi

cp "$LIB_PATH" "$OUT_DIR/libclaide_terminal.a"
echo "Installed: $OUT_DIR/libclaide_terminal.a"
