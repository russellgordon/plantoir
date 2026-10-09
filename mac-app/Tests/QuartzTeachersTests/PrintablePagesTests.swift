import XCTest
@testable import QuartzTeachers

/// Printable pages (#454), the mac's share of it: the four course-wide print
/// settings, what a Save of them leaves on the trail, the preview handing a
/// page to the web browser, and the assistant guidance written into a working
/// folder. The rules themselves (which callout is an answer, the corners) are
/// the build's and the site's, gated by the shared Python and verify.sh.
@MainActor
final class PrintablePagesTests: XCTestCase {

    // MARK: - Stored properties

    private var folder: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-printable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func configuration(_ values: [String: Any]) -> CourseConfiguration {
        return CourseConfiguration(values: values, lastSavedData: Data())
    }

    private static func repositoryRoot() -> URL {
        return UserFacingLabelWordsTests.macAppRoot().deletingLastPathComponent()
    }

    // MARK: - The settings

    func testACourseWithNoPrintSettingsReadsTheDefaults() {
        let course: CourseConfiguration = configuration([:])
        XCTAssertEqual(course.printSchoolName, "")
        XCTAssertEqual(course.printBlanks, ["name", "date"])
        XCTAssertEqual(course.printSchoolNameAt, "header_left")
        XCTAssertEqual(course.printCourseCodeAt, "footer_left")
    }

    func testUnknownValuesReadAsNothingOrTheDefaultAndAreNotWrittenBack() {
        let course: CourseConfiguration = configuration([
            "print_blanks": ["seat", "class_number", "name"],
            "print_school_name_at": "top",
            "print_course_code_at": 7,
        ])
        XCTAssertEqual(course.printBlanks, ["name", "class_number"], "print order, unknown dropped")
        XCTAssertEqual(course.printSchoolNameAt, "header_left")
        XCTAssertEqual(course.printCourseCodeAt, "footer_left")
        XCTAssertEqual(course.values["print_blanks"] as? [String], ["seat", "class_number", "name"],
                       "reading must never rewrite what the file holds")
        XCTAssertEqual(course.values["print_school_name_at"] as? String, "top")
    }

    func testAnEmptyListMeansNoBlanks() {
        XCTAssertEqual(configuration(["print_blanks": [String]()]).printBlanks, [])
    }

    func testBlanksAreWrittenInPrintOrderAndAnEmptySchoolNameRemovesTheKey() {
        let course: CourseConfiguration = configuration(["print_school_name": "Lakefield"])
        course.printBlanks = ["class_number", "name"]
        XCTAssertEqual(course.values["print_blanks"] as? [String], ["name", "class_number"])
        course.printSchoolName = "   "
        XCTAssertNil(course.values["print_school_name"])
    }

    // MARK: - The trail

    private func snapshot(
        _ name: String = "", _ blanks: [String] = ["name", "date"],
        _ schoolAt: String = "header_left", _ codeAt: String = "footer_left"
    ) -> SettingsSaveNotice.PrintingSnapshot {
        return SettingsSaveNotice.PrintingSnapshot(
            schoolName: name, blanks: blanks, schoolNameAt: schoolAt, courseCodeAt: codeAt
        )
    }

    func testNothingChangedSaysNothing() {
        XCTAssertNil(SettingsSaveNotice.printingClause(before: snapshot("A"), after: snapshot("A")))
        XCTAssertNil(SettingsSaveNotice.printingClause(before: nil, after: snapshot()),
                     "a file with no settings yet compares with the defaults")
    }

    func testTheSchoolNameIsSetChangedOrClearedAndNeverNamed() {
        let set: String? = SettingsSaveNotice.printingClause(before: snapshot(), after: snapshot("Lakefield College School"))
        XCTAssertEqual(set, "school name set")
        let changed: String? = SettingsSaveNotice.printingClause(
            before: snapshot("Lakefield"), after: snapshot("Lakefield College School"))
        XCTAssertEqual(changed, "school name changed")
        let cleared: String? = SettingsSaveNotice.printingClause(before: snapshot("Lakefield"), after: snapshot())
        XCTAssertEqual(cleared, "school name cleared")
        for line in [set, changed, cleared] {
            XCTAssertFalse((line ?? "").contains("Lakefield"), "the trail must never carry the school's name")
        }
    }

