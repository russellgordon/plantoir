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
        // **This writes into the teacher's OWN state, deliberately.** A
        // UI-driven app does not know it is under test: `isRunningTests` asks
        // whether `XCTestCase` is loaded, and it is loaded in the RUNNER, not
        // in the app. So settings persist to the real preferences domain and
        // lines land in the real breadcrumb trail. Russell chose that on
        // 2026-09-08 — "I'd rather know that it works" — and the test-state
        // redirect is still owed (TODO.md). Until it lands, run these knowing
        // the trail will carry their launches.
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

        // Dumped BEFORE anything is typed, because typing is the step that
        // has been failing and the tree is what says why: the composer sits at
        // x≈2043 on this Mac, which is a second display, and a window that is
        // not key cannot take a synthesized keystroke.
        print("=== CONVERSATION TREE BEGIN ===")
        print(application.debugDescription)
        print("=== CONVERSATION TREE END ===")

        print("=== WINDOWS ===")
        for index in 0..<application.windows.count {
            let window: XCUIElement = application.windows.element(boundBy: index)
            print("[\(index)] title=\(window.title) id=\(window.identifier) frame=\(window.frame)")
        }
    }


    // MARK: - The rollover, through the window

    /// The whole conversation, as a teacher has it.
    ///
    /// **This is the one thing the contract scenarios cannot prove.** They
    /// drive a real `AssistAgent` and assert the transcript, which catches the
    /// reply going into the wrong field — but they cannot say whether the words
    /// reach a window, whether the plan card can be reached, or whether the
    /// section's site marker actually moved on disk. All three are asserted
    /// here.
    ///
    /// Four steps, not two, because asking before changing is ON: the rollover
    /// plans, the teacher approves, the question arrives; the answer plans, the
    /// teacher approves, the website changes.
    func testARolloverAsksAboutTheWebsiteAndAnsweringItMovesTheMarker() throws {
        try requireUITestsAreWanted()
        let application: XCUIApplication = try launchWithARolloverReadySection()
        openTheAssistant(on: "EXC2O", section: 1, in: application)

        // 1 — the rollover is planned, not done.
        say("roll this section over to a new year", in: application)
        let approve: XCUIElement = application.buttons["assistApproveButton"]
        if !approve.waitForExistence(timeout: 120) {
            print("=== NO PLAN CARD — WHAT IS ON SCREEN ===")
            print(application.windows["assistant-AppWindow-1"].debugDescription)
            XCTFail("Asking before changing is on, so a rollover must offer a plan first.")
            return
        }
        approve.click()

        // 2 — and the question reaches the teacher.
        XCTAssertTrue(
            waitForTheAssistantToSay(
                try sentence(named: "rolloverWebsiteQuestion"), in: application
            ),
            "The website question never appeared in the window."
        )

        let marker: URL = try XCTUnwrap(liveMarkerURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path),
            "Nothing has been answered yet, so the section must still be on last year's website."
        )

        // 3 — answering is a second turn, and plans again.
        say("roll this section over onto a new website", in: application)
        XCTAssertTrue(
            approve.waitForExistence(timeout: 120),
            "The answer is a write too, so it must offer its own plan."
        )
        approve.click()

        // 4 — and this time the website really changes.
        XCTAssertTrue(
            waitForTheAssistantToSay(
                try sentence(named: "rolloverIsOnANewWebsite"), in: application
            ),
            "The confirmation never appeared in the window."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: marker.path),
            "The section is still pinned to last year's website — the answer did nothing on disk."
        )
    }

    /// One of the assistant's sentences, by NAME, read from the contract.
    ///
    /// A UI test bundle cannot `@testable import` the app, so the alternative
    /// is typing the sentence here — the copy that keeps passing after the
    /// product's words change. The repository is found the way the contract
    /// tests find it, from this file's own path.
    private func sentence(named key: String) throws -> String {
        let contract: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/assist-wording.json")
        let parsed: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: contract)) as? [String: Any]
        )
        let wording: [String: String] = try XCTUnwrap(parsed["wording"] as? [String: String])
        return try XCTUnwrap(wording[key], "No sentence named \(key) in the contract")
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

        // The class dates. Written as JSON because a UI test bundle cannot
        // `@testable import` the app to call `SectionTimetableStore` — and
        // WITHOUT it the rollover refuses with "I don't know when this section
        // meets" and opens the schedule sheet instead, which is a different
        // test entirely and looks like a broken selector rather than a missing
        // fixture.
        let timetableURL: URL = courseURL
            .appendingPathComponent(".internal").appendingPathComponent("timetable")
        try FileManager.default.createDirectory(at: timetableURL, withIntermediateDirectories: true)
        let timetable: [String: Any] = [
            "sectionNumber": 1,
            "source": "timetable.xlsx, block H",
            // STRINGS, parsed by `CalendarDay(text:)` — not year/month/day
            // objects. Getting that wrong throws `halfRemembered`, and the
            // assistant then answers about the remembered timetable instead of
            // planning, which looks exactly like a missing plan card.
            "dates": ["2026-09-08", "2026-09-10"],
        ]
        try JSONSerialization.data(withJSONObject: timetable, options: [.sortedKeys])
            .write(to: timetableURL.appendingPathComponent("section1.json"))

        let markerURL: URL = courseURL.appendingPathComponent(".netlify_sites")
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
        try "{\"site\":\"last-year\"}".write(
            to: markerURL.appendingPathComponent("section1.json"),
            atomically: true, encoding: .utf8
        )

        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = workspaceURL.path
        // Plan mode follows the real preference, so "with plan mode ON, the
        // default" would really mean "with whatever was last chosen on this
        // Mac". Pinned through the argument domain, the way the marketing
        // tests pin window frames.
        application.launchArguments += ["-assistantAsksBeforeChanging", "YES"]
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
        // **The WINDOW has to be key, not just the app frontmost.** Activating
        // the app is not enough when the assistant opens on a second display —
        // this Mac puts it at x≈2022 — and a window that is not key rejects a
        // synthesized keystroke with "Neither element nor any descendant has
        // keyboard focus", which reads like a broken selector rather than a
        // window that simply is not focused.
        application.activate()
        let window: XCUIElement = application.windows["assistant-AppWindow-1"]
        XCTAssertTrue(window.waitForExistence(timeout: 30), "The assistant window is not open.")
        window.click()

        let field: XCUIElement = application.textFields["assistInputField"]
        XCTAssertTrue(field.isEnabled, "The assistant is not accepting typing yet.")
        field.click()
        field.typeText(sentence)
        application.typeKey(.return, modifierFlags: [])
    }

    /// Waits for any bubble in the conversation to carry this text.
    ///
    /// A reply surfaces as a `StaticText` whose VALUE is the sentence — read
    /// off the real element tree rather than assumed — so this matches on
    /// value rather than on an identifier the transcript does not carry.
    @discardableResult
    private func waitForTheAssistantToSay(
        _ fragment: String, in application: XCUIApplication, timeout: TimeInterval = 180
    ) -> Bool {
        let carries: NSPredicate = NSPredicate(format: "value CONTAINS %@", fragment)
        let bubble: XCUIElement = application.staticTexts.matching(carries).firstMatch
        return bubble.waitForExistence(timeout: timeout)
    }
}
