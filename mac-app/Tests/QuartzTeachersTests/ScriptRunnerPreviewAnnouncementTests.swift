import XCTest
@testable import QuartzTeachers

/// The preview's address is captured as output ARRIVES — GitHub #235.
///
/// It used to be read back off the last 8,000 characters of output, and the
/// launcher announces it EARLY: on a real first preview it had scrolled out of
/// that window by the time Quartz said its server had started. These feed the
/// runner the way a real run does — through `receiveOutput`, in pieces cut
/// wherever a read happens to end, with the terminal's CRLF line endings and
/// colour codes left in — and ask for the address EXACTLY, never just its
/// port: a collector that splits terminal text wrongly produces an address
/// with the right port and a garbage path, and a port check passes it.
///
/// The fixture, `Tests/Goldens/235-preview-first-build.json`, is one real
/// first preview's output captured through the same kind of pseudo-terminal
/// the app uses, on a scratch rehearsal folder, with its one personal path
/// replaced. A made-up transcript would be a guess at the very thing being
/// tested.
@MainActor
final class ScriptRunnerPreviewAnnouncementTests: XCTestCase {

    // MARK: - Stored properties

    /// What the fixture's launcher announced, written the way the app opens it.
    private let announcedInTheFixture: String = "http://127.0.0.1:8101/"

    // MARK: - A real first preview

    /// The measured fault: after the whole of a real first preview, the
    /// 8,000-character tail read found nothing.
    func testTheAddressSurvivesARealFirstPreview() throws {
        let output: String = try ScriptRunnerPreviewAnnouncementTests.fixtureOutput()
        let runner: ScriptRunner = ScriptRunner()
        for chunk in ScriptRunnerPreviewAnnouncementTests.chunks(of: output, size: 1_024) {
            runner.receiveOutput(chunk)
        }
        XCTAssertEqual(runner.previewAddress?.absoluteString, announcedInTheFixture)
    }

    /// Once announced, it is known after EVERY later piece of output — in
    /// particular at the moment the builder says its server started, which is
    /// when the wait for the preview needs it.
    func testOnceAnnouncedTheAddressIsNeverLostAgain() throws {
        let output: String = try ScriptRunnerPreviewAnnouncementTests.fixtureOutput()
        let runner: ScriptRunner = ScriptRunner()
        var seenAnAddress: Bool = false
        var chunksAfterTheAnnouncement: Int = 0
        for chunk in ScriptRunnerPreviewAnnouncementTests.chunks(of: output, size: 256) {
            runner.receiveOutput(chunk)
            if let address = runner.previewAddress {
                seenAnAddress = true
                chunksAfterTheAnnouncement += 1
                XCTAssertEqual(address.absoluteString, announcedInTheFixture)
            } else {
                XCTAssertFalse(seenAnAddress, "the address was known and then lost")
            }
        }
        XCTAssertTrue(seenAnAddress)
        XCTAssertGreaterThan(
            chunksAfterTheAnnouncement, 30,
            "the fixture no longer carries a long build after its announcement, so it no "
            + "longer tests what it was chosen for"
        )
        XCTAssertTrue(
            runner.transcript.displayText.contains(PreviewReachability.theBuilderSaysItsServerStarted),
            "the fixture should run on past the moment the wait needs the address"
        )
    }

    /// Pieces so small that the announcement line, the port and the CRLF are
    /// all cut in several places.
    func testTheAddressSurvivesTinyPieces() throws {
        let output: String = try ScriptRunnerPreviewAnnouncementTests.fixtureOutput()
        let runner: ScriptRunner = ScriptRunner()
        for chunk in ScriptRunnerPreviewAnnouncementTests.chunks(of: output, size: 7) {
            runner.receiveOutput(chunk)
        }
        XCTAssertEqual(runner.previewAddress?.absoluteString, announcedInTheFixture)
    }

    // MARK: - A line cut in two

    /// The announcement cut at EVERY point, including after `…localhost:8`,
    /// `:81` and `:810`. Read a piece at a time with nothing carried over,
    /// those three cuts produce a valid address on the WRONG port, and the
    /// rest of the line arrives without the words that mark it — measured by
    /// cutting the real line at every scalar.
    func testTheAnnouncementCutAnywhereIsReadWhole() {
        let line: String = "🌐 Preview will be available at: http://localhost:8101/\r\n"
        let scalars: [Unicode.Scalar] = Array(line.unicodeScalars)
        for cut in 1..<scalars.count {
            var first: String.UnicodeScalarView = String.UnicodeScalarView()
            var second: String.UnicodeScalarView = String.UnicodeScalarView()
            for (index, scalar) in scalars.enumerated() {
                if index < cut {
                    first.append(scalar)
                } else {
                    second.append(scalar)
                }
            }
            let runner: ScriptRunner = ScriptRunner()
            runner.receiveOutput("🔧 Building site for ICS4U, section 1...\r\n" + String(first))
            // Until its line ending has arrived, half a line is not an
            // announcement — least of all one on port 8, 81 or 810.
            let theLineHasEnded: Bool = cut > scalars.count - 2
            if !theLineHasEnded {
                XCTAssertNil(runner.previewAddress, "half a line was read, cut after \(cut) scalars")
            }
            runner.receiveOutput(String(second) + "📋 Timetable sections for this course: [1, 2]\r\n")
            XCTAssertEqual(
                runner.previewAddress?.absoluteString, "http://127.0.0.1:8101/",
                "cut after \(cut) of \(scalars.count) scalars"
            )
        }
    }

