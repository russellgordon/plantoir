import XCTest
@testable import QuartzTeachers

/// A section's record of its problems, its Problems tab, its marker and its
/// alert (GitHub #717).
///
/// The rules are `contracts/shared-rules.json` → `sectionProblems`, walked
/// here as data: `rowState.cases` (a shared page fixed in another section,
/// and every way that must NOT clear it), `sectionMarker.cases` and
/// `alert.cases`; the wording and the retyped lists pinned to it key by
/// key; the store's key, ticks, tab and answers; and the view's half by a
/// source scan. The record itself is written by the shared Python
/// (`scripts/test_section_problems.py` runs its `rowCases`).
///
/// Serial with the other classes that reset process-wide statics: the scheme
/// runs test classes one at a time.
@MainActor
final class SectionProblemsTests: XCTestCase {

    // MARK: - Stored properties

    var answers: URL = FileManager.default.temporaryDirectory

    // MARK: - Set up

    override func setUp() async throws {
        SectionProblems.shared.reset()
        answers = try makeFolder("answers")
        SectionProblems.shared.acknowledgementFolder = answers
    }

    override func tearDown() async throws {
        SectionProblems.shared.reset()
        SectionProblems.shared.acknowledgementFolder = ProblemsAcknowledgements.folder()
    }

    // MARK: - The contract's cases

