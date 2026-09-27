import XCTest

/// The assistant's conversation is a plain stack, never a lazy one (#351).
///
/// After Approve the conversation's `LazyVStack` went into a placement loop
/// that never ended — the main thread 98% inside SwiftUI placing it, nothing
/// else on the main actor running, the window frozen. On the rollover UI test,
/// 2026-09-26: lazy, 2 runs in 13 passed; plain, 8 in 8, the question about a
/// second after Approve. A loop the unit suite cannot drive, so this reads the
/// source; the opt-in `AssistantRolloverUITests` drives the window.
final class AssistConversationStackTests: XCTestCase {

    func testTheConversationIsNotALazyStack() throws {
        let file: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Assist/AssistWindowView.swift")
        let text: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("private var conversation: some View"), "The conversation moved — point this test at it.")
        var lazyLines: [Int] = []
        var lineNumber: Int = 0
        for line in text.components(separatedBy: "\n") {
            lineNumber += 1
            let code: String = line.components(separatedBy: "//")[0]
            if code.contains("LazyVStack") {
                lazyLines.append(lineNumber)
            }
        }
        XCTAssertEqual(lazyLines, [], "A lazy stack in the assistant window froze it after Approve (#351).")
    }
}
