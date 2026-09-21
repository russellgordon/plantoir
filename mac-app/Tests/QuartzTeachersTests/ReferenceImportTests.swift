import XCTest
@testable import QuartzTeachers

/// "Import Courses for Reference…" — the act, without the sheet.
///
/// Runs `contracts/shared-rules.json` → `referenceCourses.importing`: which
/// folder shapes are accepted, what is left behind, the folder name produced,
/// the school year proposed, and what happens when one course of several
/// cannot be imported. Every case is DATA rather than a literal here, so
/// Windows runs the identical case when it implements its own half, and no
/// sentence is retyped — they are named.
@MainActor
final class ReferenceImportTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")
    var oldFolderURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    /// A destination working folder and an old folder to import from, both
    /// under a throwaway root. Nothing here touches the real home folder: no
    /// Application Support, no launch agents, no teacher-facing log.
    func prepare() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-import-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        oldFolderURL = rootURL.appendingPathComponent("Class Websites")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(
            folderURL: rootURL.appendingPathComponent("trail")
        )
        let root: URL = rootURL
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
                // Unlock first: `removeItem` refuses a locked tree, which is
                // the whole reason the product unlocks before it removes.
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// One course in the OLD folder, with everything a real one has that the
    /// import must or must not take.
    @discardableResult
    func makeOldCourse(
        code: String,
        sections: [Int] = [1, 2],
        pageDates: [Date] = [],
        inCoursesFolder coursesFolderURL: URL? = nil
    ) throws -> URL {
        let fileManager: FileManager = FileManager.default
        let coursesURL: URL = coursesFolderURL ?? oldFolderURL.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent(code)
        try fileManager.createDirectory(at: courseURL, withIntermediateDirectories: true)

        for sectionNumber in sections {
            let sectionURL: URL = courseURL.appendingPathComponent("section\(sectionNumber)")
            try fileManager.createDirectory(at: sectionURL, withIntermediateDirectories: true)
            // An OLD page, written in the spelling an older Plantoir used.
            // Never rewritten on the way in: a reference course is a faithful
            // record of what students actually saw.
            try Data("---\ndraft: true\n---\n# private\n".utf8)
                .write(to: sectionURL.appendingPathComponent("Private Notes.md"))
            try Data("---\ndraft: false\n---\n# lesson\n".utf8)
                .write(to: sectionURL.appendingPathComponent("index.md"))
        }

        let mediaURL: URL = courseURL.appendingPathComponent("Media")
        try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try Data("picture".utf8).write(to: mediaURL.appendingPathComponent("diagram.png"))

        // Last year's REAL class sites.
        let markers: URL = courseURL.appendingPathComponent(".netlify_sites")
        try fileManager.createDirectory(at: markers, withIntermediateDirectories: true)
        for sectionNumber in sections {
            try Data("{\"site_id\": \"last-years-real-site\"}".utf8)
                .write(to: markers.appendingPathComponent("section\(sectionNumber).json"))
        }

        // The teacher's own Obsidian settings, which DO come across.
        let obsidian: URL = courseURL.appendingPathComponent(".obsidian")
        try fileManager.createDirectory(at: obsidian, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: obsidian.appendingPathComponent("workspace.json"))

        // Last year's built website, as an old folder really holds it: a REAL
        // directory, not a symlink.
        let built: URL = courseURL.appendingPathComponent(".merged_output")
        try fileManager.createDirectory(
            at: built.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try Data("last year's whole built site".utf8)
            .write(to: built.appendingPathComponent("section1").appendingPathComponent("index.html"))

        // A lease naming a process on a machine that is not this one.
        let leases: URL = courseURL.appendingPathComponent(".internal").appendingPathComponent("activity")
        try fileManager.createDirectory(at: leases, withIntermediateDirectories: true)
        try Data("1234".utf8).write(to: leases.appendingPathComponent("\(code).preview.1234.lease"))

        // Everything else the contract says is left behind.
        try Data("{\"course_code\": \"\(code)\"}".utf8)
            .write(to: courseURL.appendingPathComponent("course_config.backup.json"))
        try Data("{\"course_code\": \"\(code)\"}".utf8)
            .write(to: courseURL.appendingPathComponent("course_config copy.json"))
        try Data("finder".utf8).write(to: courseURL.appendingPathComponent(".DS_Store"))

        let values: [String: Any] = [
            "course_code": code,
            "course_name": "Last year's \(code)",
            "section_numbers": sections,
            "num_sections": sections.count,
            "custom_domains": ["sections": ["section1": "\(code.lowercased()).example.org"]],
            "additional_deploy_targets": [["type": "local_folder", "path": "/tmp/redundant"]],
        ]
        try JSONSerialization.data(withJSONObject: values)
            .write(to: courseURL.appendingPathComponent("course_config.json"))

        // Pages dated on purpose, for the school-year proposal.
        var index: Int = 0
        for pageDate in pageDates {
            index += 1
            let pageURL: URL = courseURL.appendingPathComponent("Note \(index).md")
            try Data("# note\n".utf8).write(to: pageURL)
            try fileManager.setAttributes(
                [FileAttributeKey.modificationDate: pageDate], ofItemAtPath: pageURL.path
            )
        }

        return courseURL
    }

    /// The source, read the way the sheet reads it.
    func read(_ chosenURL: URL) -> ReferenceImportSource.Outcome {
        return ReferenceImportSource.resolve(
            chosen: chosenURL,
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames
        )
    }

    /// Imports whatever was found, with the years asked for.
    func importEverything(
        from source: ReferenceImportSource,
        years: [String: Int?] = [:],
        alreadyShelved: [ReferenceCourseRule.Shelved] = []
    ) async -> [ReferenceImporter.Outcome] {
        var requests: [ReferenceImporter.Request] = []
        for course in source.courses {
            var year: Int? = 2025
            if let chosen = years[course.folderName] {
                year = chosen
            }
            requests.append(ReferenceImporter.Request(course: course, schoolYear: year))
        }
        return await ReferenceImporter.importCourses(
            requests,
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: alreadyShelved,
            from: source.rootURL,
            progress: { _ in }
        )
    }

    // MARK: - Which folders are accepted

    /// Every shape the contract says is accepted, and every one it refuses.
    func testTheFolderShapesAreTheContractsShapes() throws {
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let accepted: [String: Any] = try XCTUnwrap(block["foldersAccepted"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(accepted["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 4, "The contract's cases did not load.")

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let folderURL: URL = rootURL.appendingPathComponent("case-\(UUID().uuidString)")
            try ReferenceImportTests.build(
                tree: try XCTUnwrap(testCase["tree"] as? [String]), at: folderURL
            )

            let chosenPath: String = try XCTUnwrap(testCase["choose"] as? String)
            var chosenURL: URL = folderURL
            if chosenPath != "." {
                chosenURL = folderURL.appendingPathComponent(chosenPath)
            }

            // Which folder this window has open — the thing two of the
            // refusals are about.
            var openFolderURL: URL = workingFolderURL
            if testCase["isTheFolderAlreadyOpen"] as? Bool == true {
                openFolderURL = folderURL
            }
            if testCase["openFolderIsTheRoot"] as? Bool == true {
                openFolderURL = folderURL
            }
            if let child = testCase["openFolderIsAChildNamed"] as? String {
                openFolderURL = folderURL.appendingPathComponent(child)
            }

            let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
                chosen: chosenURL,
                workingFolderURL: openFolderURL,
                leavingBehind: ReferenceImporter.leftBehindNames
            )

            let expectation: String = try XCTUnwrap(testCase["expect"] as? String)
            switch outcome {
            case .found(let found):
                XCTAssertEqual(expectation, "accepted", "\(name): accepted, and the contract refuses it.")
                var codes: [String] = []
                for course in found.courses {
                    codes.append(course.courseCode)
                }
                XCTAssertEqual(
                    codes, try XCTUnwrap(testCase["expectCourses"] as? [String]),
                    "\(name): the courses found"
                )
                var ticked: [String] = Array(found.tickedWhenOpened)
                ticked.sort()
                var wanted: [String] = try XCTUnwrap(testCase["expectTicked"] as? [String])
                wanted.sort()
                XCTAssertEqual(ticked, wanted, "\(name): what is ticked when the sheet opens")
            case .refused(let refusal):
                XCTAssertEqual(expectation, "refused", "\(name): refused, and the contract accepts it.")
                XCTAssertEqual(
                    ReferenceImportTests.name(of: refusal),
                    testCase["refusal"] as? String,
                    "\(name): the refusal"
                )
            }
        }
    }

    /// A course whose settings cannot be read is not offered at all — copying
    /// it would make a reference course of nothing.
    func testACourseWithUnreadableSettingsIsShownAndCannotBeTicked() throws {
        try prepare()
        try makeOldCourse(code: "ICS3U")
        let broken: URL = oldFolderURL.appendingPathComponent("courses").appendingPathComponent("BROKE")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{ this is not json".utf8)
            .write(to: broken.appendingPathComponent("course_config.json"))

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        XCTAssertEqual(source.courses.count, 2, "A broken course is SHOWN, not hidden.")
        var unreadable: ReferenceImportSource.FoundCourse?
        for course in source.courses where course.folderName == "BROKE" {
            unreadable = course
        }
        XCTAssertEqual(
            unreadable?.problem, ReferenceImportWording.settingsCouldNotBeRead,
            "The row says why it cannot come across."
        )
        XCTAssertFalse(
            source.tickedWhenOpened.contains("BROKE"),
            "A course that cannot come across must not arrive ticked."
        )
        XCTAssertTrue(source.tickedWhenOpened.contains("ICS3U"))
    }

    // MARK: - What is left behind

    func testEveryNameTheContractLeavesBehindIsLeftBehind() async throws {
        try prepare()
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let leftBehind: [String: Any] = try XCTUnwrap(block["leftBehind"] as? [String: Any])
        let names: [[String: Any]] = try XCTUnwrap(leftBehind["names"] as? [[String: Any]])

        let courseURL: URL = try makeOldCourse(code: "ICS3U", sections: [1])
        // One file of each name the contract lists, at the top of the course
        // and inside a folder, so a rule that only looks at the top level
        // fails here.
        for entry in names {
            let name: String = try XCTUnwrap(entry["name"] as? String)
            XCTAssertNotNil(entry["why"] as? String, "\(name) is left behind for a reason; say it.")
            try? Data("left behind".utf8).write(to: courseURL.appendingPathComponent(name))
            try? Data("left behind".utf8).write(
                to: courseURL.appendingPathComponent("section1").appendingPathComponent(name)
            )
        }

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let outcomes: [ReferenceImporter.Outcome] = await importEverything(from: source)
        XCTAssertEqual(outcomes.count, 1)

        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        for entry in names {
            let name: String = try XCTUnwrap(entry["name"] as? String)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: copyURL.appendingPathComponent(name).path),
                "\(name) came across at the top of the course."
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: copyURL.appendingPathComponent("section1")
                        .appendingPathComponent(name).path
                ),
                "\(name) came across inside a folder."
            )
        }

        // And the one that costs real time: nothing inside last year's built
        // website came across either, so it was not walked.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: copyURL.appendingPathComponent(".merged_output").path
            )
        )
        // What the contract says IS kept.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: copyURL.appendingPathComponent(".obsidian")
                .appendingPathComponent("workspace.json").path
        ))
        // And the leases, which are removed after the copy rather than
        // skipped during it.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: copyURL.appendingPathComponent(".internal")
                .appendingPathComponent("activity").path
        ))
    }

    /// A `.merged_output` that is a SYMLINK is not followed either — today's
    /// working folders keep the built site outside the course altogether.
    func testASymlinkedBuildOutputIsNeverFollowed() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS4U", sections: [1])
        try FileManager.default.removeItem(at: courseURL.appendingPathComponent(".merged_output"))
        let builds: URL = rootURL.appendingPathComponent("builds")
        try FileManager.default.createDirectory(at: builds, withIntermediateDirectories: true)
        try Data("a whole built site".utf8).write(to: builds.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"), withDestinationURL: builds
        )

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        _ = await importEverything(from: source)

        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS4U-2025")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: copyURL.appendingPathComponent(".merged_output").path
        ))
    }

    // MARK: - The folder name and the school year

    func testTheFolderNameIsTheContractsFolderName() throws {
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let rules: [String: Any] = try XCTUnwrap(block["folderNameProduced"] as? [String: Any])
        for testCase in try XCTUnwrap(rules["cases"] as? [[String: Any]]) {
            let code: String = try XCTUnwrap(testCase["code"] as? String)
            let year: Int? = testCase["schoolYear"] as? Int
            let existing: [String] = try XCTUnwrap(testCase["existing"] as? [String])
            XCTAssertEqual(
                ReferenceCourseRule.proposedFolderName(
                    forCode: code, schoolYear: year, existingFolderNames: existing
                ),
                testCase["expect"] as? String,
                "\(code) under \(String(describing: year))"
            )
        }
    }

    func testTheSchoolYearProposedIsTheContractsProposal() throws {
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let rules: [String: Any] = try XCTUnwrap(block["schoolYearProposed"] as? [String: Any])
        for testCase in try XCTUnwrap(rules["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let pageYears: [Int] = try XCTUnwrap(testCase["pageYears"] as? [Int])
            let day: CalendarDay = try XCTUnwrap(
                CalendarDay(text: try XCTUnwrap(testCase["today"] as? String))
            )
            XCTAssertEqual(
                ReferenceImportSource.suggestedSchoolYear(fromPagesChangedIn: pageYears, on: day),
                testCase["expect"] as? Int,
                name
            )
        }
    }

    /// The proposal read off real page dates rather than from a list of
    /// years, which is the half the contract cases cannot reach.
    func testTheProposalIsReadOffThePagesThemselves() throws {
        try prepare()
        let taughtIn2024: Date = ReferenceImportTests.moment(year: 2024, month: 11, day: 3)
        let onePageTouchedLater: Date = ReferenceImportTests.moment(year: 2026, month: 9, day: 11)
        // Five pages from the year it was taught, one touched last week — and
        // the two pages `makeOldCourse` writes itself, which carry today's
        // date, so the "newest page" rule would answer this year.
        try makeOldCourse(
            code: "ICS3U",
            sections: [1],
            pageDates: [
                taughtIn2024, taughtIn2024, taughtIn2024, taughtIn2024, taughtIn2024,
                onePageTouchedLater,
            ]
        )
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        // The pages written by `makeOldCourse` itself carry today's date, so
        // this asserts on the dated ones being the majority — which is the
        // shape the rule is for.
        XCTAssertEqual(
            source.courses.first?.suggestedSchoolYear, 2024,
            "One page touched last week must not drag the whole course into this school year."
        )
    }

    // MARK: - What an imported course IS

    func testAnImportedCourseIsAFrozenReferenceCourseShowingItsRealCode() async throws {
        try prepare()
        try makeOldCourse(code: "ICS4U", sections: [1, 2])
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }

        let outcomes: [ReferenceImporter.Outcome] = await importEverything(from: source)
        guard case .imported(let made) = try XCTUnwrap(outcomes.first) else {
            return XCTFail("ICS4U was not imported: \(outcomes)")
        }
        XCTAssertEqual(made.folderName, "ICS4U-2025")
        XCTAssertEqual(made.displayCode, "ICS4U", "A teacher reads the real code, never the folder.")
        XCTAssertEqual(made.schoolYear, 2025)
        XCTAssertEqual(made.sectionCount, 2)

        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS4U-2025")
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: copyURL.appendingPathComponent("course_config.json")
        )
        XCTAssertTrue(configuration.keptForReference)
        XCTAssertEqual(configuration.referenceSchoolYear, 2025)
        XCTAssertEqual(configuration.courseCode, "ICS4U", "course_code is left exactly as it was.")

        // Neutralised: an OLDER Plantoir, which has never heard of the
        // marker, refuses this too.
        XCTAssertNotNil(
            CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath)
        )
        XCTAssertNil(configuration.values["custom_domains"])

        // Cut loose from last year's real sites.
        let markers: URL = copyURL.appendingPathComponent(".netlify_sites")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: markers.appendingPathComponent("section1.json").path
        ))
        let kept: [String] = try FileManager.default.contentsOfDirectory(atPath: markers.path)
        var renamedAside: Int = 0
        for name in kept where name.contains(".previous-") {
            renamedAside += 1
        }
        XCTAssertEqual(renamedAside, 2, "Renamed aside, never deleted: the site id is still there.")

        // Frozen.
        let page: URL = copyURL.appendingPathComponent("section1")
            .appendingPathComponent("Private Notes.md")
        XCTAssertTrue(ReferenceLock.isLocked(page))
        XCTAssertFalse(
            ReferenceLock.isLocked(copyURL.appendingPathComponent("course_config.json")),
            "The settings stay writable: the school year can be changed later."
        )

        // The pages are a faithful record: the frontmatter is NOT rewritten.
        let contents: String = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(contents.contains("draft: true"))

        // And the trail says where it came from.
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("imported ICS4U for reference from Class Websites"),
            "The trail line does not name the folder it was read from: \(trail)"
        )
    }

    /// The source is the teacher's only copy of last year, and an import
    /// reads it and nothing else.
    func testTheSourceIsNotTouched() async throws {
        try prepare()
        try makeOldCourse(code: "ICS3U", sections: [1, 2])
        let before: [String: String] = try ReferenceImportTests.manifest(of: oldFolderURL)

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        _ = await importEverything(from: source)

        let after: [String: String] = try ReferenceImportTests.manifest(of: oldFolderURL)
        XCTAssertEqual(before, after, "The folder the courses were read from changed.")
    }

    // MARK: - When one course cannot come across

    func testOneCourseFailingDoesNotStopTheRest() async throws {
        try prepare()
        try makeOldCourse(code: "ICS3U", sections: [1])
        try makeOldCourse(code: "ICS4U", sections: [1])
        try makeOldCourse(code: "MPM2D", sections: [1])

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        XCTAssertEqual(source.courses.count, 3)

        // ICS4U is already on the shelf under the same year.
        let outcomes: [ReferenceImporter.Outcome] = await importEverything(
            from: source,
            alreadyShelved: [ReferenceCourseRule.Shelved(
                displayCode: "ICS4U", schoolYear: 2025, folderName: "ICS4U-2025"
            )]
        )

        XCTAssertEqual(outcomes.count, 3, "Every ticked course is reported, whatever happened to it.")
        var imported: [String] = []
        var refused: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .imported(let made):
                imported.append(made.displayCode)
            case .notImported(let course, let reason):
                refused.append(course)
                XCTAssertFalse(reason.isEmpty, "A course that did not come across says why.")
            case .stopped:
                XCTFail("Nothing was stopped.")
            }
        }
        XCTAssertEqual(imported, ["ICS3U", "MPM2D"])
        XCTAssertEqual(refused, ["ICS4U"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: coursesDirectoryURL.appendingPathComponent("ICS4U-2025").path
            ),
            "A course that was refused left a folder behind."
        )
    }

    /// The clash is the contract's own rule, and it counts courses imported
    /// EARLIER IN THE SAME RUN.
    func testTwoCoursesOfTheSameCodeInOneRunRefuseTheSecond() async throws {
        try prepare()
        let secondCoursesFolder: URL = oldFolderURL.appendingPathComponent("courses")
        try makeOldCourse(code: "ICS3U", sections: [1], inCoursesFolder: secondCoursesFolder)
        // A second folder, same code, as a teacher's two old folders would
        // be. Read as one list by hand, which is what a run of two sources
        // amounts to.
        let otherURL: URL = rootURL.appendingPathComponent("Older Websites")
        try makeOldCourse(
            code: "ICS3U", sections: [1],
            inCoursesFolder: otherURL.appendingPathComponent("courses")
        )

        guard case .found(let first) = read(oldFolderURL),
              case .found(let second) = read(otherURL) else {
            return XCTFail("One of the folders was refused.")
        }
        var requests: [ReferenceImporter.Request] = []
        requests.append(ReferenceImporter.Request(course: try XCTUnwrap(first.courses.first), schoolYear: 2025))
        requests.append(ReferenceImporter.Request(course: try XCTUnwrap(second.courses.first), schoolYear: 2025))

        let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            requests,
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: [],
            from: first.rootURL,
            progress: { _ in }
        )
        XCTAssertEqual(outcomes.count, 2)
        guard case .imported = outcomes[0] else {
            return XCTFail("The first ICS3U did not come across.")
        }
        guard case .notImported(let course, _) = outcomes[1] else {
            return XCTFail("The second ICS3U came across as well: \(outcomes[1])")
        }
        XCTAssertEqual(course, "ICS3U")
    }

    /// Nothing half-made is left behind — including when the folder cannot be
    /// turned into a reference course at all.
    func testAFailureLeavesNoFolderBehind() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS3U", sections: [1])
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)

        // Break the settings AFTER the sheet read them, which is what a
        // teacher editing the old folder in another window would do.
        try Data("{ not json".utf8).write(to: courseURL.appendingPathComponent("course_config.json"))

        let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: found, schoolYear: 2025)],
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: [],
            from: source.rootURL,
            progress: { _ in }
        )
        guard case .notImported = try XCTUnwrap(outcomes.first) else {
            return XCTFail("A course whose settings cannot be read was imported: \(outcomes)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: coursesDirectoryURL.appendingPathComponent("ICS3U-2025").path
            ),
            "The half-made folder is still there. A teacher cannot delete what the app will not."
        )
    }

    /// Stopping leaves the courses already imported and nothing of the one in
    /// hand.
    func testStoppingLeavesNothingHalfMade() async throws {
        try prepare()
        try makeOldCourse(code: "ICS3U", sections: [1])
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        let coursesDirectoryURL: URL = self.coursesDirectoryURL
        let rootURL: URL = source.rootURL

        // Cancelled before it can run: the copy checks for it before every
        // single file, so the first check is the one that fires. No sleep,
        // no guessing at a duration.
        let run: Task<[ReferenceImporter.Outcome], Never> = Task { @MainActor in
            return await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: found, schoolYear: 2025)],
                into: coursesDirectoryURL,
                existingFolderNames: [],
                alreadyShelved: [],
                from: rootURL,
                progress: { _ in }
            )
        }
        run.cancel()
        let outcomes: [ReferenceImporter.Outcome] = await run.value

        XCTAssertEqual(outcomes, [ReferenceImporter.Outcome.stopped])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: coursesDirectoryURL.appendingPathComponent("ICS3U-2025").path
            ),
            "The course that was in hand when the teacher stopped is still on disk."
        )
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true).contains("stopped importing ICS3U for reference"),
            "Stopping left no line on the trail."
        )
    }

    /// A course copied out of a frozen source arrives as an ordinary folder
    /// that can be worked on and removed.
    ///
    /// The lock TRAVELS through a copy, and a locked half-made folder is one
    /// the teacher can delete from neither the app nor Finder.
    func testImportingFromAFolderThatIsItselfFrozenStillWorks() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS3U", sections: [1])
        ReferenceLock.lock(courseDirectory: courseURL)
        XCTAssertTrue(ReferenceLock.isLocked(
            courseURL.appendingPathComponent("section1").appendingPathComponent("index.md")
        ))

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let outcomes: [ReferenceImporter.Outcome] = await importEverything(from: source)
        guard case .imported = try XCTUnwrap(outcomes.first) else {
            return XCTFail("A frozen source could not be imported: \(outcomes)")
        }

        // The site markers really were renamed aside, which is the step a
        // locked copy would have failed at silently.
        let markers: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
            .appendingPathComponent(".netlify_sites")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: markers.appendingPathComponent("section1.json").path
        ))
    }

    // MARK: - The names on disk

    /// **The bytes of a file name are carried through unchanged.**
    ///
    /// Measured on Russell's own ICS4U: a per-file copy to a rebuilt `URL`
    /// turned `App\u{00e9}tit` (`c3 a9`) into `Appe\u{0301}tit`
    /// (`65 cc 81`), the page that embeds it still spelled it the old way,
    /// and the image then vanished from the built site — no error anywhere.
    /// Both spellings are tested side by side, because the fix must not
    /// "correct" either of them.
    func testAFileNameKeepsItsExactBytes() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS4U", sections: [1])
        let composed: String = "Bone App\u{00e9}tit.md"
        let decomposed: String = "Cre\u{0301}me Bru\u{0302}le\u{0301}e.md"
        for name in [composed, decomposed] {
            // Written with POSIX `open`, so the bytes on disk are exactly
            // these and nothing has normalised them on the way in.
            let path: String = courseURL.appendingPathComponent("Media").path + "/" + name
            let file: Int32 = open(path, O_CREAT | O_WRONLY, 0o644)
            XCTAssertGreaterThan(file, -1, "could not write \(name)")
            _ = write(file, "x", 1)
            close(file)
        }
        let sourceNames: Set<[UInt8]> = ReferenceImportTests.entryBytes(
            inFolder: courseURL.appendingPathComponent("Media").path
        )

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        _ = await importEverything(from: source)

        let copiedNames: Set<[UInt8]> = ReferenceImportTests.entryBytes(
            inFolder: coursesDirectoryURL.appendingPathComponent("ICS4U-2025")
                .appendingPathComponent("Media").path
        )
        XCTAssertEqual(
            copiedNames, sourceNames,
            "A name came across re-spelled. The page that links to it still spells it the old way, "
            + "so the link no longer resolves and the file disappears from the built site."
        )
    }

    // MARK: - Nothing is visible until it is safe

    /// The staging folder is invisible to everything that looks for a course.
    ///
    /// Pinned rather than assumed: the whole fail-safe rests on it.
    func testAStagingFolderIsNotACourseAndIsNotABackupOrAnArchive() throws {
        try prepare()
        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "course_code": "ICS4U", "section_numbers": [1],
        ]).write(to: staging.appendingPathComponent("course_config.json"))

        let workspace: WorkspaceModel = WorkspaceModel()
        workspace.chooseWorkspace(at: workingFolderURL)
        for course in workspace.courses {
            XCTAssertFalse(
                ReferenceStaging.isStagingName(course.code),
                "A half-made import showed up in the sidebar as a course."
            )
        }
        for item in WorkspaceModel.findBackupItems(in: coursesDirectoryURL) {
            XCTAssertFalse(ReferenceStaging.isStagingName(item.courseCode))
        }
        for item in WorkspaceModel.findArchivedItems(in: coursesDirectoryURL) {
            XCTAssertFalse(ReferenceStaging.isStagingName(item.courseCode))
        }
    }

    /// An import that never finished is tidied away the next time the folder
    /// is read — and a teacher's own dot-folder is never touched.
    func testAnUnfinishedImportIsSweptAndOtherDotFoldersAreNot() throws {
        try prepare()
        let fileManager: FileManager = FileManager.default
        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        try fileManager.createDirectory(
            at: staging.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        let page: URL = staging.appendingPathComponent("section1").appendingPathComponent("index.md")
        try Data("# half made\n".utf8).write(to: page)
        // Locked, as it is by the time the rename is the only step left.
        ReferenceLock.lock(courseDirectory: staging)
        XCTAssertTrue(ReferenceLock.isLocked(page))

        // Somebody else's dot-folder, which is not ours to remove.
        let theirs: URL = coursesDirectoryURL.appendingPathComponent(".internal")
        try fileManager.createDirectory(at: theirs, withIntermediateDirectories: true)

        let swept: [String] = ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL)
        XCTAssertEqual(swept, ["ICS4U-2025"], "The leftover names the course it was going to be.")
        XCTAssertFalse(fileManager.fileExists(atPath: staging.path))
        XCTAssertTrue(
            fileManager.fileExists(atPath: theirs.path),
            "The sweep took a folder that was not one of ours."
        )
    }

    /// While the copy is running there is nothing under `courses/` but the
    /// hidden folder — no half-made course, and no live site markers.
    func testACourseIsNeverVisibleBeforeItIsNeutralised() async throws {
        try prepare()
        try makeOldCourse(code: "ICS4U", sections: [1])
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)

        // Cancelled before the first file, which leaves the run at exactly
        // the point the old code left a live-looking course behind.
        let coursesDirectoryURL: URL = self.coursesDirectoryURL
        let run: Task<[ReferenceImporter.Outcome], Never> = Task { @MainActor in
            return await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: found, schoolYear: 2025)],
                into: coursesDirectoryURL,
                existingFolderNames: [],
                alreadyShelved: [],
                from: source.rootURL,
                progress: { _ in }
            )
        }
        run.cancel()
        _ = await run.value

        let left: [String] = try FileManager.default.contentsOfDirectory(
            atPath: coursesDirectoryURL.path
        )
        XCTAssertEqual(left, [], "Something was left under courses/ — visible or hidden.")
    }

    // MARK: - Where the work runs

    /// The copy runs OFF the main actor, so the progress bar can draw and the
    /// Stop button can be pressed.
    ///
    /// `@concurrent` is what does it. A plain `nonisolated async` function
    /// runs on its CALLER's actor in this project, because `project.yml` sets
    /// `SWIFT_APPROACHABLE_CONCURRENCY: YES` — and the copy's loop has no
    /// suspension point, so on the slow disk this is all written for the main
    /// actor would be held for the whole copy and Stop could not be clicked
    /// at all. `ReferenceImportSource.read` and the survey carry the same
    /// attribute for the same reason.
    func testTheCopyDoesNotRunOnTheMainThread() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS4U", sections: [1])
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.survey(
            courseAt: courseURL, leavingBehind: ReferenceImporter.leftBehindNames
        )
        let destination: URL = rootURL.appendingPathComponent("copied-off-the-main-thread")
        // The copy fills a folder that is already there; making it is the
        // caller's step, exactly as the importer does it.
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let wasOnTheMainThread: LockedBox = LockedBox()
        try await ReferenceTreeCopier.copy(survey, from: courseURL, into: destination) { _ in
            wasOnTheMainThread.record(Thread.isMainThread)
        }
        XCTAssertEqual(
            wasOnTheMainThread.value, false,
            "The copy ran on the main thread: the window is frozen for its whole length and the "
            + "Stop button cannot be clicked."
        )
    }

    // MARK: - A folder that cannot be read

    /// A folder the disk will not hand over is never skipped in silence.
    func testAnUnreadableFolderRefusesTheCourseByName() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS4U", sections: [1])
        let shut: URL = courseURL.appendingPathComponent("Locked Away")
        try FileManager.default.createDirectory(at: shut, withIntermediateDirectories: true)
        try Data("# page\n".utf8).write(to: shut.appendingPathComponent("page.md"))
        // Readable by nobody, which is what a bad sector or a folder from
        // another account looks like from here.
        try FileManager.default.setAttributes(
            [FileAttributeKey.posixPermissions: 0], ofItemAtPath: shut.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [FileAttributeKey.posixPermissions: 0o755], ofItemAtPath: shut.path
            )
        }

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        XCTAssertEqual(
            found.problem, ReferenceImportWording.couldNotReadFolder(folder: "Locked Away"),
            "The sheet says which folder could not be read, before anything is copied."
        )
        XCTAssertFalse(source.tickedWhenOpened.contains(found.id))
    }

    // MARK: - The sentences

    func testTheSentencesAreTheContractsSentences() throws {
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let wording: [String: Any] = try XCTUnwrap(block["wording"] as? [String: Any])

        XCTAssertEqual(ReferenceImportWording.menuItem, wording["menuItem"] as? String)
        XCTAssertEqual(ReferenceImportWording.title, wording["title"] as? String)
        XCTAssertEqual(ReferenceImportWording.explanation, wording["explanation"] as? String)
        XCTAssertEqual(
            ReferenceImportWording.noCoursesThere(folder: "{folder}"),
            wording["noCoursesThere"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.thatIsTheFolderYouHaveOpen,
            wording["thatIsTheFolderYouHaveOpen"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.insideTheFolderYouHaveOpen(folder: "{folder}"),
            wording["insideTheFolderYouHaveOpen"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.holdsTheFolderYouHaveOpen(folder: "{folder}"),
            wording["holdsTheFolderYouHaveOpen"] as? String
        )
        XCTAssertEqual(ReferenceImportWording.schoolYearLabel, wording["schoolYearLabel"] as? String)
        XCTAssertEqual(
            ReferenceImportWording.settingsCouldNotBeRead,
            wording["settingsCouldNotBeRead"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.couldNotReadFolder(folder: "{folder}"),
            wording["couldNotReadFolder"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.builtWebsitesAreNotCopied,
            wording["builtWebsitesAreNotCopied"] as? String
        )
        XCTAssertEqual(ReferenceImportWording.importButton, wording["importButton"] as? String)
        XCTAssertEqual(ReferenceImportWording.tickSomething, wording["tickSomething"] as? String)
        XCTAssertEqual(
            ReferenceImportWording.copying(course: "{course}"), wording["copying"] as? String
        )
        XCTAssertEqual(ReferenceImportWording.doneTitle, wording["doneTitle"] as? String)
        XCTAssertEqual(ReferenceImportWording.whereTheyAre, wording["whereTheyAre"] as? String)
        XCTAssertEqual(ReferenceImportWording.noSchoolYear, wording["noSchoolYear"] as? String)
        XCTAssertEqual(ReferenceImportWording.stopped, wording["stopped"] as? String)
        XCTAssertEqual(
            ReferenceImportWording.couldNotImport(course: "{course}", reason: "{reason}"),
            wording["couldNotImport"] as? String
        )

        // The three with a number in them, where the contract holds the
        // pattern and the test puts the numbers in.
        XCTAssertEqual(
            ReferenceImportWording.imported(course: "{course}", year: "{year}", sections: 2),
            (wording["imported"] as? String)?.replacingOccurrences(of: "{sections}", with: "2 sections")
        )
        XCTAssertEqual(
            ReferenceImportWording.courseSummary(sections: 1, pages: 1, bytes: 0),
            (wording["courseSummary"] as? String)?
                .replacingOccurrences(of: "{sections}", with: "1 section")
                .replacingOccurrences(of: "{pages}", with: "1 page")
                .replacingOccurrences(of: "{size}", with: ReferenceImportWording.size(0))
        )
        XCTAssertEqual(
            ReferenceImportWording.copiedSoFar(bytes: 0, of: 0),
            (wording["copiedSoFar"] as? String)?
                .replacingOccurrences(of: "{copied}", with: ReferenceImportWording.size(0))
                .replacingOccurrences(of: "{total}", with: ReferenceImportWording.size(0))
        )
    }

    /// Rule 1, asked of the sentences themselves.
    func testNoSentenceNamesTheMachinery() throws {
        let block: [String: Any] = try ReferenceImportTests.importingRules()
        let wording: [String: Any] = try XCTUnwrap(block["wording"] as? [String: Any])
        let forbidden: [String] = [
            "chflags", "immutable", "symlink", "container", "script", "toolchain",
            "docker", "launchd", "plist", "build output", "merged_output", "json",
        ]
        for (key, value) in wording {
            guard let sentence = value as? String, key != "machineryCheck", key != "rule" else {
                continue
            }
            for word in forbidden {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "referenceCourses.importing.wording.\(key) says “\(word)”: \(sentence)"
                )
            }
        }
    }

    // MARK: - Helpers

    private static func importingRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let reference: [String: Any] = try XCTUnwrap(all["referenceCourses"] as? [String: Any])
        return try XCTUnwrap(reference["importing"] as? [String: Any],
                             "No referenceCourses.importing in shared-rules.json")
    }

    /// Builds a case's tree. A path ending in `course_config.json` is written
    /// as real settings, so the walker finds a course rather than a folder
    /// with a file in it.
    private static func build(tree: [String], at folderURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for path in tree {
            let fileURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if fileURL.lastPathComponent == "course_config.json" {
                let code: String = fileURL.deletingLastPathComponent().lastPathComponent
                try JSONSerialization.data(withJSONObject: [
                    "course_code": code, "section_numbers": [1],
                ]).write(to: fileURL)
                continue
            }
            try Data("something".utf8).write(to: fileURL)
        }
    }

    /// Every file under a folder, by path, with its size and contents' digest
    /// — enough to prove nothing was touched.
    private static func manifest(of folderURL: URL) throws -> [String: String] {
        let fileManager: FileManager = FileManager.default
        var result: [String: String] = [:]
        guard let walker = fileManager.enumerator(
            at: folderURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: []
        ) else {
            return result
        }
        for case let fileURL as URL in walker {
            let values: URLResourceValues? = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
            )
            if values?.isDirectory == true {
                result[fileURL.path] = "folder"
                continue
            }
            var line: String = "\(values?.fileSize ?? -1)"
            if let modified = values?.contentModificationDate {
                line += " \(modified.timeIntervalSince1970)"
            }
            if let contents = try? Data(contentsOf: fileURL) {
                line += " \(contents.count) \(contents.base64EncodedString())"
            }
            result[fileURL.path] = line
        }
        return result
    }

    private static func name(of refusal: ReferenceImportSource.Refusal) -> String {
        switch refusal {
        case .noCoursesThere:
            return "noCoursesThere"
        case .theFolderYouHaveOpen:
            return "theFolderYouHaveOpen"
        case .insideTheFolderYouHaveOpen:
            return "insideTheFolderYouHaveOpen"
        case .holdsTheFolderYouHaveOpen:
            return "holdsTheFolderYouHaveOpen"
        }
    }

    /// Every entry name in a folder, as the BYTES the file system holds —
    /// never as a `String`, which is what hides this whole class of fault.
    private static func entryBytes(inFolder path: String) -> Set<[UInt8]> {
        var found: Set<[UInt8]> = []
        guard let directory = opendir(path) else {
            return found
        }
        defer { closedir(directory) }
        while let entry = readdir(directory) {
            var name: [UInt8] = []
            let length: Int = Int(entry.pointee.d_namlen)
            withUnsafeBytes(of: entry.pointee.d_name) { raw in
                for index in 0..<length {
                    name.append(raw[index])
                }
            }
            let text: String = String(decoding: name, as: UTF8.self)
            if text == "." || text == ".." || text == ".DS_Store" {
                continue
            }
            found.insert(name)
        }
        return found
    }

    private static func moment(year: Int, month: Int, day: Int) -> Date {
        var components: DateComponents = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components) ?? Date()
    }
}

/// Somewhere a `@Sendable` closure running off the main actor can leave an
/// answer for the test that is waiting for it.
final class LockedBox: @unchecked Sendable {

    // MARK: - Stored properties

    private let lock: NSLock = NSLock()
    private var answer: Bool?

    // MARK: - Computed properties

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return answer
    }

    // MARK: - Functions

    func record(_ isOnTheMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if answer == nil {
            answer = isOnTheMainThread
        }
    }
}
