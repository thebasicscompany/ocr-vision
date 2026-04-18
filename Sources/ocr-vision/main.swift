import Foundation
import Vision
import CoreGraphics
import AppKit

// ---- Contract types (architecture/contracts/ocr-sidecar.md v1) ----
struct Request: Codable {
  let image_path: String
  let languages: [String]?
  let recognition_level: String?
}
struct Region: Codable {
  let text: String
  let bbox: [Int]
  let confidence: Double
}
struct Meta: Codable {
  let platform: String
  let engine: String
  let engine_version: String
  let elapsed_ms: Int
}
struct ResponseOk: Codable {
  let ok: Bool
  let regions: [Region]
  let meta: Meta
}
struct ResponseErr: Codable {
  let ok: Bool
  let code: String
  let message: String
}

// ---- Helpers ----
func emit<T: Encodable>(_ value: T) {
  let data = try! JSONEncoder().encode(value)
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func errorOut(_ code: String, _ message: String) -> Never {
  emit(ResponseErr(ok: false, code: code, message: message))
  exit(0) // structured error — exit 0 per contract
}

// ---- Read one line of stdin JSON ----
guard let input = readLine(strippingNewline: true),
      let data = input.data(using: .utf8),
      let req = try? JSONDecoder().decode(Request.self, from: data) else {
  FileHandle.standardError.write("ocr-vision: failed to read stdin JSON\n".data(using: .utf8)!)
  exit(1) // fatal pre-response
}

guard FileManager.default.fileExists(atPath: req.image_path) else {
  errorOut("file_not_found", "image_path does not exist or is not readable")
}

guard let nsImage = NSImage(byReferencingFile: req.image_path),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  errorOut("unsupported_format", "failed to decode image at image_path")
}

// ---- Vision wiring (adapted ~30 lines; see attribution block below) ----
// -----------------------------------------------------------------------------
// The block from `let start = Date()` through the `regions.append(...)` loop is
// adapted from xulihang/macOCR (MIT) — specifically the VNRecognizeTextRequest
// setup and observation→pixel-bbox conversion. Original:
//   https://github.com/xulihang/macOCR/blob/main/OCR/main.swift
// See LICENSE.third-party at repo root for the full notice. Everything outside
// this block (stdin reader, contract-shaped response emitter, error handling,
// SPM manifest, tests, build.sh, CI workflow) is original to basics/ocr-vision.
// -----------------------------------------------------------------------------
let start = Date()
let request = VNRecognizeTextRequest()
request.recognitionLevel = (req.recognition_level == "fast") ? .fast : .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = req.languages ?? ["en-US"]
if #available(macOS 13.0, *) {
  request.revision = VNRecognizeTextRequestRevision3
} else if #available(macOS 11.0, *) {
  request.revision = VNRecognizeTextRequestRevision2
}

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
  try handler.perform([request])
} catch {
  errorOut("engine_error", "Vision threw: \(error.localizedDescription)")
}

let observations = request.results ?? []
let imgW = CGFloat(cgImage.width)
let imgH = CGFloat(cgImage.height)
var regions: [Region] = []
for obs in observations {
  guard let top = obs.topCandidates(1).first else { continue }
  let box = obs.boundingBox // normalized [0..1], origin bottom-left
  let x = Int(box.minX * imgW)
  let w = Int(box.width * imgW)
  let h = Int(box.height * imgH)
  let y = Int((1.0 - box.maxY) * imgH) // flip to origin top-left per contract
  regions.append(Region(
    text: top.string.trimmingCharacters(in: .whitespacesAndNewlines),
    bbox: [x, y, w, h],
    confidence: Double(top.confidence)
  ))
}
// -----------------------------------------------------------------------------
// End adapted section.
// -----------------------------------------------------------------------------

let elapsed = Int(Date().timeIntervalSince(start) * 1000)
let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
emit(ResponseOk(
  ok: true,
  regions: regions,
  meta: Meta(platform: "macos", engine: "vision", engine_version: osVersion, elapsed_ms: elapsed)
))
exit(0)