    func testBlanksAndPlacesSayBeforeAndAfter() {
        let line: String? = SettingsSaveNotice.printingClause(
            before: snapshot(),
            after: snapshot("", ["name", "date", "class_number"], "none", "header_left")
        )
        XCTAssertEqual(
            line,
            "blanks Name, Date → Name, Date, Class #; school name top left → not printed; "
                + "course code bottom left → top left"
        )
        XCTAssertEqual(
            SettingsSaveNotice.printingClause(before: snapshot(), after: snapshot("", [])),
            "blanks Name, Date → none"
        )
    }

    func testTheSettingsSavedLineCarriesThePrintingClause() {
        let line: String = SettingsSaveNotice.trailLine(
            courseCode: "ICS3U", hiddenBefore: [], hiddenAfter: [],
            result: CourseConfiguration.WriteResult(), notice: nil,
            printingBefore: snapshot(), printingAfter: snapshot("Lakefield")
        )
        XCTAssertEqual(line, "saved the settings for ICS3U; printing: school name set")
    }

    // MARK: - The preview hands pages to the browser

    func testOnlyThePreviewsOwnPagesAndTheContractsModesAreOpened() throws {
        let opened: URL? = PreviewBrowserHandoff.printAddress(
            pageAddress: "http://localhost:8461/Unit-1/Worksheet-3", mode: "questionsOnly")
        XCTAssertEqual(opened?.absoluteString, "http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=questionsOnly")
        XCTAssertNil(PreviewBrowserHandoff.printAddress(pageAddress: "https://example.com/x", mode: "questionsOnly"))
        XCTAssertNil(PreviewBrowserHandoff.printAddress(pageAddress: "file:///etc/hosts", mode: "questionsOnly"))
        XCTAssertNil(PreviewBrowserHandoff.printAddress(pageAddress: "http://localhost:8461/x", mode: "everything"))

        let modes: [String: Any] = try XCTUnwrap(
            try SharedRulesContractTests.section("printablePages")["modes"] as? [String: Any])
        var named: [String] = []
        for entry in try XCTUnwrap(modes["list"] as? [[String: Any]]) {
            named.append(try XCTUnwrap(entry["mode"] as? String))
        }
        XCTAssertEqual(PreviewBrowserHandoff.modes, named, "the app accepts exactly the contract's ways of printing")
    }

    func testThePrintMessageOpensThePageAndTellsTheTrail() {
        let handoff: PreviewBrowserHandoff = PreviewBrowserHandoff()
        var opened: [URL] = []
        var told: [String] = []
        handoff.open = { url in opened.append(url) }
        handoff.whenHandedOver = { page, target, reason in
            told.append(PreviewBrowserHandoff.trailWords(page: page, target: target, reason: reason))
        }
        let address: URL = PreviewBrowserHandoff.printAddress(
            pageAddress: "http://localhost:8461/Unit-1/Worksheet-3", mode: "withAnswersAtTheEnd")!
        handoff.open(address)
        handoff.whenHandedOver?(address, address, .printHandout(mode: "withAnswersAtTheEnd"))
        XCTAssertEqual(opened, [address])
        XCTAssertEqual(told, [
            "preview page opened in the web browser — to print it with the answers at the end (Unit-1/Worksheet-3)",
        ])
    }

