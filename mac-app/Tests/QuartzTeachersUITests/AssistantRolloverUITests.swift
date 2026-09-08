import XCTest
import Darwin

/// The assistant driven through the REAL window, against a REAL model.
///
/// **Why this target and not the unit suite.** Building the rollover took
/// three adversarial reviews and every serious finding was at a seam ABOVE the
/// tool, each one behind a fully green unit suite: the reply text was written
/// into `detail`, which never reaches a teacher, so the feature was invisible
/// in the app and worked over MCP alone; plan mode is ON by default and the
/// plan card swallowed the answer turn, making the release unreachable in the
/// default configuration; and a Claude Code session had no argument to answer
/// with. A suite that calls `AssistToolRunner` directly can see none of those.
///
/// **No model is stubbed and nothing is bypassed.** The session spawns a real
/// `llama-server` and the window opens only when it is ready, which is why
/// these wait in minutes rather than seconds. The phrasings under test are
/// matched in CODE and never reach the model — that is what makes them
/// deterministic — but the READINESS they wait on is the real thing, and the
/// three bugs above all lived in that machinery rather than in the model.
///
/// **Opt-in, and part of no gate.** `PLANTOIR_UI_TESTS=1`, mirroring Windows'
/// `run-ui-tests.ps1` for the same reasons: it needs the foreground, it takes
/// minutes, and it wants the model weights present. A plain Cmd-U builds these
/// and runs none.
final class AssistantRolloverUITests: XCTestCase {

    // MARK: - Opting in

    /// Skips unless asked for, and says what is missing rather than failing
    /// mysteriously.
    private func requireUITestsAreWanted() throws {
        // **PARKED until tests stop writing into the teacher's own state.**
        // A UI-driven app does not know it is under test: `isRunningTests` asks
        // whether `XCTestCase` is loaded, and it is loaded in the RUNNER, not
        // in the app. So the driven app persists settings to the real
        // preferences domain, writes to the real `~/Library/Logs/Plantoir`
        // breadcrumb trail, and resolves the real `~/Library/LaunchAgents`.
        // Three runs of this file on 2026-09-08 put three launch lines into a
        // real trail before that was noticed. Windows bought this property with
        // `--state-dir`; the mac has no equivalent yet, and CLAUDE.md rule 9
        // cannot be satisfied by tidying up afterwards.
        throw XCTSkip(
            "Parked: a UI-driven app writes to the teacher's real settings, trail and LaunchAgents. "
            + "Land the test-state redirect first — see TODO.md."
        )
        // swiftlint:disable:next unreachable_code
        let environment: [String: String] = ProcessInfo.processInfo.environment
        guard environment["PLANTOIR_UI_TESTS"] == "1" else {
            throw XCTSkip(
                "Opt-in: set PLANTOIR_UI_TESTS=1. These drive the real app with a real assistant, "
                + "take minutes, and need the foreground."
            )
        }
        // The REAL home, via the password database. A UI test runner is
        // sandboxed, so `homeDirectoryForCurrentUser` and `HOME` both give it a
        // container path — and this check then reports "no weights" about a
        // folder the app never uses, which reads as a missing download rather
        // than as the test looking in the wrong place.
        let realHome: String = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let models: URL = URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Application Support/Plantoir/models")
        let weights: [String] = (try? FileManager.default.contentsOfDirectory(atPath: models.path)) ?? []
        var hasWeights: Bool = false
        for name in weights where name.hasSuffix(".gguf") {
            hasWeights = true
        }
        guard hasWeights else {
            throw XCTSkip(
                "No assistant weights in \(models.path). "
                + "Open Plantoir and let it download one, or these cannot run against a real model."
            )
        }
    }

    // MARK: - Learning the window

    /// Prints the assistant window's element tree once the conversation has
    /// something in it.
    ///
    /// Kept because the existing `AssistantTreeDump` needs the MARKETING
    /// workspace, which is built by the screenshot harness and is far more
    /// setup than this needs — and because the reply bubble carries no
    /// accessibility identifier, so how an answer is exposed has to be read
    /// off the real tree rather than assumed.
    func testDumpTheConversationTree() throws {
        try requireUITestsAreWanted()
        let application: XCUIApplication = try launchWithARolloverReadySection()

        openTheAssistant(on: "EXC2O", section: 1, in: application)
        say("what do students see right now?", in: application)

        print("=== CONVERSATION TREE BEGIN ===")
        print(application.debugDescription)
        print("=== CONVERSATION TREE END ===")
    }

