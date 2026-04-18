// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ocr-vision",
  platforms: [.macOS(.v10_15)],
  targets: [
    .executableTarget(
      name: "ocr-vision",
      path: "Sources/ocr-vision"
    ),
    .testTarget(
      name: "OcrVisionTests",
      dependencies: ["ocr-vision"],
      path: "Tests/OcrVisionTests",
      resources: [.copy("Fixtures")]
    )
  ]
)
