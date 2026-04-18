# ocr-vision

macOS OCR sidecar for the Basics platform. A purpose-built Swift binary that wraps Apple's `VNRecognizeTextRequest` and exposes a platform-agnostic JSON interface over stdin/stdout.

Satisfies [`architecture/contracts/ocr-sidecar.md`](https://github.com/thebasicscompany/architecture/blob/main/contracts/ocr-sidecar.md) v1 byte-for-byte.

## Overview

`ocr-vision` is one of three platform-specific OCR sidecars:

| Platform | Binary | Engine |
|---|---|---|
| macOS 10.15+ | `ocr-vision` (this repo) | Apple Vision |
| Windows 10+ | `ocr-winrt.exe` (deferred) | Windows.Media.Ocr |
| Linux | `ocr-tesseract` (deferred) | Tesseract 5 |

Each sidecar reads a JSON request on stdin and writes a JSON response on stdout. Consumers spawn one subprocess per frame — short-lived, crash-isolated.

## Quickstart

```bash
# Build for host architecture (dev iteration)
swift build -c release

# Run against an image
echo '{"image_path":"/absolute/path/to/frame.png"}' | .build/release/ocr-vision
```

Example response:

```json
{"ok":true,"regions":[{"text":"hello world","bbox":[20,12,186,38],"confidence":0.98}],"meta":{"platform":"macos","engine":"vision","engine_version":"macOS 26.0","elapsed_ms":42}}
```

## Universal binary

```bash
# Produces build/ocr-vision-universal + tarball + sha256
./build.sh 1.0.0
```

The `build/` directory is gitignored. The universal binary requires macOS 10.15+ and supports both Apple Silicon and Intel Macs.

## Tests

```bash
swift test
```

The test suite (`Tests/OcrVisionTests/ContractConformanceTests.swift`) asserts that the binary's JSON output conforms to `contracts/ocr-sidecar.md` v1 byte-for-byte, covering:

- Fixture PNG with known text → `ok: true`, correct `regions[]` shape
- Missing file → `ok: false`, `code: "file_not_found"`, exit 0
- Non-image file → `ok: false`, `code: "unsupported_format"`, exit 0
- Bounding boxes are integer pixels, sorted top-to-bottom
- Top-level keys are exactly `{ok, regions, meta}` (no extras, no missing)

## Releasing

Push a tag matching `v*` to trigger the GitHub Actions release workflow:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions on `macos-14` will:
1. Run `swift test`
2. Run `./build.sh <version>` to produce the universal binary
3. Attach `ocr-vision-v<version>-universal.tar.gz` and its `.sha256` sibling to the GitHub Release

Consumers (`basics/desktop`, `basics/capture`) pin to a specific release tag and verify the SHA-256 before use.

## Attribution

The ~30-line Vision wiring block in `Sources/ocr-vision/main.swift` (VNRecognizeTextRequest setup and observation→pixel-bbox conversion) is adapted from [xulihang/macOCR](https://github.com/xulihang/macOCR) under MIT. See `LICENSE.third-party` for the full notice.

Everything else (SPM manifest, stdin reader, contract-shaped response encoder, tests, build.sh, CI workflow) is purpose-built for basics/ocr-vision.
