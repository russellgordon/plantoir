import XCTest
@testable import QuartzTeachers

/// A preview of a section cannot start while that same section is being
/// deployed, whoever started the deploy (GitHub #381, Russell's decision 4 on
/// #378). The contract is `shared-rules.json` → `previewWhileItsSectionDeploys`.
///
/// This class covers the WINDOW layer — `SectionDetailView.startPreview`
/// asking `refusalWhileThisSectionDeploys` first — and the app's halves of the
/// launcher layer (the failure explanation, the trail line). The launcher
/// itself is `scripts/test_preview_while_deploying.py`; the lease layer is
/// `WorkLeaseDecliningTests`, unchanged.
///
/// Resets `CourseActivity` and `WorkLeaseRegistry`, which are process-wide:
/// safe only because the scheme runs test classes one at a time (CLAUDE.md,
/// "The mac suite runs its test classes one at a time").
@MainActor
final class PreviewWhileDeployingTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL = URL(fileURLWithPath: "/")
    private var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Set up

    override func setUpWithError() throws {
        CourseActivity.reset()
        WorkLeaseRegistry.reset()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-while-deploying-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("courses/ICS4U"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("trail"), withIntermediateDirectories: true
        )
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
    }

    override func tearDownWithError() throws {
        CourseActivity.reset()
        WorkLeaseRegistry.reset()
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The window's rule

    /// The same window, another window and the in-app assistant with no
    /// window all deploy through ONE record — `CourseActivity.beginPublish`,
    /// written by the window's Deploy (`WorkLeaseRegistry.claimAPublish`) and
    /// by `AssistSiteWork.deploy` alike — so one refusal covers the three
    /// `window` cases in the contract.
    func testAPreviewOfTheSectionBeingDeployedIsRefused() {
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS4U", sectionNumber: 2)
        let refusal: String? = SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: root.path, courseCode: "ICS4U", displayCode: "ICS4U", sectionNumber: 2
        )
        XCTAssertEqual(refusal, AssistWording.sectionIsBeingDeployed(course: "ICS4U", section: "2"))
    }

    func testAnotherSectionOfTheSameCourseIsNotRefused() {
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS4U", sectionNumber: 2)
        XCTAssertNil(SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: root.path, courseCode: "ICS4U", displayCode: "ICS4U", sectionNumber: 1
        ), "the rule names the same section; widening it takes a working flow away")
    }

    func testTheSameSectionInAnotherWorkingFolderIsNotRefused() throws {
        let elsewhere: URL = root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        CourseActivity.beginPublish(folderPath: elsewhere.path, courseCode: "ICS4U", sectionNumber: 2)
        XCTAssertNil(SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: root.path, courseCode: "ICS4U", displayCode: "ICS4U", sectionNumber: 2
        ))
    }

    func testOnceTheDeployEndsThePreviewCanStart() {
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS4U", sectionNumber: 2)
        CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS4U", sectionNumber: 2)
        XCTAssertNil(SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: root.path, courseCode: "ICS4U", displayCode: "ICS4U", sectionNumber: 2
        ))
    }

    func testTheSentenceNamesTheCourseATeacherReads() {
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS4U-2025", sectionNumber: 2)
        let refusal: String? = SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: root.path, courseCode: "ICS4U-2025", displayCode: "ICS4U", sectionNumber: 2
        )
        XCTAssertEqual(refusal, AssistWording.sectionIsBeingDeployed(course: "ICS4U", section: "2"))
    }

    /// Every way into a window's preview goes through `startPreview`, and
    /// the question is asked there FIRST: before a build is recorded, before
    /// a port is leased, before other programs' leases are read. Read from
    /// the source because nothing in the suite constructs the view.
    func testStartPreviewAsksBeforeAnythingIsTaken() throws {
        let body: String = try codeLines(of: "SectionDetailView.swift", from: "    func startPreview() {",
                                          to: "        Task { @MainActor in")
        let asked: Range<String.Index> = try XCTUnwrap(
            body.range(of: "SectionDetailView.refusalWhileThisSectionDeploys("),
            "startPreview no longer asks whether its section is being deployed"
        )
        for later in ["previewBuildWait.begin(", "PreviewLeases.lease(", "WorkLeaseRegistry.whatBlocksABuild(",
                      "ReferenceLock.ensureLockedInBackground("] {
            let found: Range<String.Index> = try XCTUnwrap(body.range(of: later), later)
            XCTAssertLessThan(asked.lowerBound, found.lowerBound, "asked after \(later)")
        }
        XCTAssertTrue(body.contains("WorkLeaseRegistry.noteDeclinedWhileItsSectionDeploys("))
    }

    /// The windowless deploy writes the record the window reads — the gap
    /// the plan review found was that nothing READ it for a preview.
    func testTheAssistantsWindowlessDeployWritesTheRecordTheWindowReads() throws {
        let deploy: String = try codeLines(
            of: "AssistSiteWork.swift",
            from: "func deploy(course: Course, sectionNumber: Int) async -> AssistSiteWorkResult {",
            to: "\n    func "
        )
        XCTAssertTrue(deploy.contains("CourseActivity.beginPublish("))
    }

    // MARK: - The contract

    func testTheWindowSentenceIsTheContracts() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["previewWhileItsSectionDeploys"])
        let sentences: [String: Any] = try XCTUnwrap(rule["sentences"] as? [String: Any])
        XCTAssertEqual(sentences["window"] as? String, "wording.sectionIsBeingDeployed")
        XCTAssertEqual(sentences["windowTitle"] as? String, "Cannot Preview Yet")
        let wording: [String: Any] = try WorkLeaseLivenessTests.contract("assist-wording.json", ["wording"])
        let rendered: String = try XCTUnwrap(wording["sectionIsBeingDeployed"] as? String,
                                             "assist-wording.json has no sectionIsBeingDeployed; run --write-contracts")
        XCTAssertEqual(rendered, AssistWording.sectionIsBeingDeployed(course: "{course}", section: "{section}"))
        for word in ["workspace", "container", "script", "Docker"] {
            XCTAssertFalse(rendered.contains(word), word)
        }
    }

    func testEveryWindowCaseInTheContractIsARefusalOrAnotherSection() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["previewWhileItsSectionDeploys"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        var windowCases: Int = 0
        for testCase in cases {
            guard testCase["layer"] as? String == "window" else {
                continue
            }
            windowCases += 1
            CourseActivity.reset()
            CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS4U", sectionNumber: 2)
            let asked: Int = testCase["section"] as? String == "same" ? 2 : 1
            let refusal: String? = SectionDetailView.refusalWhileThisSectionDeploys(
                folderPath: root.path, courseCode: "ICS4U", displayCode: "ICS4U", sectionNumber: asked
            )
            let name: String = testCase["name"] as? String ?? "?"
            if testCase["expect"] as? String == "refused" {
                XCTAssertNotNil(refusal, name)
            } else {
                XCTAssertNil(refusal, name)
            }
        }
        XCTAssertEqual(windowCases, 4, "same window, another window, the in-app assistant, another section")
    }

    func testTheTrailLineIsTheContractsAndIsWritten() throws {
        let entry: [String: Any] = try trailEntry("build declined, course busy elsewhere")
        XCTAssertEqual(entry["lineWhenItsSectionIsBeingDeployed"] as? String,
                       WorkLeaseRegistry.lineWhenItsSectionIsBeingDeployed)
        WorkLeaseRegistry.noteDeclinedWhileItsSectionDeploys(courseCode: "ICS4U", sectionNumber: 2)
        let written: String = trailText()
        XCTAssertTrue(written.contains("ICS4U/2"), written)
        XCTAssertTrue(written.contains(WorkLeaseRegistry.lineWhenItsSectionIsBeingDeployed), written)
    }

    /// A preview the LAUNCHER refused (a deploy typed at a command line, or
    /// set for later) reaches the panel as the launcher's own sentence.
    func testTheLaunchersRefusalIsExplainedInItsOwnWords() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["previewWhileItsSectionDeploys"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["failureExplanationCases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for testCase in cases {
            let output: String = try XCTUnwrap(testCase["output"] as? String)
            XCTAssertEqual(FailureExplainer.explanation(in: output), testCase["expect"] as? String)
        }
        let sentences: [String: Any] = try XCTUnwrap(rule["sentences"] as? [String: Any])
        let launcher: [String] = try XCTUnwrap(sentences["launcher"] as? [String])
        XCTAssertTrue(launcher[0].contains(FailureExplainer.sectionIsBeingDeployedMarker))
    }

    // MARK: - The scheduled deploy's label, as the launchers read it (#388, N5)

    /// Every `labelCodeCases` case is what `ScheduledDeploy.sanitizedCode`
    /// writes into a scheduled deploy's label. The launchers' one reader of
    /// the process table runs the same cases (scripts/test_preview_while_deploying.py),
    /// so the two sides are held to one list rather than to each other.
    func testEveryLabelCodeCaseIsWhatAScheduledDeployIsNamed() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["previewWhileItsSectionDeploys"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["labelCodeCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8)
        for testCase in cases {
            let course: String = try XCTUnwrap(testCase["course"] as? String)
            let labelCode: String = try XCTUnwrap(testCase["labelCode"] as? String)
            XCTAssertEqual(ScheduledDeploy.sanitizedCode(course), labelCode, "course \"\(course)\"")
        }
    }

    /// Swift keeps any letter or digit in a label; the launchers keep only
    /// A-Z and 0-9. They agree on every code a teacher can make only because
    /// `CourseCodeRule` refuses every character they disagree on. This walks
    /// the whole Basic Multilingual Plane and holds that true — so the day
    /// the rule starts accepting an accented letter (French course names
    /// are common in Ontario), this fails instead of a scheduled deploy of
    /// that course quietly going unseen by the launchers.
    func testEveryCharacterACourseCodeMayHoldIsLabelledAsTheLaunchersLabelIt() {
        var disagreementsChecked: Int = 0
        var accepted: [String] = []
        for value in 0x20...0xFFFF {
            guard let scalar = Unicode.Scalar(value) else {
                continue
            }
            let character: Character = Character(scalar)
            let swiftWrites: String = ScheduledDeploy.sanitizedCode(String(character))
            let launchersWrite: String = launcherLabelCode(of: character)
            if swiftWrites == launchersWrite {
                continue
            }
            disagreementsChecked += 1
            let typed: String = "A" + String(character) + "1"
            if CourseCodeRule.trouble(typed, existingCodes: []) == nil {
                accepted.append(String(format: "U+%04X", value))
            }
        }
        XCTAssertGreaterThan(disagreementsChecked, 1000, "the walk found almost nothing to check")
        XCTAssertEqual(accepted, [], "a code holding these is accepted, and Swift and the launchers label it differently")
    }

    // MARK: - Functions

    /// The launchers' label code for one character: an ASCII letter
    /// upper-cased, an ASCII digit kept, and anything else "-"
    /// (the_launchers_running's label_code, in the PROCESS TABLE BLOCK).
    private func launcherLabelCode(of character: Character) -> String {
        if character.isASCII && (character.isLetter || character.isNumber) {
            return character.uppercased()
        }
        return "-"
    }

    private func trailEntry(_ event: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let trail: [String: Any] = try XCTUnwrap(all["activityTrail"] as? [String: Any])
        let entries: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for entry in entries {
            if entry["event"] as? String == event {
                return entry
            }
        }
        throw XCTSkip("no \(event) in the contract")
    }

    private func trailText() -> String {
        var text: String = ""
        let folder: URL = root.appendingPathComponent("trail")
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                text += String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    /// The code of one product file between two markers, comment lines left
    /// out so a comment naming the rule cannot pass the test.
    private func codeLines(of fileName: String, from start: String, to end: String?) throws -> String {
        var text: String = ""
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: ActivityTrailWiringTests.productSourceFolderURL()) {
            if fileURL.lastPathComponent == fileName {
                text = try String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        let from: Range<String.Index> = try XCTUnwrap(text.range(of: start), "\(fileName) has no \(start)")
        var upTo: String.Index = text.endIndex
        if let end, let found = text.range(of: end, range: from.upperBound..<text.endIndex) {
            upTo = found.lowerBound
        }
        var kept: [String] = []
        for line in text[from.lowerBound..<upTo].components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }
}
