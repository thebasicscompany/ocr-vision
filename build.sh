#!/bin/bash
# Universal macOS build for basics/ocr-vision.
# Usage: ./build.sh <version>        (e.g., ./build.sh 0.0.0-smoke)
# Output: build/ocr-vision-universal  + build/ocr-vision-v<VERSION>-universal.tar.gz  + .sha256 sibling
set -euo pipefail

VERSION="${1:-dev}"
OUT_DIR="build"
mkdir -p "$OUT_DIR"

# Build for both architectures. `swift build -c release --arch arm64 --arch x86_64`
# works on GitHub Actions macos-14 (Xcode present). On machines with Command Line
# Tools only (no Xcode), we fall back to building each arch separately + lipo.
if xcrun -find xctest >/dev/null 2>&1; then
  # Xcode path: single-command universal build via XCBuild
  swift build -c release --arch arm64 --arch x86_64
  SRC=$(find .build -path "*/apple/Products/Release/ocr-vision" -type f 2>/dev/null \
       | head -1)
  if [ -z "$SRC" ]; then
    SRC=$(find .build -type f -name ocr-vision -perm -u+x | grep -v dSYM | head -1)
  fi
  if [ -z "$SRC" ]; then
    echo "build.sh: could not locate built ocr-vision binary under .build/" >&2
    exit 1
  fi
  cp "$SRC" "$OUT_DIR/ocr-vision-universal"
else
  # Command Line Tools path: build each arch separately then lipo-merge
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  ARM64_BIN=$(find .build/arm64-apple-macosx/release -maxdepth 1 -name ocr-vision -type f | head -1)
  X86_BIN=$(find .build/x86_64-apple-macosx/release -maxdepth 1 -name ocr-vision -type f | head -1)
  if [ -z "$ARM64_BIN" ] || [ -z "$X86_BIN" ]; then
    echo "build.sh: could not find arm64 or x86_64 binary under .build/" >&2
    exit 1
  fi
  lipo -create "$ARM64_BIN" "$X86_BIN" -output "$OUT_DIR/ocr-vision-universal"
fi

# Sanity: BOTH arches present (order may vary between lipo -create and --arch single-command).
if ! lipo -info "$OUT_DIR/ocr-vision-universal" | grep -q "arm64" \
   || ! lipo -info "$OUT_DIR/ocr-vision-universal" | grep -q "x86_64"; then
  echo "build.sh: universal binary missing arm64 + x86_64 slices:" >&2
  lipo -info "$OUT_DIR/ocr-vision-universal" >&2
  exit 1
fi

# Tarball naming mirrors basics/capture's pattern so Plan 07-02's fetch-ocr-vision.cjs
# is a 1:1 copy of fetch-captured.cjs conventions.
TARBALL="ocr-vision-v${VERSION}-universal.tar.gz"
tar -czf "$OUT_DIR/$TARBALL" -C "$OUT_DIR" ocr-vision-universal
( cd "$OUT_DIR" && shasum -a 256 "$TARBALL" > "$TARBALL.sha256" )

echo "build.sh: built $OUT_DIR/$TARBALL + $OUT_DIR/$TARBALL.sha256"
lipo -info "$OUT_DIR/ocr-vision-universal"
