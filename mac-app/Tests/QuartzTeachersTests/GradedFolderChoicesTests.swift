import XCTest
@testable import QuartzTeachers

/// Which folders the Marks checklist may OFFER — run from
/// `contracts/shared-rules.json` → `gradedFolders.choices` against a REAL
/// directory tree, because the rule is a walk and a walk over a fixture is not
/// a walk.
///
/// The failure being guarded is silent and permanent: the build counts a graded
/// folder at any depth, an absent `graded_folders` key means the historical rule
/// still applies, and the FIRST TICK freezes the pool. So a folder the checklist
/// fails to offer stops counting for marks from that tick onwards, and every
/// expectation it addressed reads as never evaluated.
///
/// Windows has run this same case list since 2026-09-06
/// (`Plantoir.Tests/GradedFolderChoicesTests.cs`); this side ran none of it
/// until now, which is what [issue #112] was for. A case proposed from either
/// platform now turns both suites red.
@MainActor
final class GradedFolderChoicesTests: XCTestCase {

    // MARK: - Stored properties

    /// One disposable root per test method, so two cases that both make a
    /// `Tasks` folder cannot see each other's tree.
    var root: URL = URL(fileURLWithPath: "/")

    /// The trail's store before this test pointed it at `root`. A removal
    /// through the list editor runs `folderWasRemoved`, which writes an
    /// `.itemExcluded` line — and without the redirect that line would land in
    /// the real `~/Library/Logs/Plantoir`.
    var previousTrailStore: ProblemReportStore?

    // MARK: - Functions

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("graded-choices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        previousTrailStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
    }

