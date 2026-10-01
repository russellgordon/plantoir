import XCTest
@testable import QuartzTeachers

/// Obsidian add-ons stay behind on EVERY route to a reference course (#255).
///
/// Runs `contracts/shared-rules.json` → `referenceCourses.obsidianAddOns`:
/// each case is a folder tree, and each is made into a reference course BOTH
/// ways a modern course can be — "Keep a Copy for Reference…" and "Import
/// Courses for Reference…" — because the two routes had drifted apart once
/// already and a case run through only one of them could drift again. The
/// older layouts run their own contract cases (`OlderLayoutImportTests`,
/// `QuartzCheckoutImportTests`); what they share with these is proven there
/// by the unreadable-add-on test, which each of the four routes has.
///
/// No sentence is retyped: the sheets' notes are compared against the
/// wording keys, and the trail's clause against `ObsidianAddOns.trailClause`
/// — except in the zero case, where the line must be EXACTLY what it was
/// before #255, and only a written-out line can say so.
@MainActor
final class ObsidianAddOnsTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    /// A destination working folder under a throwaway root, with the trail
    /// redirected there too. Nothing here touches the real home folder.
    func prepare() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("obsidian-add-ons-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        let root: URL = rootURL
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - The contract's cases

    /// The list the contract names is the list the code leaves behind.
    func testTheContractListIsTheCodesList() throws {
        let block: [String: Any] = try ObsidianAddOnsTests.rules()
        var named: [String] = []
        for entry in try XCTUnwrap(block["leftBehindInsideObsidian"] as? [[String: Any]]) {
            named.append(try XCTUnwrap(entry["path"] as? String))
            XCTAssertNotNil(entry["why"] as? String, "Every entry left behind says why.")
        }
        XCTAssertEqual(named, ObsidianAddOns.leftBehindInsideTheSettingsFolder)
        XCTAssertEqual(
            ObsidianAddOns.leftBehindFromTheCourse,
            [".obsidian/plugins", ".obsidian/community-plugins.json", ".obsidian/publish.json"]
        )
    }

    func testEveryContractCaseHoldsForKeepACopy() async throws {
        try await runEveryCase(throughKeepACopy: true)
    }

    func testEveryContractCaseHoldsForTheModernImport() async throws {
        try await runEveryCase(throughKeepACopy: false)
    }

    /// Builds each case, makes a reference course from it one way, and holds
    /// it to the case: what is absent, what is byte-identical, what is not a
    /// link, what was found, whether the sheet says so — and that the SOURCE,
    /// links' targets included, is exactly as it was.
    func runEveryCase(throughKeepACopy: Bool) async throws {
        let cases: [[String: Any]] = try XCTUnwrap(try ObsidianAddOnsTests.rules()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9, "The contract’s cases did not load.")
        let route: String = throughKeepACopy ? "Keep a Copy" : "import"

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case")
            try ObsidianAddOnsTests.build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)
            let courseURL: URL = caseURL.appendingPathComponent(try XCTUnwrap(testCase["course"] as? String))
            let before: [String: String] = ObsidianAddOnsTests.manifest(of: caseURL)

            let found: ObsidianAddOns.Found = ObsidianAddOns.found(inCourseAt: courseURL)
            let expected: [String: Any] = try XCTUnwrap(testCase["expectFound"] as? [String: Any])
            XCTAssertEqual(found.addOnNames, expected["addOnNames"] as? [String], "\(name): the add-ons found")
            XCTAssertEqual(found.addOnsFolderIsALink, expected["addOnsFolderIsALink"] as? Bool, "\(name)")
            XCTAssertEqual(found.settingsFolderIsALink, expected["settingsFolderIsALink"] as? Bool, "\(name)")
            XCTAssertEqual(found.publishSiteIsSet, expected["publishSiteIsSet"] as? Bool, "\(name)")
            let expectSaid: Bool = try XCTUnwrap(testCase["expectSaid"] as? Bool)

            let madeURL: URL
            if throughKeepACopy {
                let course: Course = Course(
                    code: courseURL.lastPathComponent,
                    directoryURL: courseURL,
                    configuration: try CourseConfiguration(
                        contentsOf: courseURL.appendingPathComponent("course_config.json")
                    )
                )
                let note: String? = KeepACopyForReferenceSheet.addOnsNote(course: course.displayCode, found: found)
                if expectSaid {
                    XCTAssertEqual(
                        note, ReferenceWording.keepACopyLeavesAddOnsBehind(course: course.displayCode),
                        "\(name): the Keep a Copy sheet says nothing about add-ons it leaves behind"
                    )
                } else {
                    XCTAssertNil(note, "\(name): the Keep a Copy sheet speaks of add-ons that are not there")
                }
                let made: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
                    of: course, named: course.code + "-2025", schoolYear: 2025,
                    coursesDirectoryURL: coursesDirectoryURL
                )
                madeURL = coursesDirectoryURL.appendingPathComponent(made.folderName)
            } else {
                let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
                    chosen: caseURL,
                    workingFolderURL: workingFolderURL,
                    leavingBehind: ReferenceImporter.leftBehindNames
                )
                guard case .found(let source) = outcome else {
                    XCTFail("\(name): the folder was refused: \(outcome)")
                    continue
                }
                let row: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first, name)
                XCTAssertNil(row.problem, "\(name): \(row.problem ?? "")")
                XCTAssertEqual(row.addOns, found, "\(name): the sheet's row read something else")
                let note: String? = ImportCoursesForReferenceSheet.addOnsNote(for: source.courses)
                if expectSaid {
                    XCTAssertEqual(note, ReferenceImportWording.addOnsAreLeftBehind, "\(name): the sheet is silent")
                } else {
                    XCTAssertNil(note, "\(name): the sheet speaks of add-ons that are not there")
                }
                let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                    [ReferenceImporter.Request(course: row, schoolYear: 2025)],
                    into: coursesDirectoryURL,
                    existingFolderNames: [],
                    alreadyShelved: [],
                    from: source.rootURL,
                    progress: { _ in }
                )
                guard case .imported(let made) = try XCTUnwrap(outcomes.first) else {
                    XCTFail("\(name): not imported: \(outcomes)")
                    continue
                }
                madeURL = coursesDirectoryURL.appendingPathComponent(made.folderName)
            }

            for path in try XCTUnwrap(testCase["expectAbsent"] as? [String]) {
                XCTAssertNil(
                    ObsidianAddOnsTests.kind(of: madeURL.appendingPathComponent(path)),
                    "\(name) (\(route)): \(path) came across"
                )
            }
            for path in try XCTUnwrap(testCase["expectUnchanged"] as? [String]) {
                let copied: Data? = try? Data(contentsOf: madeURL.appendingPathComponent(path))
                let original: Data? = try? Data(contentsOf: courseURL.appendingPathComponent(path))
                XCTAssertNotNil(copied, "\(name) (\(route)): \(path) did not come across")
                XCTAssertEqual(copied, original, "\(name) (\(route)): \(path) is not the same bytes")
            }
            if let notLinks = testCase["expectNotALink"] as? [String] {
                for path in notLinks {
                    XCTAssertNotEqual(
                        ObsidianAddOnsTests.kind(of: madeURL.appendingPathComponent(path)), S_IFLNK,
                        "\(name) (\(route)): \(path) came across as a link to the live settings"
                    )
                }
            }
            // Nothing anywhere in the made course is a link into an add-on.
            for path in ObsidianAddOnsTests.manifest(of: madeURL).keys {
                XCTAssertFalse(path.hasPrefix(".obsidian/plugins"), "\(name) (\(route)): \(path) came across")
            }
            XCTAssertEqual(
                ObsidianAddOnsTests.manifest(of: caseURL), before,
                "\(name) (\(route)): the source changed — through a link, or otherwise"
            )

            // The trail names what was left behind, and only when anything was.
            let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
            if found.isEmpty {
                XCTAssertFalse(trail.contains("Obsidian"), "\(name) (\(route)): \(trail)")
            } else {
                XCTAssertTrue(
                    trail.contains(ObsidianAddOns.trailClause(for: found)),
                    "\(name) (\(route)): the trail does not say what was left behind: \(trail)"
                )
            }
        }
    }

    // MARK: - What the contract cannot carry

    /// Skipped, not walked and filtered: a folder inside an add-on that
    /// nobody can read does not refuse the course. The older layouts prove
    /// the same in their own suites.
    func testAnUnreadableFolderInsideAnAddOnDoesNotRefuseTheCourse() async throws {
        for throughKeepACopy in [true, false] {
            try prepare()
            let courseURL: URL = try makeCourse(code: "ICS3U", inFolder: rootURL.appendingPathComponent("old/courses"))
            let shut: URL = courseURL.appendingPathComponent(".obsidian/plugins/digitalgarden/cache")
            try FileManager.default.createDirectory(at: shut, withIntermediateDirectories: true)
            try Data("cached".utf8).write(to: shut.appendingPathComponent("blob"))
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: shut.path)
            addTeardownBlock {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shut.path)
            }

            if throughKeepACopy {
                let course: Course = try ObsidianAddOnsTests.course(at: courseURL)
                XCTAssertNoThrow(
                    try ReferenceCopier.keepACopy(
                        of: course, named: "ICS3U-2025", schoolYear: 2025, coursesDirectoryURL: coursesDirectoryURL
                    ),
                    "Keep a Copy was refused for a folder inside an add-on it never meant to copy."
                )
            } else {
                let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
                    chosen: rootURL.appendingPathComponent("old"),
                    workingFolderURL: workingFolderURL,
                    leavingBehind: ReferenceImporter.leftBehindNames
                )
                guard case .found(let source) = outcome else {
                    return XCTFail("The old folder was refused: \(outcome)")
                }
                let row: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
                XCTAssertNil(row.problem, "The sheet refuses the course over a folder inside an add-on.")
                let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                    [ReferenceImporter.Request(course: row, schoolYear: 2025)],
                    into: coursesDirectoryURL, existingFolderNames: [], alreadyShelved: [],
                    from: source.rootURL, progress: { _ in }
                )
                guard case .imported = try XCTUnwrap(outcomes.first) else {
                    return XCTFail("The import was refused over a folder inside an add-on: \(outcomes)")
                }
            }
        }
    }

    /// The size a teacher reads is the size that will be copied: an add-on's
    /// megabyte is not in it.
    func testTheSheetNumbersLeaveTheAddOnsOut() throws {
        try prepare()
        let courseURL: URL = try makeCourse(code: "ICS3U", inFolder: rootURL.appendingPathComponent("old/courses"))
        let outcomeWithout: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
            chosen: rootURL.appendingPathComponent("old"),
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames
        )
        guard case .found(let without) = outcomeWithout else {
            return XCTFail("The old folder was refused.")
        }
        let rowWithout: ReferenceImportSource.FoundCourse = try XCTUnwrap(without.courses.first)

        try Data(count: 1_048_576).write(
            to: courseURL.appendingPathComponent(".obsidian/plugins/digitalgarden/big.bin")
        )
        let outcomeWith: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
            chosen: rootURL.appendingPathComponent("old"),
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames
        )
        guard case .found(let with) = outcomeWith else {
            return XCTFail("The old folder was refused.")
        }
        let rowWith: ReferenceImportSource.FoundCourse = try XCTUnwrap(with.courses.first)
        XCTAssertEqual(rowWith.byteCount, rowWithout.byteCount, "An add-on's bytes are counted as coming across.")
        XCTAssertEqual(rowWith.fileCount, rowWithout.fileCount)
        XCTAssertEqual(rowWith.addOns.addOnNames, ["digitalgarden"])
    }

    /// Which sentence the import sheet says. The modern one wins when both
    /// kinds are in the list, because the older one beside a modern course
    /// with an add-on reads as if that course's add-ons came.
    func testTheImportSheetsNoteIsChosenByWhatTheCoursesHold() {
        let none: ReferenceImportSource.FoundCourse = ObsidianAddOnsTests.row("ICS4U", addOns: [])
        let some: ReferenceImportSource.FoundCourse = ObsidianAddOnsTests.row("ICS3U", addOns: ["digitalgarden"])
        let older: ReferenceImportSource.FoundCourse = ObsidianAddOnsTests.olderRow("ICS3U-S1-2023-24")

        XCTAssertNil(ImportCoursesForReferenceSheet.addOnsNote(for: [none]))
        XCTAssertNil(ImportCoursesForReferenceSheet.addOnsNote(for: []))
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.addOnsNote(for: [none, some]), ReferenceImportWording.addOnsAreLeftBehind
        )
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.addOnsNote(for: [older]), ReferenceImportWording.olderLayoutAddOnsAreLeftBehind,
            "An older class says what it always said."
        )
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.addOnsNote(for: [older, none]),
            ReferenceImportWording.olderLayoutAddOnsAreLeftBehind
        )
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.addOnsNote(for: [older, some]), ReferenceImportWording.addOnsAreLeftBehind,
            "Both kinds: the sentence true of every route, not the one that names only older class folders."
        )
    }

    // MARK: - The trail

    /// A course with NO add-ons leaves exactly the line it left before #255
    /// — on both modern routes. Written out, because a comparison with the
    /// function that makes the line would change along with it.
    func testTheTrailLineForACourseWithoutAddOnsIsWhatItWas() async throws {
        try prepare()
        let courseURL: URL = try makeCourse(
            code: "ICS4U", inFolder: rootURL.appendingPathComponent("Class Websites/courses"), addOns: []
        )
        _ = try ReferenceCopier.keepACopy(
            of: try ObsidianAddOnsTests.course(at: courseURL), named: "ICS4U-2024", schoolYear: 2024,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
            chosen: rootURL.appendingPathComponent("Class Websites"),
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames
        )
        guard case .found(let source) = outcome else {
            return XCTFail("The old folder was refused.")
        }
        _ = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: try XCTUnwrap(source.courses.first), schoolYear: 2025)],
            into: coursesDirectoryURL, existingFolderNames: ["ICS4U-2024"], alreadyShelved: [],
            from: source.rootURL, progress: { _ in }
        )

        let lines: [String] = ActivityTrail.store.activityText(includingPrompts: true)
            .components(separatedBy: "\n")
        let kept: String = try XCTUnwrap(ObsidianAddOnsTests.line(in: lines, containing: "kept a copy of ICS4U"))
        XCTAssertTrue(
            kept.hasSuffix("kept a copy of ICS4U for reference as ICS4U-2024 — shown as ICS4U, 2024–25, 1 section"),
            "The Keep a Copy line changed for a course with no add-ons: \(kept)"
        )
        let imported: String = try XCTUnwrap(ObsidianAddOnsTests.line(in: lines, containing: "imported ICS4U"))
        XCTAssertTrue(
            imported.hasSuffix("imported ICS4U for reference from Class Websites as ICS4U-2025 — 2025–26, 1 section"),
            "The import line changed for a course with no add-ons: \(imported)"
        )
    }

    /// A course WITH add-ons: both lines name them, by folder name.
    func testTheTrailNamesTheAddOnsLeftBehind() async throws {
        try prepare()
        let courseURL: URL = try makeCourse(
            code: "ICS3U", inFolder: rootURL.appendingPathComponent("Class Websites/courses"),
            addOns: ["obsidian-git", "digitalgarden"]
        )
        _ = try ReferenceCopier.keepACopy(
            of: try ObsidianAddOnsTests.course(at: courseURL), named: "ICS3U-2024", schoolYear: 2024,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
            chosen: rootURL.appendingPathComponent("Class Websites"),
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames
        )
        guard case .found(let source) = outcome else {
            return XCTFail("The old folder was refused.")
        }
        _ = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: try XCTUnwrap(source.courses.first), schoolYear: 2025)],
            into: coursesDirectoryURL, existingFolderNames: ["ICS3U-2024"], alreadyShelved: [],
            from: source.rootURL, progress: { _ in }
        )

        let lines: [String] = ActivityTrail.store.activityText(includingPrompts: true)
            .components(separatedBy: "\n")
        let clause: String = "; 2 Obsidian add-ons left behind (digitalgarden, obsidian-git)"
        let kept: String = try XCTUnwrap(ObsidianAddOnsTests.line(in: lines, containing: "kept a copy of ICS3U"))
        XCTAssertTrue(kept.hasSuffix(clause), kept)
        let imported: String = try XCTUnwrap(ObsidianAddOnsTests.line(in: lines, containing: "imported ICS3U"))
        XCTAssertTrue(imported.hasSuffix(clause), imported)
    }

    /// The clause for every shape, one at a time, and nothing for nothing.
    func testTheTrailClauseSaysEachThingOnce() {
        XCTAssertEqual(ObsidianAddOns.trailClause(for: ObsidianAddOns.Found()), "")
        var one: ObsidianAddOns.Found = ObsidianAddOns.Found()
        one.addOnNames = ["digitalgarden"]
        XCTAssertEqual(ObsidianAddOns.trailClause(for: one), "; 1 Obsidian add-on left behind (digitalgarden)")
        var linked: ObsidianAddOns.Found = ObsidianAddOns.Found()
        linked.settingsFolderIsALink = true
        linked.publishSiteIsSet = true
        XCTAssertEqual(
            ObsidianAddOns.trailClause(for: linked),
            "; Obsidian's settings folder was a link and was left behind"
            + "; Obsidian Publish's site setting was left behind"
        )
    }

    // MARK: - The sentences

    func testTheSentencesAreTheContractsSentences() throws {
        let all: [String: Any] = try ObsidianAddOnsTests.allRules()
        let reference: [String: Any] = try XCTUnwrap(all["referenceCourses"] as? [String: Any])
        let referenceWording: [String: Any] = try XCTUnwrap(reference["wording"] as? [String: Any])
        XCTAssertEqual(
            ReferenceWording.keepACopyLeavesAddOnsBehind(course: "{course}"),
            referenceWording["keepACopyLeavesAddOnsBehind"] as? String
        )
        let importing: [String: Any] = try XCTUnwrap(reference["importing"] as? [String: Any])
        let importWording: [String: Any] = try XCTUnwrap(importing["wording"] as? [String: Any])
        XCTAssertEqual(ReferenceImportWording.addOnsAreLeftBehind, importWording["addOnsAreLeftBehind"] as? String)

        // Rule 1: plain words. "Add-on" is the word already shipped.
        let sentences: [String] = [
            ReferenceWording.keepACopyLeavesAddOnsBehind(course: "ICS3U"), ReferenceImportWording.addOnsAreLeftBehind,
        ]
        for sentence in sentences {
            for word in ["plugin", "vault", "token", "link", "json", "folder", "script", "cannot"] {
                XCTAssertFalse(sentence.lowercased().contains(word), "“\(word)” in: \(sentence)")
            }
        }
    }

    // MARK: - Helpers

    /// A modern course with one section, a plain `.obsidian`, and the named
    /// add-ons installed (each with a credential-shaped setting).
    @discardableResult
    func makeCourse(code: String, inFolder coursesURL: URL, addOns: [String] = ["digitalgarden"]) throws -> URL {
        let courseURL: URL = coursesURL.appendingPathComponent(code)
        let obsidian: URL = courseURL.appendingPathComponent(".obsidian")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: obsidian, withIntermediateDirectories: true)
        try Data("# lesson\n".utf8).write(to: courseURL.appendingPathComponent("section1/index.md"))
        try Data("{}".utf8).write(to: obsidian.appendingPathComponent("appearance.json"))
        try JSONSerialization.data(withJSONObject: [
            "course_code": code, "section_numbers": [1], "num_sections": 1,
        ]).write(to: courseURL.appendingPathComponent("course_config.json"))
        for addOn in addOns {
            let folder: URL = obsidian.appendingPathComponent("plugins").appendingPathComponent(addOn)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{\"githubToken\": \"not-a-real-credential\"}".utf8)
                .write(to: folder.appendingPathComponent("data.json"))
        }
        return courseURL
    }

    private static func course(at courseURL: URL) throws -> Course {
        return Course(
            code: courseURL.lastPathComponent,
            directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        )
    }

    private static func line(in lines: [String], containing text: String) -> String? {
        for line in lines where line.contains(text) {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func row(_ code: String, addOns: [String]) -> ReferenceImportSource.FoundCourse {
        var found: ObsidianAddOns.Found = ObsidianAddOns.Found()
        found.addOnNames = addOns
        return ReferenceImportSource.FoundCourse(
            folderName: code, courseCode: code, courseName: code, sectionNumbers: [1],
            pageCount: 1, fileCount: 1, byteCount: 1, problem: nil, suggestedSchoolYear: 2025,
            directoryURL: URL(fileURLWithPath: "/nowhere").appendingPathComponent(code),
            addOns: found
        )
    }

    private static func olderRow(_ folderName: String) -> ReferenceImportSource.FoundCourse {
        let names: OlderCourseLayout.NameFacts = OlderCourseLayout.nameFacts(of: folderName)
        return ReferenceImportSource.FoundCourse(
            folderName: folderName, courseCode: names.code ?? folderName, courseName: folderName,
            sectionNumbers: [1], pageCount: 1, fileCount: 1, byteCount: 1, problem: nil,
            suggestedSchoolYear: 2023,
            directoryURL: URL(fileURLWithPath: "/nowhere").appendingPathComponent(folderName),
            olderLayout: OlderCourseLayout.Facts(
                classFolderName: folderName,
                names: names,
                shared: OlderCourseLayout.SharedContent(
                    howFound: .notNeeded, folderURL: nil, foundNames: [], missingNames: [], linkCount: 0
                ),
                chosenWarning: nil
            )
        )
    }

    private static func allRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private static func rules() throws -> [String: Any] {
        let reference: [String: Any] = try XCTUnwrap(try ObsidianAddOnsTests.allRules()["referenceCourses"] as? [String: Any])
        return try XCTUnwrap(reference["obsidianAddOns"] as? [String: Any], "No referenceCourses.obsidianAddOns")
    }

    /// What kind of thing is at a path, without following a link.
    private static func kind(of url: URL) -> mode_t? {
        var status: stat = stat()
        if lstat(url.path, &status) != 0 {
            return nil
        }
        return status.st_mode & S_IFMT
    }

    /// Builds a contract tree: see `obsidianAddOns.treeEntries`.
    private static func build(tree: [Any], at folderURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var links: [[String: Any]] = []
        for entry in tree {
            if let path = entry as? String {
                let fileURL: URL = folderURL.appendingPathComponent(path)
                if path.hasSuffix("/") {
                    try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true)
                    continue
                }
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileURL.lastPathComponent == "course_config.json" {
                    let code: String = fileURL.deletingLastPathComponent().lastPathComponent
                    try JSONSerialization.data(withJSONObject: [
                        "course_code": code, "section_numbers": [1],
                    ]).write(to: fileURL)
                    continue
                }
                try Data("something".utf8).write(to: fileURL)
                continue
            }
            guard let described = entry as? [String: Any] else {
                continue
            }
            if described["link"] != nil {
                links.append(described)
                continue
            }
            let path: String = try XCTUnwrap(described["file"] as? String)
            let fileURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(((described["text"] as? String) ?? "something").utf8).write(to: fileURL)
        }
        // After every file, so a link has something to lead to.
        for described in links {
            let path: String = try XCTUnwrap(described["link"] as? String)
            let linkURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let to: String = try XCTUnwrap(described["to"] as? String)
            try fileManager.createSymbolicLink(
                atPath: linkURL.path, withDestinationPath: folderURL.appendingPathComponent(to).path
            )
        }
    }

    /// Every entry under a folder — files, folders and links, never followed
    /// — with its mode, size, modification time, bytes and link text.
    private static func manifest(of folderURL: URL) -> [String: String] {
        var result: [String: String] = [:]
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: folderURL, leavingBehind: [])
        for item in survey.items {
            let url: URL = ReferenceTreeCopier.url(named: item.relativePath, inFolderAt: folderURL)
            var status: stat = stat()
            _ = lstat(url.path, &status)
            var line: String = "mode \(status.st_mode) size \(status.st_size) "
                + "time \(status.st_mtimespec.tv_sec).\(status.st_mtimespec.tv_nsec)"
            if item.isSymbolicLink {
                line += " -> " + ((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?")
            } else if !item.isDirectory {
                line += " " + ((try? Data(contentsOf: url))?.base64EncodedString() ?? "unreadable")
            }
            result[item.text] = line
        }
        return result
    }
}