    /// `sectionProblems.rowState.cases`: a shared page's problem is "fixed in
    /// the source" only when another section's LATER build shows the page
    /// with no problem of that kind on it — never for a link, a reason about
    /// the machine, a page that section does not show, an older build, or a
    /// site-said kind before that section's site has said.
    func testRowStateCases() throws {
        let rule: [String: Any] = try XCTUnwrap(try section()["rowState"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let row: SectionProblemRow = SectionProblemRow(
                id: "here", kind: try XCTUnwrap(testCase["kind"] as? String),
                page: try XCTUnwrap(testCase["page"] as? String),
                reason: (testCase["reason"] as? String) ?? ""
            )
            let here: SectionProblemsRecord = record(builtAt: try XCTUnwrap(testCase["builtAt"] as? String), rows: [row])
            var others: [SectionProblemsRecord] = []
            for other in try XCTUnwrap(testCase["others"] as? [[String: Any]]) {
                var otherRows: [SectionProblemRow] = []
                for otherRow in (other["rows"] as? [[String: Any]]) ?? [] {
                    otherRows.append(SectionProblemRow(
                        id: "there", kind: try XCTUnwrap(otherRow["kind"] as? String),
                        page: try XCTUnwrap(otherRow["page"] as? String)
                    ))
                }
                others.append(record(
                    builtAt: try XCTUnwrap(other["builtAt"] as? String), rows: otherRows,
                    pagesShown: (other["pagesShown"] as? [String]) ?? [],
                    siteSaidComplete: (other["siteSaidComplete"] as? Bool) ?? false, section: 2
                ))
            }
            let state: SectionProblemsRules.RowState = SectionProblemsRules.state(of: row, in: here, others: others)
            XCTAssertEqual(state.rawValue, testCase["expect"] as? String, name)
        }
    }

    /// `sectionProblems.sectionMarker.cases`: the warning stays while the
    /// section's OWN record has a row, fixed in the source or not (ruling 11).
    func testSectionMarkerCases() throws {
        let rule: [String: Any] = try XCTUnwrap(try section()["sectionMarker"] as? [String: Any])
        for testCase in try XCTUnwrap(rule["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var made: SectionProblemsRecord?
            if let states = testCase["rows"] as? [String] {
                var rows: [SectionProblemRow] = []
                for (index, _) in states.enumerated() {
                    rows.append(SectionProblemRow(id: "row\(index)", kind: "figuresCouldNotBeDrawn", page: "Unit 1/Graphs"))
                }
                made = record(builtAt: "2026-11-01T09:00:00Z", rows: rows)
            }
            XCTAssertEqual(SectionProblemsRules.markerShows(made), testCase["expect"] as? Bool, name)
        }
    }

    /// `sectionProblems.alert.cases`, through the store and its answers file:
    /// a relaunch is a fresh read of the same file.
    func testAlertCases() throws {
        let rule: [String: Any] = try XCTUnwrap(try section()["alert"] as? [String: Any])
        let workingFolder: URL = try makeFolder("working")
        for testCase in try XCTUnwrap(rule["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let newCount: Int = try XCTUnwrap(testCase["new"] as? Int)
            let goneCount: Int = try XCTUnwrap(testCase["gone"] as? Int)
            var newIDs: [String] = []
            for index in 0..<newCount {
                newIDs.append("figuresCouldNotBeDrawn|p|tikz|k\(index)")
            }
            var goneIDs: [String] = []
            for index in 0..<goneCount {
                goneIDs.append("quizzesNotReady|p|\(index)")
            }
            let made: SectionProblemsRecord = record(
                builtAt: "2026-11-01T09:00:00Z", rows: [], newIDs: newIDs, goneIDs: goneIDs, alertKey: "key-\(name)"
            )
            var answered: Set<String> = []
            if testCase["answered"] as? Bool == true {
                var kept: ProblemsAcknowledgements = ProblemsAcknowledgements.read(in: answers, forWorkingFolder: workingFolder)
                kept.remember(answered: made.alertKey, courseCode: "MPM2D", sectionNumber: 1)
                kept.write(in: answers, forWorkingFolder: workingFolder)
                // A relaunch, or a second marker of the same build: the
                // answers come from the FILE, not from this test's memory.
                answered = ProblemsAcknowledgements.read(in: answers, forWorkingFolder: workingFolder)
                    .answered(courseCode: "mpm2d", sectionNumber: 1)
            }
            XCTAssertEqual(SectionProblemsRules.alertIsDue(made, answered: answered), testCase["expect"] as? Bool, name)
        }
    }

    // MARK: - Pinned to the contract

    /// The lists retyped in `SectionProblemsRules` are the contract's.
    func testTheRulesAreTheContracts() throws {
        let problems: [String: Any] = try section()
        let rule: [String: Any] = try XCTUnwrap(problems["rowState"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(rule["clearsAcrossSections"] as? [String])), SectionProblemsRules.clearsAcrossSections)
        let machine: [String: [String]] = try XCTUnwrap(rule["notAboutThePage"] as? [String: [String]])
        var retyped: [String: Set<String>] = [:]
        for (kind, reasons) in machine {
            retyped[kind] = Set(reasons)
        }
        XCTAssertEqual(retyped, SectionProblemsRules.notAboutThePage)
        var bySite: Set<String> = []
        var labels: [String: String] = [:]
        var scopes: [String: String] = [:]
        for kind in try XCTUnwrap(problems["kinds"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(kind["kind"] as? String)
            if kind["from"] as? String == "site" {
                bySite.insert(name)
            }
            labels[name] = kind["label"] as? String
            scopes[name] = kind["scope"] as? String
        }
        XCTAssertEqual(bySite, SectionProblemsRules.saidByTheSite)
        XCTAssertEqual(labels, SectionProblemsWording.kindLabels)
        XCTAssertEqual(scopes, SectionProblemsWording.kindScopes)
        let marker: [String: Any] = try XCTUnwrap(problems["marker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, SectionProblemsMarker.prefix)
        let alert: [String: Any] = try XCTUnwrap(problems["alert"] as? [String: Any])
        XCTAssertEqual(alert["acknowledgedKept"] as? Int, ProblemsAcknowledgements.kept)
        let file: [String: Any] = try XCTUnwrap(problems["file"] as? [String: Any])
        XCTAssertEqual(file["name"] as? String, SectionProblemsRecord.fileName)
        XCTAssertEqual(file["version"] as? Int, SectionProblemsRecord.version)
    }

    /// Every sentence, key by key, each called with its `{placeholder}`.
    func testTheWordsAreTheContracts() throws {
        let words: [String: String] = try XCTUnwrap(try section()["words"] as? [String: String])
        let said: [String: String] = [
            "tabWebsite": SectionProblemsWording.tabWebsite,
            "tabProblems": SectionProblemsWording.tabProblems,
            "columnIncluded": SectionProblemsWording.columnIncluded,
            "columnKind": SectionProblemsWording.columnKind,
            "columnPage": SectionProblemsWording.columnPage,
            "columnProblem": SectionProblemsWording.columnProblem,
            "columnFirstFound": SectionProblemsWording.columnFirstFound,
            "columnLastFound": SectionProblemsWording.columnLastFound,
            "wholeSection": SectionProblemsWording.wholeSection,
            "wholeCourse": SectionProblemsWording.wholeCourse,
            "intro": SectionProblemsWording.intro(course: "{course}", section: "{section}"),
            "fixedInTheSource": SectionProblemsWording.fixedInTheSource,
            "alertTitleOne": SectionProblemsWording.alertTitleOne(course: "{course}", section: "{section}"),
            "alertTitleSeveral": SectionProblemsWording.alertTitleSeveral(count: "{count}", course: "{course}", section: "{section}"),
            "alertMessage": SectionProblemsWording.alertMessage,
            "alertAlsoGoneOne": SectionProblemsWording.alertAlsoGoneOne,
            "alertAlsoGoneSeveral": SectionProblemsWording.alertAlsoGoneSeveral(count: "{count}"),
            "show": SectionProblemsWording.show,
            "markerHelp": SectionProblemsWording.markerHelp,
        ]
        XCTAssertEqual(Set(said.keys), Set(words.keys), "every word in the contract has a Swift home, and no more")
        for (key, text) in said {
            XCTAssertEqual(text, words[key], key)
        }
    }

    /// Rule 1: nothing the tab, the marker or the alert says names the
    /// machinery.
    func testNothingSaidNamesTheMachinery() throws {
        let words: [String: String] = try XCTUnwrap(try section()["words"] as? [String: String])
        var texts: [String] = []
        for (_, text) in words {
            texts.append(text)
        }
        for (_, label) in SectionProblemsWording.kindLabels {
            texts.append(label)
        }
        for text in texts {
            for word in ["script", "Docker", "container", "toolchain", "Python", "JSON", "marker", "record"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(word), "\(word) in: \(text)")
            }
        }
    }

    // MARK: - Reading what the build wrote

    /// The marker the contract's example prints, read the way the runner
    /// reads it — glued behind half a line, too (#153's rule).
    func testTheMarkerIsReadFromItsPrefixOnward() throws {
        let marker: [String: Any] = try XCTUnwrap(try section()["marker"] as? [String: Any])
        let example: String = try XCTUnwrap((marker["examples"] as? [String])?.first)
        let read: [SectionProblemsMarker] = SectionProblemsMarker.markers(in: "Building…" + example + "\nmore")
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.course, "MPM2D")
        XCTAssertEqual(read.first?.section, 1)
        XCTAssertEqual(read.first?.rows, 3)
        XCTAssertEqual(read.first?.new, 1)
        XCTAssertTrue(BuildMarkerLine.isMachineLine(example), "the marker is kept out of the console")
    }

    /// A record in the shape `scripts/section_problems.py` writes is read
    /// whole; a different version, or nonsense, is no record.
    func testTheRecordIsReadAsTheBuildWritesIt() throws {
        let data: Data = Data(SectionProblemsTests.recordJSON.utf8)
        let read: SectionProblemsRecord = try XCTUnwrap(SectionProblemsRecord.parse(data))
        XCTAssertEqual(read.course, "MPM2D")
        XCTAssertEqual(read.section, 1)
        XCTAssertEqual(read.occasion, "preview")
        XCTAssertEqual(read.rows.count, 2)
        XCTAssertEqual(read.rows[0].kind, "figuresCouldNotBeDrawn")
        XCTAssertEqual(read.rows[0].page, "Unit 1/Graphs")
        XCTAssertEqual(read.rows[1].source, "deploy")
        XCTAssertTrue(read.rows[1].carried)
        XCTAssertNotNil(read.rows[0].firstSeen)
        XCTAssertEqual(read.newIDs, ["figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"])
        XCTAssertEqual(read.alertKey, "B2")
        XCTAssertEqual(SectionProblemsWording.pageColumn(for: read.rows[1]), SectionProblemsWording.wholeSection)
        XCTAssertNil(SectionProblemsRecord.parse(Data(SectionProblemsTests.recordJSON.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2").utf8)))
        XCTAssertNil(SectionProblemsRecord.parse(Data("{not".utf8)))
        XCTAssertEqual(SectionProblemsRecord.kind(ofID: "quizzesNotReady|Unit 1/Quiz|#2"), "quizzesNotReady")
        XCTAssertEqual(SectionProblemsRecord.kind(ofID: "mediaFolderMissing"), "mediaFolderMissing")
    }

    // MARK: - The store

    /// Read through the course's `.merged_output` link, under `SectionRuns`'
    /// key; one alert per alert key, still answered after a relaunch; ticks
    /// start included; the tab falls back to Website without problems.
    func testTheStoreReadsAnswersAndRemembers() throws {
        let (workingFolder, course) = try makeCourse(sections: [1, 2])
        try writeRecord(SectionProblemsTests.recordJSON, course: course, section: 1)
        let store: SectionProblems = SectionProblems.shared
        store.reload(folder: workingFolder, course: course)

        XCTAssertTrue(store.hasProblems(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1))
        XCTAssertFalse(store.hasProblems(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 2))
        XCTAssertTrue(store.hasProblems(folder: workingFolder, courseCode: "mpm2d", sectionNumber: 1),
                      "the course code is one course however it is cased")
        XCTAssertEqual(store.key(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1),
                       SectionRuns.key(folderPath: workingFolder.path, courseCode: "MPM2D", sectionNumber: 1),
                       "one spelling of the key, #706's")

        let due: SectionProblemsRecord = try XCTUnwrap(store.recordWithAnAlertDue(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1))
        store.answer(due, with: "Show", folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1)
        XCTAssertNil(store.recordWithAnAlertDue(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1))
        store.reset()
        store.reload(folder: workingFolder, course: course)
        XCTAssertNil(store.recordWithAnAlertDue(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1),
                     "answered, then the app opened again: not raised again (plan review, HIGH 2)")

        let rowID: String = "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"
        XCTAssertTrue(store.isTicked(rowID, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1), "ticked means included")
        store.setTicked(false, rowID: rowID, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1)
        XCTAssertFalse(store.isTicked(rowID, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1))

        store.show(.problems, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1)
        XCTAssertEqual(store.tab(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1), .problems)
        store.show(.problems, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 2)
        XCTAssertEqual(store.tab(folder: workingFolder, courseCode: "MPM2D", sectionNumber: 2), .website,
                       "a section with no problems shows its website")
    }

    /// The trail's line is written once per alert key — not again after a
    /// relaunch — and names kinds, never a page.
    func testTheTrailLineNamesKindsOnceAndNeverAPage() throws {
        let read: SectionProblemsRecord = try XCTUnwrap(SectionProblemsRecord.parse(Data(SectionProblemsTests.recordJSON.utf8)))
        let line: String = SectionProblemsRules.trailLine(for: read)
        XCTAssertEqual(line, "the preview found 1 new and 1 fewer problems (new: figuresCouldNotBeDrawn; gone: quizzesNotReady)")
        XCTAssertFalse(line.contains("Unit 1"), "never a page")
        let workingFolder: URL = try makeFolder("trail")
        SectionProblems.shared.noteOnTheTrailOnce(read, folder: workingFolder, courseCode: "MPM2D", sectionNumber: 1)
        let kept: ProblemsAcknowledgements = ProblemsAcknowledgements.read(in: answers, forWorkingFolder: workingFolder)
        XCTAssertEqual(kept.noted(courseCode: "MPM2D", sectionNumber: 1), ["B2"])
        XCTAssertEqual(ProblemsAcknowledgements.adding("x", to: Array(repeating: "y", count: 0)), ["x"])
        var many: [String] = []
        for index in 0..<30 {
            many = ProblemsAcknowledgements.adding("k\(index)", to: many)
        }
        XCTAssertEqual(many.count, ProblemsAcknowledgements.kept)
        XCTAssertEqual(many.last, "k29")
    }

    /// The trail event is the contract's.
    func testTheTrailEventIsNamedInTheContract() throws {
        let trail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        var events: [String] = []
        for entry in try XCTUnwrap(trail["mustRecord"] as? [[String: Any]]) {
            if let event = entry["event"] as? String {
                events.append(event)
            }
        }
        XCTAssertTrue(events.contains(ActivityTrail.Event.problemsChanged.rawValue))
    }

    // MARK: - The view

    /// The view's half, read from its source: the alert is raised from the
    /// record's marker and the store, never from a run's findings; the old
    /// per-build dialog's queue is gone; the Problems tab is drawn OVER the
    /// site rather than instead of it; and the sidebar shows ONE warning.
    func testTheViewRaisesOneAlertFromTheRecord() throws {
        let view: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        XCTAssertFalse(view.contains("heldHealthFindings"), "the per-build dialog's queue is gone")
        XCTAssertTrue(view.contains(".onChange(of: previewRunner.problemsMarkers.count)"))
        let showing: String = try body(of: "func showHealthFindings(", in: view)
        XCTAssertFalse(showing.contains("healthDialog = .findings"), "a run's findings never raise a dialog of their own")
        let raising: String = try body(of: "func raiseTheProblemsAlertIfDue()", in: view)
        XCTAssertTrue(raising.contains("recordWithAnAlertDue("))
        XCTAssertTrue(raising.contains("if healthDialog != nil || previewAlertIsUp {"))
        let deploy: String = try body(of: "func takeWhatTheDeployLeft(", in: view)
        XCTAssertTrue(deploy.contains("raiseTheProblemsAlertIfDue()"), "#706's findings come to the one alert")
        XCTAssertFalse(view.contains("TabView"), "the site's web view never leaves its container")
        let sidebar: String = try readSource("QuartzTeachers/Views/SidebarView.swift")
        let label: String = try body(of: "func sectionRowLabel(", in: sidebar)
        XCTAssertEqual(label.components(separatedBy: "Image(systemName: \"exclamationmark.triangle").count - 1, 1,
                       "one warning glyph on a row")
    }

    /// #772: the warning's identifier names the course as well as the
    /// section, in Windows' form (#734), because the sidebar is one list of
    /// every course and two courses' Section 1 rows shared an identifier.
    func testTheWarningsIdentifierNamesTheCourse() throws {
        XCTAssertEqual(
            SidebarView.warningIdentifier(courseCode: "MPM2D", sectionNumber: 1, stoppedPublish: false),
            "problemsBadge-MPM2D-section1"
        )
        XCTAssertEqual(
            SidebarView.warningIdentifier(courseCode: "MPM2D", sectionNumber: 1, stoppedPublish: true),
            "stoppedPublishBadge-MPM2D-section1"
        )
        XCTAssertNotEqual(
            SidebarView.warningIdentifier(courseCode: "MPM2D", sectionNumber: 1, stoppedPublish: false),
            SidebarView.warningIdentifier(courseCode: "SCH3U", sectionNumber: 1, stoppedPublish: false),
            "two courses' Section 1 warnings are told apart"
        )
        XCTAssertEqual(
            SidebarView.clockIdentifier(courseCode: "MPM2D", sectionNumber: 1),
            "scheduledDeployBadge-MPM2D-section1"
        )
    }

    /// #772: the row takes both identifiers from the rules above, and no
    /// identifier in the sidebar names the section alone. Read from the
    /// source, so the old section-only form fails here rather than merely
    /// failing to compile.
    func testNoWarningIdentifierNamesTheSectionAlone() throws {
        let sidebar: String = try readSource("QuartzTeachers/Views/SidebarView.swift")
        let label: String = try body(of: "func sectionRowLabel(", in: sidebar)
        XCTAssertTrue(label.contains("SidebarView.warningIdentifier("), "the warning takes its identifier from the rule")
        XCTAssertTrue(label.contains("SidebarView.clockIdentifier("), "the clock takes its identifier from the rule")
        XCTAssertFalse(sidebar.contains("\"problemsBadge-section"), "no identifier names the section alone")
        XCTAssertFalse(sidebar.contains("\"stoppedPublishBadge-section"), "no identifier names the section alone")
        XCTAssertFalse(sidebar.contains("\"scheduledDeployBadge-section"), "no identifier names the section alone")
    }

    /// #731 (implementation review H1): the add-ons offer's "Don't ask
    /// again" is presented from a view of its own, so it never reaches the
    /// Problems alert — where ticking it silently turned the offer off.
    /// There is ONE suppression toggle in the app's views, inside the offer's
    /// own host, and none in the section's view.
    func testOnlyTheAddOnsOfferCarriesASuppressionToggle() throws {
        let main: String = try readSource("QuartzTeachers/Views/MainWindowView.swift")
        let offer: String = try body(of: "private struct ObsidianAddOnsOfferDialog: ViewModifier {", in: main)
        let host: String = try body(of: "private var offerHost: some View {", in: offer)
        XCTAssertTrue(host.contains(".dialogSuppressionToggle("), "the offer keeps its box")
        XCTAssertTrue(host.contains("Color.clear.confirmationDialog("), "on a view of its own")
        let presenting: String = try body(of: "func body(content: Content) -> some View {", in: offer)
        XCTAssertFalse(presenting.contains("dialogSuppressionToggle"), "never on the window's content")
        XCTAssertTrue(presenting.contains("content.background {"))
        var toggles: Int = 0
        let views: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views")
        let walker: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)
        while let file = walker?.nextObject() as? URL {
            if file.pathExtension != "swift" {
                continue
            }
            let text: String = try String(contentsOf: file, encoding: .utf8)
            toggles += text.components(separatedBy: ".dialogSuppressionToggle(").count - 1
        }
        XCTAssertEqual(toggles, 1, "one suppression toggle in the app's views: the add-ons offer's")
        let section: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        XCTAssertFalse(section.contains("dialogSuppressionToggle"))
    }

    // MARK: - Helpers

    static let recordJSON: String = """
    {"version": 1, "course": "MPM2D", "section": 1, "buildId": "B2", "builtAt": "2026-11-01T13:00:00Z",
     "occasion": "preview", "pagesShown": ["Unit 1/Graphs"], "before": ["quizzesNotReady|Unit 1/Quiz|"],
     "siteSaidComplete": true, "alertKey": "B2",
     "changed": {"new": ["figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1"], "gone": ["quizzesNotReady|Unit 1/Quiz|"]},
     "rows": [
      {"id": "figuresCouldNotBeDrawn|Unit 1/Graphs|tikz|k1", "kind": "figuresCouldNotBeDrawn", "page": "Unit 1/Graphs",
       "reason": "undefinedCommand", "item": "“Unit 1/Graphs”, diagram 2, line 14: \\\\foo isn't a command LaTeX knows here",
       "sentence": "A diagram or graph on “Unit 1/Graphs” in MPM2D Section 1 could not be drawn.", "detail": "d",
       "fixable": false, "prompt": "p", "from": "build", "firstSeen": "2026-11-01T13:00:00Z", "lastSeen": "2026-11-01T13:00:00Z"},
      {"id": "filesTooLargeForCloudflare|Media/talk.mp4", "kind": "filesTooLargeForCloudflare", "page": "",
       "reason": "", "item": "Media/talk.mp4 (40.0 MB)", "sentence": "s", "detail": "d", "fixable": false, "prompt": "p",
       "from": "deploy", "carried": true, "firstSeen": "2026-10-30T08:00:00Z", "lastSeen": "2026-10-30T08:00:00Z"}
     ]}
    """

    func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("sectionProblems")
    }

    func record(
        builtAt: String, rows: [SectionProblemRow], pagesShown: [String] = [], siteSaidComplete: Bool = true,
        section: Int = 1, newIDs: [String] = [], goneIDs: [String] = [], alertKey: String = "B"
    ) -> SectionProblemsRecord {
        return SectionProblemsRecord(
            course: "MPM2D", section: section, buildId: "B", builtAt: SectionProblemsRecord.date(builtAt),
            occasion: "preview", rows: rows, pagesShown: pagesShown, newIDs: newIDs, goneIDs: goneIDs,
            siteSaidComplete: siteSaidComplete, alertKey: alertKey
        )
    }

    func makeFolder(_ name: String) throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SectionProblemsTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    func makeCourse(sections: [Int]) throws -> (URL, Course) {
        let workingFolder: URL = try makeFolder("course")
        let courseURL: URL = workingFolder.appendingPathComponent("courses/MPM2D", isDirectory: true)
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let configuration: [String: Any] = [
            "course_code": "MPM2D", "course_name": "Maths", "section_numbers": sections, "num_sections": sections.count,
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        return (workingFolder, Course(code: "MPM2D", directoryURL: courseURL, configuration: loaded))
    }

    func writeRecord(_ text: String, course: Course, section: Int) throws {
        let url: URL = SectionProblemsRecord.url(courseFolder: course.directoryURL, sectionNumber: section)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The text of the function starting at `signature`, to its closing brace
    /// at the same indent.
    func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        var lineStart: String.Index = start.lowerBound
        while lineStart > source.startIndex && source[source.index(before: lineStart)] != "\n" {
            lineStart = source.index(before: lineStart)
        }
        var indent: String = ""
        for character in source[lineStart..<start.lowerBound] {
            if character != " " {
                break
            }
            indent.append(character)
        }
        let rest: Substring = source[start.lowerBound...]
        guard let end = rest.range(of: "\n" + indent + "}\n") else {
            return String(rest)
        }
        return String(rest[..<end.upperBound])
    }
}
