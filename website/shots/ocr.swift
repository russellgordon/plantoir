// Prints every line of text Vision recognises in an image, one per line.
//
// Usage: swift ocr.swift <image.png>
//
// The capture's read-back check: every scene lists, in shots.json
// `expectText`, words its finished picture must show, and capture.py fails
// the scene when any is missing. That is what catches "the right window, the
// wrong state" — an empty plan, the other appearance, a sheet that never
// opened — which every failure in the marketing-screenshots skill's list was,
// and which no exit code reports.

import AppKit
import Foundation
import Vision

guard CommandLine.arguments.count == 2,
      let image: NSImage = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cgImage: CGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: swift ocr.swift <image.png>\n".data(using: .utf8)!)
    exit(2)
}

let request: VNRecognizeTextRequest = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
// Course codes and curriculum codes are not words; correcting "ICS3U" to a
// dictionary word would fail a picture that is right.
request.usesLanguageCorrection = false

let handler: VNImageRequestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    FileHandle.standardError.write("Text recognition failed: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
for observation in request.results ?? [] {
    if let candidate: VNRecognizedText = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
