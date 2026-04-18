#!/bin/bash
# Run contract-conformance tests for basics/ocr-vision.
# Usage: ./test.sh
#
# This script is needed on macOS systems with Command Line Tools only (no Xcode).
# On macOS with Xcode installed, `swift test` works directly.
# On Command Line Tools only, we need to:
#   1. Pass the Testing.framework search path to the Swift compiler
#   2. Symlink Testing.framework into the test build output so dyld can find it at runtime
#
# On CI (GitHub Actions macos-14), Xcode is preinstalled and `swift test` works directly
# without this script.
set -euo pipefail

TESTING_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"
TESTING_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib"

# Build the release binary first (required by tests — they invoke the built binary)
swift build -c release

# Determine test build output directory
BUILD_DIR=".build/arm64-apple-macosx/debug"
if [ ! -d "$BUILD_DIR" ]; then
  BUILD_DIR=".build/$(uname -m)-apple-macosx/debug"
fi

# On CI (Xcode present), swift test works directly
if xcrun -find xctest >/dev/null 2>&1; then
  swift test
  exit $?
fi

# Command Line Tools only path: set up framework symlinks then run swift test
if [ -d "$TESTING_FW" ] && [ -f "$TESTING_INTEROP" ]; then
  # Build test bundle first (compiles but may not run yet)
  swift build --build-tests \
    -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
    2>&1

  # Locate the actual debug dir (may vary by arch)
  for candidate in .build/arm64-apple-macosx/debug .build/x86_64-apple-macosx/debug; do
    if [ -d "$candidate" ]; then
      BUILD_DIR="$candidate"
    fi
  done

  # Symlink Testing.framework and lib_TestingInterop.dylib into the build dir so
  # dyld can resolve them when swift test runs the test bundle
  ln -sf "$TESTING_FW" "$BUILD_DIR/Testing.framework" 2>/dev/null || true
  ln -sf "$TESTING_INTEROP" "$BUILD_DIR/lib_TestingInterop.dylib" 2>/dev/null || true

  swift test \
    -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
else
  echo "test.sh: Swift Testing framework not found. Install Xcode or Command Line Tools 15+." >&2
  exit 1
fi