    func testTheTrailWordsMatchTheContractsExampleLine() throws {
        let events: [[String: Any]] = try XCTUnwrap(
            try SharedRulesContractTests.section("activityTrail")["mustRecord"] as? [[String: Any]])
        var example: String = ""
        for event in events where event["event"] as? String == ActivityTrail.Event.previewPageOpenedInBrowser.rawValue {
            example = (event["line"] as? String) ?? ""
        }
        let printed: URL = URL(string: "http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=withAnswersAtTheEnd")!
        let words: String = PreviewBrowserHandoff.trailWords(
            page: printed, target: printed, reason: .printHandout(mode: "withAnswersAtTheEnd")
        )
        XCTAssertEqual(example, "{course}/{section} · " + words)
        let page: URL = URL(string: "http://localhost:8461/Unit-1/Worksheet-3")!
        let pdf: String = PreviewBrowserHandoff.trailWords(
            page: page, target: URL(string: "http://localhost:8461/Media/Key.pdf")!, reason: .newWindow)
        XCTAssertEqual(pdf, "preview page opened in the web browser — the page's own PDF (Unit-1/Worksheet-3)")
    }

    /// Rule 5 (implementation review S2): a link's destination is something
    /// the teacher wrote, and a shared-document address is a key to it. The
    /// line names the page the teacher was on, and only the KIND of link.
    func testALinksDestinationNeverReachesTheTrail() {
        let page: URL = URL(string: "http://localhost:8461/Unit-1/Worksheet-3")!
        for secret in [
            "https://docs.google.com/document/d/1AbcSecretDocId/edit?usp=sharing",
            "https://zoom.us/j/81234567890",
            "mailto:teacher@school.ca",
        ] {
            let line: String = PreviewBrowserHandoff.trailWords(
                page: page, target: URL(string: secret)!, reason: .newWindow)
            XCTAssertEqual(line, "preview page opened in the web browser — a link to another site (Unit-1/Worksheet-3)")
            XCTAssertFalse(line.contains("Secret") || line.contains("8123") || line.contains("@"), line)
        }
        let external: String = PreviewBrowserHandoff.trailWords(
            page: URL(string: "https://example.com/x")!,
            target: URL(string: "https://example.com/y")!, reason: .newWindow)
        XCTAssertEqual(external, "preview page opened in the web browser — a link to another site (an unknown page)")
    }

    /// The real web view, as the preview builds it: the page's own print
    /// code posting to `plantoirPrint`, and a link that asks for a new
    /// window, both reach the browser. Before #454 both did nothing at all
    /// (plan review B1, measured on a bare WKWebView).
    func testThePreviewsWebViewHandsBothToTheBrowser() throws {
        let controller: WebPreviewController = WebPreviewController()
        var opened: [String] = []
        let printed: XCTestExpectation = expectation(description: "print request opened")
        let linked: XCTestExpectation = expectation(description: "new-window link opened")
        controller.browserHandoff.open = { url in
            opened.append(url.absoluteString)
            if url.absoluteString.contains("plantoir-print=") {
                printed.fulfill()
            } else {
                linked.fulfill()
            }
        }
        let page: String = """
        <html><body><a id="pdf" href="Media/Key.pdf" target="_blank">Print</a>
        <script>
        window.webkit.messageHandlers.plantoirPrint.postMessage({mode: "answersOnly", url: location.href});
        document.getElementById("pdf").click();
        </script></body></html>
        """
        controller.webView.loadHTMLString(page, baseURL: URL(string: "http://localhost:8461/Unit-1/Worksheet-3"))
        wait(for: [printed, linked], timeout: 10)
        XCTAssertTrue(opened.contains("http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=answersOnly"), "\(opened)")
        XCTAssertTrue(opened.contains("http://localhost:8461/Unit-1/Media/Key.pdf"), "\(opened)")
    }

    // MARK: - The guidance written into a working folder

    private var guidanceSource: URL {
        return PrintablePagesTests.repositoryRoot().appendingPathComponent("support/agent_guidance")
    }

    private func agentGuidanceContract() throws -> [String: Any] {
        return try XCTUnwrap(try SharedRulesContractTests.section("printablePages")["agentGuidance"] as? [String: Any])
    }