    // MARK: - Driving the app

    /// A working folder whose EXC2O Section 1 is ready to be rolled over: a
    /// class page on the wrong day, class dates on file, and a site marker
    /// saying it has been published before.
    ///
    /// Seeded rather than assumed. The shared fixture builds the course and
    /// its settings the way a teacher's folder is laid out, but a fresh course
    /// has no timetable and has never been published — and a rollover needs
    /// both, or it refuses before reaching anything worth testing.
    private func launchWithARolloverReadySection() throws -> XCUIApplication {
        let workspaceURL: URL = try FixtureWorkspace.materialize()
        let courseURL: URL = workspaceURL
            .appendingPathComponent("courses").appendingPathComponent("EXC2O")

        let classesURL: URL = courseURL.appendingPathComponent("section1/All Classes")
        try FileManager.default.createDirectory(at: classesURL, withIntermediateDirectories: true)
        try """
        ---
        title: Unit 1, Day 1
        date: 2020-01-15
        ---
        Something to move.
        """.write(
            to: classesURL.appendingPathComponent("Unit 1, Day 1.md"),
            atomically: true, encoding: .utf8
        )

        let markerURL: URL = courseURL.appendingPathComponent(".netlify_sites")
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
        try "{\"site\":\"last-year\"}".write(
            to: markerURL.appendingPathComponent("section1.json"),
            atomically: true, encoding: .utf8
        )

        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = workspaceURL.path
        application.launch()
        liveMarkerURL = markerURL.appendingPathComponent("section1.json")
        return application
    }

    /// The marker the test asserts against on disk, kept so a test can check
    /// what the app did rather than only what it said.
    private var liveMarkerURL: URL?

    /// Opens the assistant on one section and waits for it to be READY —
    /// which means a real `llama-server` has started and warmed up.
    private func openTheAssistant(on code: String, section: Int, in application: XCUIApplication) {
        let courseRow: XCUIElement = application.outlines.staticTexts[code]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 30), "\(code) should be in the sidebar")
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])

        let sectionRow: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "sidebar-\(code)-section\(section)")
            .firstMatch
        XCTAssertTrue(sectionRow.waitForExistence(timeout: 20), "Section \(section) should be in the sidebar")
        sectionRow.rightClick()

        let assistantItem: XCUIElement = application.menuItems["Revise with Local AI Assistant…"]
        XCTAssertTrue(assistantItem.waitForExistence(timeout: 20), "The assistant should be offered")
        assistantItem.click()

        // Minutes, not seconds: the model is loaded and warmed up for real.
        let field: XCUIElement = application.textFields["assistInputField"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 300),
            "The assistant window never appeared."
        )

        // **ENABLED, not merely present.** The field is bound to
        // `canAcceptTyping`, which is false until a real `llama-server` has
        // started and warmed up — and a disabled field cannot take keyboard
        // focus, so typing into it fails with "Neither element nor any
        // descendant has keyboard focus", which reads like a focus bug rather
        // than a model that is still loading. Waiting on existence alone is
        // the same mistake the Windows suite records: a control can be there
        // and not usable.
        let deadline: Date = Date().addingTimeInterval(300)
        while !field.isEnabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(
            field.isEnabled,
            "The assistant never started accepting typing — llama-server did not become ready."
        )
    }

    /// Types one sentence and sends it.
    private func say(_ sentence: String, in application: XCUIApplication) {
        // The app has to be frontmost for synthesized keystrokes to land, and
        // a UI test can lose the front to anything the machine does while it
        // runs.
        application.activate()
        let field: XCUIElement = application.textFields["assistInputField"]
        XCTAssertTrue(field.isEnabled, "The assistant is not accepting typing yet.")
        field.click()
        field.typeText(sentence)
        application.typeKey(.return, modifierFlags: [])
    }
}
