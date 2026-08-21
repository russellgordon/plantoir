import XCTest
@testable import QuartzTeachers

/// Pins how the engine's own output reaches a problem report — and, more
/// importantly, pins the property that makes reading it safe at all.
///
/// Until 2026-08-20 `llama-server`'s two streams went to `FileHandle.nullDevice`,
/// so a report from a teacher whose assistant was misbehaving carried nothing
/// the engine had said. That was not laziness: a redirected pipe nobody drains
/// fills up and blocks the engine on its next log write, mid-request, looking
/// exactly like a hung model — which is what wedged the Windows server. The mac
/// never had that bug BECAUSE it discarded the output.
///
/// So the output now goes to a FILE and a bounded tail of it is sampled. A file
/// has no reader to wait for; nothing is ever read on the engine's timetable.
@MainActor
final class AssistEngineLogTests: XCTestCase {

    // MARK: - The engine's output never goes through a pipe

    /// The load-bearing property, pinned the only way it can be: by reading
    /// the source. A `Pipe` here would pass every other test in this file and
    /// reintroduce the wedge, so "there is no Pipe in this file" is the
    /// assertion, and the comment above says why anyone would be tempted.
    func testTheEnginesOutputIsNeverReadThroughAPipe() throws {
        let sourceURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Models/Assist/AssistServerHost.swift")
        let source: String = try String(contentsOf: sourceURL, encoding: .utf8)

        var pipeLines: [String] = []
        for line in source.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }
            if trimmed.contains("Pipe(") || trimmed.contains("readabilityHandler") {
                pipeLines.append(trimmed)
            }
        }
        XCTAssertEqual(
            pipeLines, [],
            "The engine's output is going through a pipe again. An unread pipe fills up and blocks the engine mid-request — the wedge Windows had to fix and the mac never had. Write to a file and sample its tail."
        )
    }

    // MARK: - Reading the tail

    /// Each look shows what arrived SINCE the last one, so a sampler that
    /// runs every fifteen seconds does not write the same line four times a
    /// minute.
    func testEachLookShowsOnlyWhatIsNew() throws {
        let logURL: URL = try makeLog(holding: "first\nsecond\n")
        defer { try? FileManager.default.removeItem(at: logURL) }

        var mark: UInt64 = 0
        XCTAssertEqual(
            AssistServerHost.lines(in: logURL, since: &mark, atMost: 200),
            ["first", "second"]
        )
        XCTAssertEqual(
            AssistServerHost.lines(in: logURL, since: &mark, atMost: 200), [],
            "Nothing was written in between, so there is nothing new to say."
        )

        try append("third\n", to: logURL)
        XCTAssertEqual(
            AssistServerHost.lines(in: logURL, since: &mark, atMost: 200), ["third"]
        )
    }

    /// A log that has grown past the window is read from its recent end, and
    /// the fragment of a line that lands on is dropped rather than reported
    /// as a line the engine wrote.
    func testAVeryLongLogIsReadFromItsRecentEnd() throws {
        var written: String = ""
        var index: Int = 0
        while index < 20000 {
            written += "line \(index) with enough text on it to make this file large\n"
            index += 1
        }
        let logURL: URL = try makeLog(holding: written)
        defer { try? FileManager.default.removeItem(at: logURL) }

        var mark: UInt64 = 0
        let lines: [String] = AssistServerHost.lines(in: logURL, since: &mark, atMost: 6)
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines.last, "line 19999 with enough text on it to make this file large")
        for line in lines {
            XCTAssertTrue(line.hasPrefix("line "), "A fragment left by skipping ahead was reported as a whole line: \(line)")
        }
    }

    /// A file that has shrunk would otherwise leave the mark off the end and
    /// every later look empty for good.
    func testAShrunkenLogDoesNotSilenceEveryLaterLook() throws {
        let logURL: URL = try makeLog(holding: "a long first line\nand a second\n")
        defer { try? FileManager.default.removeItem(at: logURL) }

        var mark: UInt64 = 0
        _ = AssistServerHost.lines(in: logURL, since: &mark, atMost: 200)
        try "short\n".write(to: logURL, atomically: true, encoding: .utf8)

        var found: [String] = AssistServerHost.lines(in: logURL, since: &mark, atMost: 200)
        XCTAssertEqual(found, [], "The mark is past the new end, so this look has nothing to report — but it must reset.")
        try append("after the reset\n", to: logURL)
        found = AssistServerHost.lines(in: logURL, since: &mark, atMost: 200)
        XCTAssertEqual(found, ["after the reset"])
    }

    // MARK: - What counts as worth recording

    /// The filter, against lines taken verbatim from a real engine
    /// (llama.cpp build b10435, driven on this Mac on 2026-08-20).
    ///
    /// The point of the healthy half is that it is what a NORMAL start looks
    /// like: six warnings, none of which mean anything here. A filter that
    /// caught warnings would spend the whole trail budget on them before the
    /// teacher had asked their first question.
    func testTheFilterKeepsTheTroubleAndDropsAHealthyStart() {
        let trouble: [String] = [
            "0.46.018.667 E srv    send_error: task id = 3, error: request (20030 tokens) exceeds the available context size (8192 tokens), try increasing it",
            #"0.45.886.270 W srv    operator(): got exception: {"error":{"code":500,"message":"[json.exception.parse_error.101] parse error at line 1, column 10"}}"#,
        ]
        for line in trouble {
            XCTAssertTrue(AssistSession.readsLikeATrouble(line), "This is exactly the line a report is for: \(line)")
        }

        let healthyStart: [String] = [
            "0.07.300.122 W srv  llama_server: -----------------",
            "0.07.300.127 W srv  llama_server: CORS is set to allow all origins ('*') and no API key is set",
            "0.07.300.127 W srv  llama_server: this can be a security risk (cross-origin attacks)",
            "0.07.300.127 W srv  llama_server: more info: https://github.com/ggml-org/llama.cpp/pull/25655",
            "0.07.488.084 W load: control-looking token: 128247 '</s>' was not control-type; this is probably a bug in the model. its type will be overridden",
            "0.07.990.066 I srv  llama_server: model loaded",
            "0.18.295.148 I slot print_timing: id  0 | task 0 | prompt eval time =      58.58 ms /    33 tokens",
            "0.07.986.963 I srv    load_model: initializing, n_slots = 1, n_ctx_slot = 8192, kv_unified = 'false'",
        ]
        for line in healthyStart {
            XCTAssertFalse(AssistSession.readsLikeATrouble(line), "A healthy start must leave the trail alone: \(line)")
        }
    }

    /// A line long enough to swamp the trail is cut, and one that is not is
    /// left exactly as the engine wrote it.
    func testALongLineIsCutAndAShortOneIsNot() {
        let short: String = "0.07.990.066 I srv  llama_server: model loaded"
        XCTAssertEqual(AssistSession.shortened(short), short)

        let long: String = String(repeating: "x", count: 500)
        let cut: String = AssistSession.shortened(long)
        XCTAssertEqual(cut.count, 201, "Two hundred characters and the ellipsis that says there were more.")
        XCTAssertTrue(cut.hasSuffix("…"))
    }

    // MARK: - Functions

    private func makeLog(holding text: String) throws -> URL {
        let logURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-log-\(UUID().uuidString).log")
        try text.write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    private func append(_ text: String, to logURL: URL) throws {
        let handle: FileHandle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