    private func filled(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "{start}", with: AgentGuidance.sectionStart)
            .replacingOccurrences(of: "{end}", with: AgentGuidance.sectionEnd)
    }

    /// Russell's P1 rulings: a managed SECTION - written, replaced, or added
    /// to a teacher's own file only after a yes - every case in the contract.
    func testEveryRootFileCaseHoldsAsTheContractSays() throws {
        let guidance: [String: Any] = try agentGuidanceContract()
        XCTAssertEqual(guidance["sectionStart"] as? String, AgentGuidance.sectionStart)
        XCTAssertEqual(guidance["sectionEnd"] as? String, AgentGuidance.sectionEnd)
        XCTAssertEqual(guidance["rootFiles"] as? [String], AgentGuidance.rootFiles)
        let block: [String: Any] = try XCTUnwrap(guidance["rootFileCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9, "the contract lost root-file cases")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var existing: String? = nil
            if let text = testCase["existing"] as? String {
                existing = filled(text)
            }
            var declined: String? = nil
            if let said = testCase["declined"] as? String {
                declined = said == "thisSection"
                    ? AgentGuidance.signature(of: "NEW")
                    : AgentGuidance.signature(of: "EARLIER")
            }
            let action: AgentGuidance.RootFileAction = AgentGuidance.action(
                existing: existing, body: "NEW", declinedSignature: declined)
            let expected: String = filled(try XCTUnwrap(testCase["result"] as? String))
            switch try XCTUnwrap(testCase["expect"] as? String) {
            case "write":
                XCTAssertEqual(action, .write(expected), name)
            case "replace":
                XCTAssertEqual(action, .replace(expected), name)
            case "unchanged":
                XCTAssertEqual(action, .unchanged, name)
                XCTAssertEqual(existing, expected, name)
            case "leave":
                XCTAssertEqual(action, .leave, name)
                XCTAssertEqual(existing, expected, name)
            case "ask":
                XCTAssertEqual(action, .ask, name)
                XCTAssertEqual(AgentGuidance.appended(to: existing ?? "", body: "NEW"), expected, name)
            default:
                XCTFail("\(name): an expectation this test does not know")
            }
            // The property the first version lacked: whatever a pass (or an
            // Add) leaves, the next pass leaves alone.
            if let after = (testCase["expect"] as? String), after != "leave" {
                XCTAssertEqual(
                    AgentGuidance.action(existing: expected, body: "NEW", declinedSignature: nil), .unchanged,
                    "\(name): a second pass must change nothing"
                )
            }
        }
    }

    /// `addCases`: Add reads the file again, and refuses one it can no longer
    /// read rather than writing the section over the teacher's text.
    func testAddReadsTheFileAgainAndRefusesOneItCannotRead() throws {
        let block: [String: Any] = try XCTUnwrap(try agentGuidanceContract()["addCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let fileURL: URL = folder.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-") + ".md")
            var before: Data? = nil
            switch try XCTUnwrap(testCase["file"] as? String) {
            case "readable":
                try (try XCTUnwrap(testCase["existing"] as? String)).write(to: fileURL, atomically: true, encoding: .utf8)
            case "unreadable":
                // Saved in another encoding: these bytes are not UTF-8.
                before = Data([0x4D, 0x79, 0x20, 0xE9, 0xE8, 0x0A, 0xFF, 0xFE])
                try before!.write(to: fileURL)
            default:
                break
            }
            let added: Bool = AgentGuidance.appendAfterYes(
                AgentGuidance.PendingAppend(fileName: "CLAUDE.md", fileURL: fileURL, body: "NEW"))
            switch try XCTUnwrap(testCase["expect"] as? String) {
            case "refused":
                XCTAssertFalse(added, name)
                XCTAssertEqual(try Data(contentsOf: fileURL), before, "\(name): the teacher's file must be untouched")
            default:
                XCTAssertTrue(added, name)
                let expected: String = filled(try XCTUnwrap(testCase["result"] as? String))
                XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), expected, name)
            }
        }
    }

    /// The trail line and the notice: the contract's example line is the
    /// app's own words, and the notice carries the system's sentence without
    /// a path or a doubled full stop.
    func testTheFailureLineIsTheContractsAndTheNoticeHasNoPath() throws {
        let events: [[String: Any]] = try XCTUnwrap(
            try SharedRulesContractTests.section("activityTrail")["mustRecord"] as? [[String: Any]])
        var example: String = ""
        for event in events where event["event"] as? String == ActivityTrail.Event.guidanceCouldNotBeWritten.rawValue {
            example = (event["line"] as? String) ?? ""
        }
        var outcome: AgentGuidance.Outcome = AgentGuidance.Outcome()
        outcome.note(".agents/skills/plantoir-printing", "You don’t have permission to save the file.")
        XCTAssertEqual(AgentGuidance.couldNotWriteLine(outcome.failures), example)
        XCTAssertEqual(
            AgentGuidanceWording.couldNotWrite(reason: try XCTUnwrap(outcome.firstReason)),
            "Plantoir could not put its guidance for assistants into this folder (You don’t have permission to save the file). Everything else works as usual."
        )
    }

    func testTheSheetsWordsAreTheContractsAndNameNoMachinery() throws {
        let words: [String: Any] = try XCTUnwrap(try agentGuidanceContract()["words"] as? [String: Any])
        let pairs: [(String, String)] = [
            ("askTitle", AgentGuidanceWording.askTitle(file: "{file}")),
            ("askFound", AgentGuidanceWording.askFound(file: "{file}")),
            ("askWhat", AgentGuidanceWording.askWhat),
            ("askYoursStays", AgentGuidanceWording.askYoursStays),
            ("showWhatIsAdded", AgentGuidanceWording.showWhatIsAdded),
            ("add", AgentGuidanceWording.add),
            ("notNow", AgentGuidanceWording.notNow),
            ("couldNotWrite", AgentGuidanceWording.couldNotWrite(reason: "{reason}")),
            ("dismiss", AgentGuidanceWording.dismiss),
        ]
        let forbidden: [String] = try UserFacingLabelWordsTests.forbiddenWords()
        for (key, said) in pairs {
            XCTAssertEqual(said, words[key] as? String, key)
            XCTAssertEqual(UserFacingLabelWordsTests.forbiddenWords(in: said, from: forbidden), [], key)
        }
    }

    func testAFreshFolderGetsTheSkillsAndBothFilesHoldingOnlyTheSection() throws {
        let outcome: AgentGuidance.Outcome = AgentGuidance.write(
            from: guidanceSource, into: folder, declined: { _ in nil }, forgetDeclined: { _ in })
        XCTAssertEqual(outcome.failures, [])
        XCTAssertEqual(outcome.pending, [])
        for home in [".claude", ".agents"] {
            let skill: String = try String(
                contentsOf: folder.appendingPathComponent("\(home)/skills/plantoir-printing/SKILL.md"), encoding: .utf8)
            XCTAssertTrue(skill.contains("name: plantoir-printing"))
            XCTAssertTrue(skill.contains("printable: true"))
        }
        for name in AgentGuidance.rootFiles {
            let text: String = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            XCTAssertTrue(text.hasPrefix(AgentGuidance.sectionStart), name)
            XCTAssertTrue(text.contains("plantoir-printing"), "\(name) must name the skill")
            XCTAssertTrue(text.hasSuffix(AgentGuidance.sectionEnd + "\n"), name)
        }
        let second: AgentGuidance.Outcome = AgentGuidance.write(
            from: guidanceSource, into: folder, declined: { _ in nil }, forgetDeclined: { _ in })
        XCTAssertEqual(second.changed, 0, "a second pass changes nothing")
    }

    func testATeachersOwnFileIsAskedAboutNotWrittenAndTheirSkillsAreLeftAlone() throws {
        let fileManager: FileManager = FileManager.default
        let own: String = "# My own notes for Claude\n\nAlways use British spelling.\n"
        try own.write(to: folder.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        let sibling: URL = folder.appendingPathComponent(".claude/skills/my-own-skill/SKILL.md")
        try fileManager.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "mine\n".write(to: sibling, atomically: true, encoding: .utf8)
        let settings: URL = folder.appendingPathComponent(".claude/settings.local.json")
        try "{}\n".write(to: settings, atomically: true, encoding: .utf8)

        let outcome: AgentGuidance.Outcome = AgentGuidance.write(
            from: guidanceSource, into: folder, declined: { _ in nil }, forgetDeclined: { _ in })

        XCTAssertEqual(outcome.pending.count, 1)
        XCTAssertEqual(outcome.pending.first?.fileName, "CLAUDE.md")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("CLAUDE.md"), encoding: .utf8), own,
                       "never appended without a yes")
        XCTAssertEqual(try String(contentsOf: sibling, encoding: .utf8), "mine\n")
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{}\n")
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(".claude/skills/plantoir-printing/SKILL.md").path),
                      "the skills are written whatever the answer")

        // Add: below their text, which is left exactly as it was.
        XCTAssertTrue(AgentGuidance.appendAfterYes(try XCTUnwrap(outcome.pending.first)))
        let after: String = try String(contentsOf: folder.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        XCTAssertTrue(after.hasPrefix(own + "\n" + AgentGuidance.sectionStart), after)
        let again: AgentGuidance.Outcome = AgentGuidance.write(
            from: guidanceSource, into: folder, declined: { _ in nil }, forgetDeclined: { _ in })
        XCTAssertEqual(again.pending, [], "once it has the section, it is kept up to date without asking")
    }

    func testNotNowIsRememberedUntilTheWordsChangeOrTheFileGoes() throws {
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: "plantoir-tests-\(UUID().uuidString)"))
        let pending: AgentGuidance.PendingAppend = AgentGuidance.PendingAppend(
            fileName: "CLAUDE.md", fileURL: folder.appendingPathComponent("CLAUDE.md"), body: "NEW")
        AgentGuidance.rememberDeclined(pending, in: defaults)
        let stored: String? = AgentGuidance.declinedSignature(forPath: pending.fileURL.path, in: defaults)
        XCTAssertEqual(AgentGuidance.action(existing: "Mine.\n", body: "NEW", declinedSignature: stored), .leave)
        XCTAssertEqual(AgentGuidance.action(existing: "Mine.\n", body: "NEWER", declinedSignature: stored), .ask)
        AgentGuidance.forgetDeclined(forPath: pending.fileURL.path, in: defaults)
        XCTAssertNil(AgentGuidance.declinedSignature(forPath: pending.fileURL.path, in: defaults))
    }

    /// Implementation review S1: a guidance write that fails is a notice and a
    /// trail line, and NEVER makes the folder "not ready".
    func testAGuidanceFailureNeverHoldsTheFolderBack() throws {
        try "not a folder".write(to: folder.appendingPathComponent(".claude"), atomically: true, encoding: .utf8)
        let outcome: AgentGuidance.Outcome = AgentGuidance.write(
            from: guidanceSource, into: folder, declined: { _ in nil }, forgetDeclined: { _ in })
        XCTAssertFalse(outcome.failures.isEmpty, "a file where a folder belongs cannot hold the skill")

        let readiness: ToolchainReadiness = ToolchainReadiness.shared
        readiness.noteReadyForTests(folder)
        readiness.applyGuidance(outcome, to: folder)
        XCTAssertEqual(readiness.state(of: folder), .ready)
        XCTAssertNil(readiness.reasonToWait(folder), "Preview, Deploy and New Course must not wait on guidance")
        XCTAssertNotNil(readiness.guidanceNotices[FolderIdentity.canonicalPath(folder.path)])
        readiness.dismissGuidanceNotice(for: folder)
        readiness.forgetEverything(about: folder)
    }

    /// And the toolchain copy no longer writes the guidance at all, so its
    /// own outcome cannot be failed by it.
    func testTheToolchainCopyDoesNotWriteTheGuidance() throws {
        let source: String = try String(
            contentsOf: UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers/Models/WorkspaceModel.swift"),
            encoding: .utf8)
        XCTAssertFalse(source.contains("AgentGuidance.write("), "the copy's outcome decides readiness; guidance must stay out of it")
    }
}
