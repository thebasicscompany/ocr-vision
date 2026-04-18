import Testing
import Foundation

// ContractConformanceTests — verifies that the ocr-vision binary conforms
// byte-for-byte to architecture/contracts/ocr-sidecar.md v1.

/// Resolve the binary built by `swift build -c release`.
private func binaryPath() throws -> String {
  let pkgRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let buildRoot = pkgRoot.appendingPathComponent(".build")
  let fm = FileManager.default
  guard let enumerator = fm.enumerator(at: buildRoot, includingPropertiesForKeys: [.isExecutableKey]) else {
    throw SkipError("`.build` directory missing — run `swift build` first")
  }
  for case let url as URL in enumerator {
    if url.lastPathComponent == "ocr-vision",
       (try? url.resourceValues(forKeys: [.isExecutableKey]).isExecutable) == true {
      return url.path
    }
  }
  throw SkipError("ocr-vision binary not found in .build — run `swift build` first")
}

struct SkipError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

/// Fixture PNGs are copied into the test bundle via Package.swift resources.
private func fixturePath(_ name: String) -> String {
  let bundle = Bundle.module
  if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
             ?? bundle.url(forResource: name, withExtension: "png") {
    return url.path
  }
  return ""
}

private func runSidecar(request: [String: Any]) throws -> (stdout: String, exitCode: Int32) {
  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: try binaryPath())
  let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
  proc.standardInput = stdin
  proc.standardOutput = stdout
  proc.standardError = stderr
  try proc.run()
  let reqData = try JSONSerialization.data(withJSONObject: request)
  stdin.fileHandleForWriting.write(reqData)
  stdin.fileHandleForWriting.write("\n".data(using: .utf8)!)
  try stdin.fileHandleForWriting.close()
  proc.waitUntilExit()
  let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  return (out, proc.terminationStatus)
}

@Test func testFixtureReturnsExpectedRegions() throws {
  let path = fixturePath("hello-world")
  #expect(!path.isEmpty, "fixture hello-world.png missing from test bundle")
  let (out, code) = try runSidecar(request: ["image_path": path])
  #expect(code == 0)
  let json = try JSONSerialization.jsonObject(with: out.data(using: .utf8)!) as! [String: Any]
  #expect(json["ok"] as? Bool == true)
  let regions = json["regions"] as! [[String: Any]]
  #expect(!regions.isEmpty)
  let joined = regions.compactMap { $0["text"] as? String }.joined(separator: " ").lowercased()
  #expect(joined.contains("hello") || joined.contains("world"),
          "expected 'hello' or 'world' in OCR output, got: \(joined)")
  let meta = json["meta"] as! [String: Any]
  #expect(meta["platform"] as? String == "macos")
  #expect(meta["engine"] as? String == "vision")
}

@Test func testMissingFileReturnsFileNotFound() throws {
  let (out, code) = try runSidecar(request: ["image_path": "/tmp/does-not-exist-\(UUID().uuidString).png"])
  #expect(code == 0)
  let json = try JSONSerialization.jsonObject(with: out.data(using: .utf8)!) as! [String: Any]
  #expect(json["ok"] as? Bool == false)
  #expect(json["code"] as? String == "file_not_found")
}

@Test func testUnsupportedFormatReturnsStructuredError() throws {
  let tmpPath = NSTemporaryDirectory() + "not-an-image-\(UUID()).txt"
  try "hello".write(toFile: tmpPath, atomically: true, encoding: .utf8)
  defer { try? FileManager.default.removeItem(atPath: tmpPath) }
  let (out, code) = try runSidecar(request: ["image_path": tmpPath])
  #expect(code == 0)
  let json = try JSONSerialization.jsonObject(with: out.data(using: .utf8)!) as! [String: Any]
  #expect(json["ok"] as? Bool == false)
  #expect(json["code"] as? String == "unsupported_format")
}

@Test func testRegionsAreIntegerPixelBboxesSortedTopDown() throws {
  let path = fixturePath("multi-line")
  #expect(!path.isEmpty, "fixture multi-line.png missing from test bundle")
  let (out, _) = try runSidecar(request: ["image_path": path])
  let json = try JSONSerialization.jsonObject(with: out.data(using: .utf8)!) as! [String: Any]
  let regions = json["regions"] as! [[String: Any]]
  var prevY = -1
  for r in regions {
    let bbox = r["bbox"] as! [Int]
    #expect(bbox.count == 4, "bbox must be [x,y,w,h]")
    #expect(bbox.allSatisfy { $0 >= 0 }, "bbox values must be non-negative integers")
    #expect(bbox[1] >= prevY, "regions must be sorted top-to-bottom")
    prevY = bbox[1]
  }
}

@Test func testContractTopLevelKeysExact() throws {
  let path = fixturePath("hello-world")
  #expect(!path.isEmpty, "fixture hello-world.png missing from test bundle")
  let (out, _) = try runSidecar(request: ["image_path": path])
  let json = try JSONSerialization.jsonObject(with: out.data(using: .utf8)!) as! [String: Any]
  let keys = Set(json.keys)
  #expect(keys == ["ok", "regions", "meta"], "OK response must have exactly ok/regions/meta")
}