    // MARK: - Shapes of the line

    /// Colour codes around the line come out before it is read, a whole line
    /// at a time.
    func testAColouredAnnouncementIsReadExactly() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput(
            "\u{1B}[36m🌐 Preview will be available at: http://localhost:8092/\u{1B}[0m\r\n"
        )
        XCTAssertEqual(runner.previewAddress?.absoluteString, "http://127.0.0.1:8092/")
    }

    /// An announcement that is the very last thing a run prints, with no
    /// newline after it, is still read when the run ends.
    func testAnAnnouncementWithNoNewlineIsReadWhenTheRunEnds() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🌐 Preview will be available at: http://localhost:8093/")
        XCTAssertNil(runner.previewAddress, "an unfinished line is not an announcement yet")
        runner.simulateFinishForTesting(exitCode: 0)
        XCTAssertEqual(runner.previewAddress?.absoluteString, "http://127.0.0.1:8093/")
    }

    /// The last announcement wins, as it always has — and as Windows reads it.
    func testTheLastAnnouncementWins() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🌐 Preview will be available at: http://localhost:8081/\r\n")
        runner.receiveOutput("🌐 Preview will be available at: http://localhost:8092/\r\n")
        XCTAssertEqual(runner.previewAddress?.absoluteString, "http://127.0.0.1:8092/")
    }

    /// Nothing announced is nil — never a port somebody assumed.
    func testNothingAnnouncedIsNoAddress() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🚀 Launching Quartz preview on http://localhost:8081\r\n")
        runner.receiveOutput("Started a Quartz server listening at http://localhost:8081\r\n")
        XCTAssertNil(runner.previewAddress)
    }

    /// The words the contract says mark the line are the words read.
    func testTheContractsMarkerIsTheOneRead() throws {
        let rulesURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts")
            .appendingPathComponent("app-rules.json")
        let rules: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: rulesURL)) as? [String: Any]
        )
        let ports: [String: Any] = try XCTUnwrap(rules["previewPorts"] as? [String: Any])
        let announced: [String: Any] = try XCTUnwrap(ports["announcedAddress"] as? [String: Any])
        let marker: String = try XCTUnwrap(announced["marker"] as? String)

        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🌐 " + marker + "http://localhost:8095/\r\n")
        XCTAssertEqual(runner.previewAddress?.absoluteString, "http://127.0.0.1:8095/")
    }

    // MARK: - From one run to the next

    /// A new run forgets the last run's address; the second half of a task
    /// that continues the same output keeps it — the same rule, and the same
    /// single reset, as the health findings.
    func testANewRunForgetsTheAddressAndAContinuationKeepsIt() {
        let runner: ScriptRunner = ScriptRunner()
        runner.receiveOutput("🌐 Preview will be available at: http://localhost:8091/\r\n")

        runner.prepareForContinuationForTesting(keepingTranscript: true)
        XCTAssertEqual(runner.previewAddress?.absoluteString, "http://127.0.0.1:8091/")

        runner.prepareForContinuationForTesting(keepingTranscript: false)
        XCTAssertNil(runner.previewAddress)
    }

    // MARK: - Helpers

    private static func fixtureOutput() throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Goldens")
            .appendingPathComponent("235-preview-first-build.json")
        let fixture: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let output: String = try XCTUnwrap(fixture["output"] as? String)
        XCTAssertTrue(output.contains("\r\n"), "the fixture has lost its terminal line endings")
        return output
    }

    /// The output cut every `size` scalars, the way reads from a terminal
    /// cut it: with no regard for where lines, CRLF pairs or colour codes end.
    private static func chunks(of text: String, size: Int) -> [String] {
        var pieces: [String] = []
        var current: String.UnicodeScalarView = String.UnicodeScalarView()
        var count: Int = 0
        for scalar in text.unicodeScalars {
            current.append(scalar)
            count += 1
            if count == size {
                pieces.append(String(current))
                current = String.UnicodeScalarView()
                count = 0
            }
        }
        if !current.isEmpty {
            pieces.append(String(current))
        }
        return pieces
    }
}
