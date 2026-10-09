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
        handoff.whenHandedOver = { url, reason in
            told.append(PreviewBrowserHandoff.trailWords(for: url, reason: reason))
        }
        let address: URL = PreviewBrowserHandoff.printAddress(
            pageAddress: "http://localhost:8461/Unit-1/Worksheet-3", mode: "withAnswersAtTheEnd")!
        handoff.open(address)
        handoff.whenHandedOver?(address, .printHandout(mode: "withAnswersAtTheEnd"))
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
        let words: String = PreviewBrowserHandoff.trailWords(
            for: URL(string: "http://localhost:8461/Unit-1/Worksheet-3#plantoir-print=withAnswersAtTheEnd")!,
            reason: .printHandout(mode: "withAnswersAtTheEnd")
        )
        XCTAssertEqual(example, "{course}/{section} · " + words)
        let pdf: String = PreviewBrowserHandoff.trailWords(
            for: URL(string: "http://localhost:8461/Media/Key.pdf")!, reason: .newWindow)
        XCTAssertEqual(pdf, "preview page opened in the web browser — a page's own PDF (Media/Key.pdf)")
    }

    // MARK: - The guidance written into a working folder

    private var guidanceSource: URL {
        return PrintablePagesTests.repositoryRoot().appendingPathComponent("support/agent_guidance")
    }

    func testTheSkillAndBothPointersAreWrittenAtTheRoot() throws {
        let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.writeAgentGuidance(from: guidanceSource, into: folder)
        XCTAssertEqual(outcome.failed, 0)
        for home in [".claude", ".agents"] {
            let skill: URL = folder.appendingPathComponent("\(home)/skills/plantoir-printing/SKILL.md")
            let text: String = try String(contentsOf: skill, encoding: .utf8)
            XCTAssertTrue(text.contains("name: plantoir-printing"))
            XCTAssertTrue(text.contains("printable: true"))
            XCTAssertTrue(text.contains("printPdf"))
        }
        for name in ["AGENTS.md", "CLAUDE.md"] {
            let text: String = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            XCTAssertTrue(text.hasPrefix(WorkspaceModel.agentGuidanceMarker), "\(name) must say Plantoir manages it")
            XCTAssertTrue(text.contains("plantoir-printing"), "\(name) must name the skill")
        }
        let second: WorkspaceModel.MirrorOutcome = WorkspaceModel.writeAgentGuidance(from: guidanceSource, into: folder)
        XCTAssertEqual(second.changed, 0, "a second pass changes nothing")
    }

    func testTheContractNamesTheMarkerTheAppChecks() throws {
        let guidance: [String: Any] = try XCTUnwrap(
            try SharedRulesContractTests.section("printablePages")["agentGuidance"] as? [String: Any])
        XCTAssertEqual(guidance["managedMarker"] as? String, WorkspaceModel.agentGuidanceMarker)
        XCTAssertEqual(guidance["rootFiles"] as? [String], ["AGENTS.md", "CLAUDE.md"])
    }

    func testATeachersOwnFilesAndSkillsAreLeftAlone() throws {
        let fileManager: FileManager = FileManager.default
        let own: String = "# My own notes for Claude\n"
        try own.write(to: folder.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        let sibling: URL = folder.appendingPathComponent(".claude/skills/my-own-skill/SKILL.md")
        try fileManager.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "mine\n".write(to: sibling, atomically: true, encoding: .utf8)
        let settings: URL = folder.appendingPathComponent(".claude/settings.local.json")
        try "{}\n".write(to: settings, atomically: true, encoding: .utf8)

        _ = WorkspaceModel.writeAgentGuidance(from: guidanceSource, into: folder)

        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("CLAUDE.md"), encoding: .utf8), own,
                       "a CLAUDE.md without Plantoir's marker is the teacher's")
        XCTAssertEqual(try String(contentsOf: sibling, encoding: .utf8), "mine\n")
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{}\n")
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("AGENTS.md").path))
    }

    func testAManagedFileIsRewrittenAndAnExtraFileInTheSkillGoes() throws {
        let managed: URL = folder.appendingPathComponent("AGENTS.md")
        try (WorkspaceModel.agentGuidanceMarker + " old -->\nold words\n").write(to: managed, atomically: true, encoding: .utf8)
        let extra: URL = folder.appendingPathComponent(".agents/skills/plantoir-printing/old.md")
        try FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old\n".write(to: extra, atomically: true, encoding: .utf8)

        _ = WorkspaceModel.writeAgentGuidance(from: guidanceSource, into: folder)

        let rewritten: String = try String(contentsOf: managed, encoding: .utf8)
        XCTAssertFalse(rewritten.contains("old words"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extra.path), "the skill's folder is the app's, whole")
    }
}