    override func tearDownWithError() throws {
        if let previousTrailStore {
            ActivityTrail.store = previousTrailStore
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Removes a folder the way the teacher does, through the list editor
    /// Course Settings builds for that list: `removeItem(named:)` takes the
    /// name out of the list, then calls `onRemove`, which is
    /// `folderWasRemoved` — the exclusion, then the pool, then the trail line.
    ///
    /// Issue #183: these tests used to replay those steps by hand, in the
    /// order they were believed to run. A replay stays green when the shipped
    /// order changes, which is exactly the bug the contract's removal cases
    /// exist to catch, so the tests call the owner of the order instead.
    private func removeThroughTheListEditor(
        _ name: String,
        scope: FolderScope,
        in view: CourseSettingsView
    ) {
        let list: GestureList = scope == .shared ? .sharedFolders : .perSectionFolders
        let editor: StringListEditorView = CourseSettingsGestureScript.editor(for: list, of: view)
        editor.removeItem(named: name)
    }

    /// A course folder holding the given directories, and a configuration to
    /// go with it. Nothing here writes `course_config.json` into the course
    /// folder itself: a file is not a folder, and the walk must not offer one.
    @discardableResult
    private func makeCourse(
        named name: String,
        sharedFolders: [String] = [],
        perSectionFolders: [String] = [],
        gradedFolders: [String]? = nil,
        excludedItems: [String: [String]]? = nil,
        directories: [String] = []
    ) throws -> Course {
        let courseURL: URL = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        for relative in directories {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(relative), withIntermediateDirectories: true
            )
        }
        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "shared_folders": sharedFolders,
            "per_section_folders": perSectionFolders,
        ]
        if let gradedFolders {
            values["graded_folders"] = gradedFolders
        }
        if let excludedItems {
            values["excluded_items"] = excludedItems
        }
        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: Data())
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    private static func gradedFoldersSection() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["gradedFolders"] as? [String: Any])
    }

    private static func choicesRule() throws -> [String: Any] {
        return try XCTUnwrap(try gradedFoldersSection()["choices"] as? [String: Any])
    }

    // MARK: - The contract's own cases

    func testTheOfferedPoolMatchesTheContract() throws {
        let cases: [[String: Any]] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["cases"] as? [[String: Any]]
        )
        XCTAssertGreaterThanOrEqual(
            cases.count, 14,
            "The contract lost graded-folder-choice cases: \(cases.count) present, 14 expected at least."
        )

        var index: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: Course = try makeCourse(
                named: "case\(index)",
                sharedFolders: try XCTUnwrap(testCase["sharedFolders"] as? [String]),
                perSectionFolders: try XCTUnwrap(testCase["perSectionFolders"] as? [String]),
                excludedItems: testCase["excludedItems"] as? [String: [String]],
                directories: try XCTUnwrap(testCase["directories"] as? [String])
            )
            index += 1

            let offered: [String] = GradedFolderChoices.choices(
                for: course.configuration, courseDirectory: course.directoryURL
            )
            XCTAssertEqual(offered, try XCTUnwrap(testCase["expect"] as? [String]), name)
        }
    }

    /// The acceptance test the visible list alone would not have caught: what
    /// the teacher's first tick actually FREEZES is derived from the same list
    /// the checklist offers, so a nested folder survives it.
    func testTheFrozenPoolIsMaterialisedFromTheSameListTheChecklistOffers() throws {
        let course: Course = try makeCourse(
            named: "nested",
            sharedFolders: ["Concepts", "Portfolios"],
            perSectionFolders: ["All Classes"],
            directories: ["Concepts", "Portfolios", "Portfolios/Tasks"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        XCTAssertTrue(view.gradedFolderChoices.contains("Tasks"))
        XCTAssertNil(course.configuration.gradedFolders)
        XCTAssertTrue(view.gradedFoldersBinding.wrappedValue.contains("Tasks"))
    }

    /// The whole of issue #79, through the interface: a folder the teacher has
    /// REMOVED from the course does not come back into the Marks checklist on
    /// the next redraw, and the pool does not name it either.
    ///
    /// Both halves are needed and neither stands in for the other.
    /// `dropFromMarksPool` has always taken the name out of the pool; the
    /// folder was still sitting on disk, so the walk offered it back UNTICKED,
    /// and ticking it wrote a `graded_folders` naming a folder `excluded_items`
    /// tells the build to skip — a pool matching nothing the site publishes,
    /// while the settings claim something counts.
    ///
    /// The removal runs through the list editor's own `removeItem(named:)`, so
    /// it happens in the order Course Settings really does it (issue #183):
    /// `exclude` first, then `dropFromMarksPool`. That order matters for a
    /// course that has NEVER been asked — by the time the pool is touched the
    /// folder is no longer among the choices, so nothing is materialised and
    /// the key stays absent, which is the right answer rather than an
    /// oversight. This course has been asked, so the drop is unambiguous.
    func testAFolderRemovedFromTheCourseLeavesTheChecklistAndThePool() throws {
        let course: Course = try makeCourse(
            named: "removed",
            sharedFolders: ["Concepts", "Tasks"],
            gradedFolders: ["Tasks"],
            directories: ["Concepts", "Tasks", "Tasks/Unit 1"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)
        XCTAssertEqual(view.gradedFolderChoices, ["Concepts", "Tasks", "Unit 1"])

        // What Course Settings does when the teacher confirms the removal: the
        // list editor's own binding takes the name out of `shared_folders`,
        // and its `onRemove` excludes it and drops it from the pool. The
        // folder itself stays on disk, which is the whole difficulty — before
        // this change the walk handed it straight back.
        removeThroughTheListEditor("Tasks", scope: .shared, in: view)

        // Not offered back — and neither is anything inside it, because
        // nothing under a removed folder reaches the site either.
        XCTAssertEqual(view.gradedFolderChoices, ["Concepts"])
        XCTAssertEqual(course.configuration.gradedFolders, [])
    }

    // MARK: - What a removal does to the pool

    /// `contracts/shared-rules.json` → `gradedFolders.removingAFolder`, run
    /// through the list editor Course Settings builds for that list, so the
    /// order is the shipped one rather than a replay of it: the editor's
    /// binding takes the name out of its list, `onRemove` (`folderWasRemoved`)
    /// records the exclusion, and only then is the pool touched.
    ///
    /// Until issue #183 this runner replayed those three steps by hand, and a
    /// reorder or a dropped step inside `folderWasRemoved` left every case
    /// green. Now moving the pool above the exclusion, leaving either out, or
    /// calling `onRemove` before the list is written turns cases 3 and 4 red —
    /// the same pair the same mutations turn red on Windows.
    ///
    /// The order is the whole subject. Ask what the checklist offers BEFORE
    /// the exclusion is written and the removed folder is still there, so the
    /// pool gets frozen — which is what the mac did until 2026-09-09 and
    /// Windows until 2026-09-18, from a walk cached one `BuildForm` pass
    /// earlier (issue #142). Both platforms follow the rule now; on Windows
    /// the whole gesture is one Core method,
    /// `FolderRemoval.RemoveFolderFromCourse`.
    func testWhatARemovalDoesToTheMarksPoolMatchesTheContract() throws {
        let rule: [String: Any] = try GradedFolderChoicesTests.gradedFoldersSection()["removingAFolder"] as? [String: Any] ?? [:]
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(
            cases.count, 7,
            "The contract lost removal cases: \(cases.count) present, 7 expected at least."
        )

        var index: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let sharedFolders: [String] = try XCTUnwrap(testCase["sharedFolders"] as? [String])
            let perSectionFolders: [String] = try XCTUnwrap(testCase["perSectionFolders"] as? [String])
            let course: Course = try makeCourse(
                named: "removal\(index)",
                sharedFolders: sharedFolders,
                perSectionFolders: perSectionFolders,
                gradedFolders: testCase["graded"] as? [String],
                directories: try XCTUnwrap(testCase["directories"] as? [String])
            )
            index += 1
            let view: CourseSettingsView = CourseSettingsView(course: course)

            let removal: [String: Any] = try XCTUnwrap(testCase["remove"] as? [String: Any])
            let removed: String = try XCTUnwrap(removal["name"] as? String)
            let scope: FolderScope =
                (try XCTUnwrap(removal["scope"] as? String)) == "per_section" ? .perSection : .shared
            removeThroughTheListEditor(removed, scope: scope, in: view)

            if let expected = testCase["expectGraded"] as? [String] {
                XCTAssertEqual(course.configuration.gradedFolders, expected, name)
            } else {
                XCTAssertNil(
                    course.configuration.gradedFolders,
                    "\(name): the pool should have been left as it was, and it says "
                        + String(describing: course.configuration.gradedFolders)
                )
            }
        }
    }

    /// A removal through the list editor leaves its line on the trail (rule 5):
    /// one `.itemExcluded` line naming the folder, the list it left and the
    /// course. Pinned here because the contract runner above now drives the
    /// same path, and a line that went missing from it would otherwise be
    /// noticed only when a teacher's report came back without it.
    func testARemovalThroughTheListEditorLeavesItsLineOnTheTrail() throws {
        let course: Course = try makeCourse(
            named: "trail",
            sharedFolders: ["Concepts"],
            perSectionFolders: ["All Classes", "Labs"],
            directories: ["Concepts", "Labs"]
        )
        let view: CourseSettingsView = CourseSettingsView(course: course)

        removeThroughTheListEditor("Labs", scope: .perSection, in: view)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        var matchingLines: [String] = []
        for line in trail.components(separatedBy: "\n") {
            if line.hasSuffix("excluded per-section folder Labs in ICS3U") {
                matchingLines.append(line)
            }
        }
        XCTAssertEqual(matchingLines.count, 1, trail)
        XCTAssertEqual(course.configuration.perSectionFolders, ["All Classes"])
    }

    /// The still-offered question itself, asked the way the BUILD asks it.
    ///
    /// The contract's seventh case proves the rule end to end; this pins two
    /// properties of the comparison itself — that case is IGNORED and that a
    /// WHOLE name is matched — so an exact test or a substring test cannot be
    /// put back and stay green.
    ///
    /// **It does not pin WHICH case-insensitive fold**, and no test here does:
    /// the pairs that separate `lowercased()` from `caseInsensitiveCompare`
    /// and `localizedCaseInsensitiveCompare` are non-ASCII (`Straße`/`STRASSE`,
    /// `Σ`/`ς`) or need a Turkish-locale machine, and this rule deliberately
    /// promises nothing about either. The fold is held by the measured argument
    /// in `GradedFolderChoices.stillOffers` — read it before swapping one in,
    /// because a green run here is not permission.
    func testStillOfferedIgnoresCaseAndMatchesWholeNames() {
        XCTAssertTrue(
            GradedFolderChoices.stillOffers(["Concepts", "Portfolios", "tasks"], aFolderNamed: "Tasks")
        )
        XCTAssertTrue(GradedFolderChoices.stillOffers(["TASKS"], aFolderNamed: "tasks"))
        // A whole name, never a substring: `Homework Tasks` is a different
        // folder, and `_is_graded_path` compares whole segments too.
        XCTAssertFalse(GradedFolderChoices.stillOffers(["Homework Tasks"], aFolderNamed: "Tasks"))
        XCTAssertFalse(GradedFolderChoices.stillOffers([], aFolderNamed: "Tasks"))
    }

    // MARK: - The walk itself

    func testACourseFolderThatIsNotThereOffersOnlyWhatTheCourseDeclares() throws {
        let course: Course = try makeCourse(named: "declared-only", sharedFolders: ["Tasks"])
        let missing: URL = root.appendingPathComponent("not-there")

        XCTAssertEqual(GradedFolderChoices.nestedFolderNames(inCourseDirectory: missing), [])
        XCTAssertEqual(
            GradedFolderChoices.choices(for: course.configuration, courseDirectory: missing), ["Tasks"]
        )
    }

    func testFilesAreNotOfferedOnlyFolders() throws {
        let course: Course = try makeCourse(named: "files", directories: ["Tasks"])
        try Data("x".utf8).write(to: course.directoryURL.appendingPathComponent("Key Links.md"))
        try Data("x".utf8).write(
            to: course.directoryURL.appendingPathComponent("Tasks").appendingPathComponent("Quiz.md")
        )

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    func testSectionFoldersAreRecognisedByNameAndNumberAlone() {
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("section1"))
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("section12"))
        XCTAssertTrue(GradedFolderChoices.isSectionFolder("SECTION3"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("sections"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section1a"))
        // The digits are digits and nothing else: `Int("-1")` is not nil, so
        // the reading this replaced counted `section-1` as a section folder
        // and did not offer a teacher's own folder of that name.
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section-1"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("section 1"))
        XCTAssertFalse(GradedFolderChoices.isSectionFolder("Sectional Tasks"))
    }

    /// A folder marked hidden by the platform, rather than merely named with a
    /// dot. The contract asks for both; `.skipsHiddenFiles` is what covers the
    /// second, and a test is what keeps it there.
    func testAFolderHiddenByAttributeIsNotOffered() throws {
        let course: Course = try makeCourse(named: "hidden", directories: ["Tasks", "Bookkeeping"])
        var bookkeeping: URL = course.directoryURL.appendingPathComponent("Bookkeeping")
        var values: URLResourceValues = URLResourceValues()
        values.isHidden = true
        try bookkeeping.setResourceValues(values)

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    /// A symbolic link is neither offered nor walked into: what it points at is
    /// not part of this course, and following one is how a walk finds its way
    /// into a loop.
    func testASymbolicLinkIsNotFollowed() throws {
        let course: Course = try makeCourse(named: "linked", directories: ["Tasks"])
        let away: URL = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(
            at: away.appendingPathComponent("Linked Tasks"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: course.directoryURL.appendingPathComponent("Shortcut"), withDestinationURL: away
        )

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["Tasks"]
        )
    }

    /// A teacher's own lowercase `media` is theirs, and is offered: the skip
    /// list is matched exactly, case included, on both platforms.
    func testATeachersOwnLowercaseMediaFolderIsStillOffered() throws {
        let course: Course = try makeCourse(named: "case-sensitive", directories: ["media"])

        XCTAssertEqual(
            GradedFolderChoices.nestedFolderNames(inCourseDirectory: course.directoryURL), ["media"]
        )
    }

    // MARK: - The numbers both apps must share

    func testTheDepthCapIsTheOneTheContractNames() throws {
        let walk: [String: Any] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["walk"] as? [String: Any]
        )
        XCTAssertEqual(walk["maxDepth"] as? Int, GradedFolderChoices.maxDepth)
    }

    func testTheSkippedFoldersAreTheOnesTheContractNames() throws {
        let walk: [String: Any] = try XCTUnwrap(
            try GradedFolderChoicesTests.choicesRule()["walk"] as? [String: Any]
        )
        let named: [String] = try XCTUnwrap(walk["skipped"] as? [String])
        XCTAssertEqual(Set(named), GradedFolderChoices.skippedFolders)
    }
}
