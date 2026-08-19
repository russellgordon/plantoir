// Prints the window number of an application's window.
//
// `screencapture -l <window-number>` grabs THAT WINDOW's own contents,
// whatever is in front of it and wherever it sits — which a region capture
// cannot do. A region capture photographs a rectangle of the screen, so a
// window that had not finished coming to the front produced a screenshot of
// whatever was behind it. That happened, and the result was a picture of a
// terminal filed as a class website.
//
// With expected bounds, the window whose frame best matches is chosen —
// and nothing is printed if no window comes close. Without them, the
// largest ordinary window wins. Bounds are not optional decoration: the
// largest-window rule once photographed the developer's own logged-in
// Netlify dashboard and filed it as three class websites, because his
// browser window was bigger than the harness's.
//
// Usage: swift windowid.swift "Safari" [x y width height]

import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Safari"

var expected: CGRect? = nil
if CommandLine.arguments.count >= 6,
   let x = Double(CommandLine.arguments[2]),
   let y = Double(CommandLine.arguments[3]),
   let width = Double(CommandLine.arguments[4]),
   let height = Double(CommandLine.arguments[5]) {
    expected = CGRect(x: x, y: y, width: width, height: height)
}

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write("Could not list windows.\n".data(using: .utf8)!)
    exit(1)
}

var bestNumber: Int = 0
var bestScore: Double = -1

for window in windows {
    guard let name = window[kCGWindowOwnerName as String] as? String, name == owner else {
        continue
    }
    // Layer 0 is an ordinary document window; panels and overlays sit above.
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0 else {
        continue
    }
    guard let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Double,
          let y = bounds["Y"] as? Double,
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        continue
    }
    if let expected {
        // Smaller mismatch is better; stored negated so "bigger score wins"
        // reads the same in both modes.
        let mismatch = abs(x - expected.minX) + abs(y - expected.minY)
            + abs(width - expected.width) + abs(height - expected.height)
        let score = -mismatch
        if bestNumber == 0 || score > bestScore {
            bestScore = score
            bestNumber = number
        }
    } else {
        let area = width * height
        if area > bestScore {
            bestScore = area
            bestNumber = number
        }
    }
}

if bestNumber == 0 {
    FileHandle.standardError.write("No ordinary window found for \(owner).\n".data(using: .utf8)!)
    exit(2)
}

if let expected, bestScore < -40 {
    // The nearest window is nowhere near where the harness put its own.
    // Refusing beats photographing somebody else's window: a wrong
    // screenshot that looks like a right one is the worst failure here.
    FileHandle.standardError.write(
        "No \(owner) window matches the expected frame \(expected); nearest missed by \(-bestScore) points.\n"
            .data(using: .utf8)!
    )
    exit(3)
}

print(bestNumber)
