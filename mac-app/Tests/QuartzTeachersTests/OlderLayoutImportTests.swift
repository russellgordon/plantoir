import XCTest
@testable import QuartzTeachers

/// Importing a class kept in Russell's OLDER layout — a folder per class,
/// with the shared folders and pages reached through links into a sibling
/// "… Shared" folder — as a reference course. Issue #254.
///
/// Runs `contracts/shared-rules.json` → `referenceCourses.importing.olderLayout`
/// (recognition, the code and year read off a name, choosing the shared folder
/// by hand, and where every file lands), and then proves the four things a
/// contract case cannot say on its own: no link reaches a reference course,
/// no add-on credential does either, every page and picture arrives as the
/// same bytes under the same name, and the source is never written.
@MainActor
final class OlderLayoutImportTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")
    var classWebsiteURL: URL = URL(fileURLWithPath: "/")

    /// The day every case is read on, from the contract, so a proposal read
    /// off a name cannot drift out of the offered years as the calendar moves.
    var today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 23) ?? CalendarDay.today()

    // MARK: - Setting up

    /// A destination working folder and a folder of older classes, under a
    /// throwaway root, with the trail redirected there too.
    func prepare() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("older-layout-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        classWebsiteURL = rootURL.appendingPathComponent("ICS3U").appendingPathComponent("Class Website")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: classWebsiteURL, withIntermediateDirectories: true)

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
        if let day = try? OlderLayoutImportTests.contractDay() {
            today = day
        }
    }

    /// A class folder and its shared folder, shaped the way the real ICS3U
    /// ones are: links named for every shared entry, a publishing add-on in
    /// `.obsidian`, pages with Digital Garden's keys, and two pictures whose
    /// names are spelled the two ways an accent can be.
    @discardableResult
    func makeICS3U(
        linksResolve: Bool = false,
        withShared: Bool = true
    ) throws -> (classURL: URL, sharedURL: URL) {
        let classURL: URL = classWebsiteURL.appendingPathComponent("ICS3U-S1-2023-24")
        let sharedURL: URL = classWebsiteURL.appendingPathComponent("ICS3U-2024-25 Shared")
        let fileManager: FileManager = FileManager.default

        try write("{\"alwaysUpdateLinks\": true}", to: classURL, "/.obsidian/app.json")
        try write("{\"theme\": \"obsidian\"}", to: classURL, "/.obsidian/appearance.json")
        try write(
            "{\"githubRepo\": \"garden\", \"githubToken\": \"not-a-real-credential-0000\"}",
            to: classURL, "/.obsidian/plugins/digitalgarden/data.json"
        )
        try write("console.log('publisher')", to: classURL, "/.obsidian/plugins/digitalgarden/main.js")
        try write("[\"digitalgarden\"]", to: classURL, "/.obsidian/community-plugins.json")
        try write("---\ndg-publish: true\ndg-home-link: false\n---\n# Day 1\n", to: classURL, "/Thread 1/Day 1.md")
        try write("---\ndg-publish: true\n---\n# Day 2\n![[Media/Appétit.png]]\n", to: classURL, "/Thread 1/Day 2.md")
        try write("---\ndg-publish: true\n---\n# Day 15\n", to: classURL, "/Thread 4/Day 15.md")
        try write("---\ndg-home: true\ndg-publish: true\n---\n![[Thread 4/Day 15]]\n", to: classURL, "/Home.md")
        try write("---\ndg-publish: true\n---\n- [[Thread 1/Day 1]]\n", to: classURL, "/All Prior Classes.md")
        try write("finder", to: classURL, "/.DS_Store")

        if withShared {
            try write("{}", to: sharedURL, "/.obsidian/app.json")
            try write("---\n---\n# Lists\n", to: sharedURL, "/Concepts/Lists.md")
            try write("---\ndraft: true\n---\n# Loops\n", to: sharedURL, "/Concepts/Loops.md")
            try write("# Goals\n", to: sharedURL, "/Learning Goals.md")
            try write("# Task\n", to: sharedURL, "/Tasks/Task 1.md")
            try write("never shown by this class", to: sharedURL, "/Not Named.md")
            try fileManager.createDirectory(
                at: sharedURL.appendingPathComponent("Media"), withIntermediateDirectories: true
            )
            try ReferenceTreeCopier.create(
                Data("composed picture".utf8),
                named: Array("App\u{00e9}tit.png".utf8),
                inFolderAt: sharedURL.appendingPathComponent("Media")
            )
            try ReferenceTreeCopier.create(
                Data("decomposed picture".utf8),
                named: Array("Cre\u{0300}me.png".utf8),
                inFolderAt: sharedURL.appendingPathComponent("Media")
            )
        }

        for name in ["Media", "Concepts", "Learning Goals.md", "Tasks"] {
            var target: String = "/nowhere-\(UUID().uuidString)/Old ICS3U/Class Website/ICS3U-2024-25 Shared/\(name)"
            if linksResolve {
                target = sharedURL.appendingPathComponent(name).path
            }
            try fileManager.createSymbolicLink(
                atPath: classURL.appendingPathComponent(name).path, withDestinationPath: target
            )
        }
        return (classURL: classURL, sharedURL: sharedURL)
    }

    /// Reads a folder the way the sheet does, on the contract's day.
    func read(_ chosenURL: URL) -> ReferenceImportSource.Outcome {
        return ReferenceImportSource.resolve(
            chosen: chosenURL,
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames,
            on: today
        )
    }

    /// Imports the given courses, each under 2023.
    func importCourses(_ courses: [ReferenceImportSource.FoundCourse]) async -> [ReferenceImporter.Outcome] {
        var requests: [ReferenceImporter.Request] = []
        for course in courses {
            requests.append(ReferenceImporter.Request(course: course, schoolYear: 2023))
        }
        return await ReferenceImporter.importCourses(
            requests,
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: [],
            from: classWebsiteURL,
            progress: { _ in }
        )
    }

    /// The one course the class folder makes, imported, with the outcome
    /// asserted FIRST — a test about what is inside a course must not pass
    /// because no course was made.
    func importTheClass(_ classURL: URL) async throws -> (outcome: ReferenceImporter.Outcome, courseURL: URL) {
        guard case .found(let source) = read(classURL) else {
            throw OlderLayoutTestFailure.refused
        }
        let course: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        let outcomes: [ReferenceImporter.Outcome] = await importCourses([course])
        let outcome: ReferenceImporter.Outcome = try XCTUnwrap(outcomes.first)
        switch outcome {
        case .imported(let made), .importedWithSomethingMissing(let made, _, _):
            return (outcome: outcome, courseURL: coursesDirectoryURL.appendingPathComponent(made.folderName))
        default:
            XCTFail("The class was not imported: \(outcomes)")
            throw OlderLayoutTestFailure.notImported
        }
    }

    // MARK: - The contract's cases

    func testRecognitionIsTheContractsCases() throws {
        let block: [String: Any] = try OlderLayoutImportTests.olderLayoutRules()
        let recognition: [String: Any] = try XCTUnwrap(block["recognition"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(recognition["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20, "The contract's recognition cases did not load.")

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case-\(UUID().uuidString)")
            try OlderLayoutImportTests.build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)

            let chosenPath: String = try XCTUnwrap(testCase["choose"] as? String)
            var chosenURL: URL = caseURL
            if chosenPath != "." {
                chosenURL = caseURL.appendingPathComponent(chosenPath)
            }
            let outcome: ReferenceImportSource.Outcome = read(chosenURL)
            let expectation: String = try XCTUnwrap(testCase["expect"] as? String)

            switch outcome {
            case .refused(let refusal):
                XCTAssertEqual(expectation, "refused", "\(name): refused, and the contract accepts it (\(refusal)).")
                XCTAssertEqual(
                    OlderLayoutImportTests.name(of: refusal), testCase["refusal"] as? String, "\(name): the refusal"
                )
            case .found(let found):
                XCTAssertEqual(expectation, "accepted", "\(name): accepted, and the contract refuses it.")
                let expected: [[String: Any]] = try XCTUnwrap(testCase["expectCourses"] as? [[String: Any]])
                XCTAssertEqual(found.courses.count, expected.count, "\(name): how many courses")
                var index: Int = 0
                for wanted in expected where index < found.courses.count {
                    try OlderLayoutImportTests.check(found.courses[index], against: wanted, in: name)
                    index += 1
                }
                var ticked: [String] = Array(found.tickedWhenOpened)
                ticked.sort()
                var wantedTicks: [String] = try XCTUnwrap(testCase["expectTicked"] as? [String])
                wantedTicks.sort()
                XCTAssertEqual(ticked, wantedTicks, "\(name): what is ticked when the sheet opens")
            }
        }
    }

    func testTheCodeAndYearAreTheContractsCases() throws {
        let block: [String: Any] = try OlderLayoutImportTests.olderLayoutRules()
        let codeAndYear: [String: Any] = try XCTUnwrap(block["codeAndYear"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(codeAndYear["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9)

        for testCase in cases {
            let folder: String = try XCTUnwrap(testCase["folder"] as? String)
            let facts: OlderCourseLayout.NameFacts = OlderCourseLayout.nameFacts(of: folder)
            XCTAssertEqual(facts.code, testCase["code"] as? String, "\(folder): the code")
            XCTAssertEqual(facts.startingYear, testCase["startingYear"] as? Int, "\(folder): the year")
            XCTAssertEqual(facts.section, testCase["section"] as? Int, "\(folder): the section")
            XCTAssertEqual(
                facts.looksLikeAClass, testCase["looksLikeAClass"] as? Bool, "\(folder): named like a class"
            )
        }
    }

    func testChoosingTheSharedFolderIsTheContractsCases() throws {
        let block: [String: Any] = try OlderLayoutImportTests.olderLayoutRules()
        let shared: [String: Any] = try XCTUnwrap(block["sharedFolder"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(shared["chosenCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case-\(UUID().uuidString)")
            try OlderLayoutImportTests.build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)
            let classURL: URL = caseURL.appendingPathComponent(try XCTUnwrap(testCase["classFolder"] as? String))
            let chosenURL: URL = caseURL.appendingPathComponent(try XCTUnwrap(testCase["choose"] as? String))

            guard case .found(let source) = read(classURL), let course = source.courses.first else {
                XCTFail("\(name): the class folder itself was not accepted")
                continue
            }
            let choice: ReferenceImportSource.SharedChoice = ReferenceImportSource.withSharedChosen(
                course,
                sharedFolderURL: chosenURL,
                workingFolderURL: workingFolderURL,
                leavingBehind: ReferenceImporter.leftBehindNames,
                on: today
            )
            let expectation: String = try XCTUnwrap(testCase["expect"] as? String)
            switch choice {
            case .refused(let sentence):
                XCTAssertEqual(expectation, "refused", "\(name): refused (\(sentence)), and the contract accepts it")
                let key: String = try XCTUnwrap(testCase["refusal"] as? String)
                XCTAssertEqual(
                    sentence,
                    OlderLayoutImportTests.sentence(forKey: key, folder: chosenURL.lastPathComponent),
                    "\(name): the refusal"
                )
            case .accepted(let remeasured):
                XCTAssertEqual(expectation, "accepted", "\(name): accepted, and the contract refuses it")
                let facts: OlderCourseLayout.Facts = try XCTUnwrap(remeasured.olderLayout)
                XCTAssertEqual(facts.shared.state.rawValue, testCase["shared"] as? String, "\(name): what was found")
                XCTAssertEqual(facts.shared.howFound, .chosen, "\(name): recorded as chosen by hand")
                XCTAssertEqual(facts.shared.missingNames, testCase["missing"] as? [String], "\(name): missing")
                XCTAssertEqual(facts.chosenWarning != nil, testCase["warning"] as? Bool, "\(name): the warning")
            }
        }
    }

    /// The three existing refusals about the folder this window has open
    /// apply to the chooser too: a shared folder inside the working folder
    /// would be copied into itself.
    func testTheSharedFolderCannotBeTheFolderYouHaveOpen() throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U(withShared: false)
        guard case .found(let source) = read(made.classURL), let course = source.courses.first else {
            return XCTFail("The class folder was refused.")
        }
        let choice: ReferenceImportSource.SharedChoice = ReferenceImportSource.withSharedChosen(
            course,
            sharedFolderURL: coursesDirectoryURL,
            workingFolderURL: workingFolderURL,
            leavingBehind: ReferenceImporter.leftBehindNames,
            on: today
        )
        guard case .refused(let sentence) = choice else {
            return XCTFail("A folder inside the one open was accepted as the shared folder.")
        }
        XCTAssertEqual(sentence, ReferenceImportWording.insideTheFolderYouHaveOpen(folder: "courses"))
    }

    func testPlacementIsTheContractsCases() async throws {
        let block: [String: Any] = try OlderLayoutImportTests.olderLayoutRules()
        let placement: [String: Any] = try XCTUnwrap(block["placement"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(placement["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case-\(UUID().uuidString)")
            try OlderLayoutImportTests.build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)
            var baseURL: URL = caseURL
            if let root = testCase["root"] as? String, root != "." {
                baseURL = caseURL.appendingPathComponent(root)
            }
            let classURL: URL = baseURL.appendingPathComponent(try XCTUnwrap(testCase["classFolder"] as? String))
            var sharedURL: URL?
            if let sharedName = testCase["sharedFolder"] as? String {
                sharedURL = baseURL.appendingPathComponent(sharedName)
            }

            let plan: OlderCourseLayout.Plan = OlderCourseLayout.plan(
                classFolderURL: classURL,
                sharedFolderURL: sharedURL,
                howFound: sharedURL == nil ? .none : .byItsName,
                leavingBehind: ReferenceImporter.leftBehindNames
            )
            XCTAssertEqual(plan.unreadableFolders, [], "\(name): nothing should be unreadable")

            var placed: [String: String] = [:]
            for entry in plan.placements where !entry.item.isDirectory {
                placed[entry.destinationText] = entry.sourceRoot.lastPathComponent + "/" + entry.item.text
            }
            XCTAssertEqual(
                placed, try XCTUnwrap(testCase["expectPlaced"] as? [String: String]), "\(name): where every file lands"
            )

            var leftOut: [String] = []
            for entry in plan.leftOut {
                leftOut.append("\(entry.path) | \(entry.inTheSharedFolder) | \(entry.reason.rawValue)")
            }
            leftOut.sort()
            var wantedLeftOut: [String] = []
            for entry in try XCTUnwrap(testCase["expectLeftOut"] as? [[String: Any]]) {
                let path: String = try XCTUnwrap(entry["path"] as? String)
                let inShared: Bool = try XCTUnwrap(entry["inTheSharedFolder"] as? Bool)
                let reason: String = try XCTUnwrap(entry["reason"] as? String)
                wantedLeftOut.append("\(path) | \(inShared) | \(reason)")
            }
            wantedLeftOut.sort()
            XCTAssertEqual(leftOut, wantedLeftOut, "\(name): what is left out, and why")

            XCTAssertEqual(plan.shared.missingNames, testCase["expectMissing"] as? [String], "\(name): missing")
            var lost: [String] = plan.leftOutAndLost
            lost.sort()
            var wantedLost: [String] = try XCTUnwrap(testCase["expectLost"] as? [String], "\(name): no expectLost")
            wantedLost.sort()
            XCTAssertEqual(lost, wantedLost, "\(name): what is lost, and must be named")
            XCTAssertEqual(plan.createsEmptyMedia, testCase["expectEmptyMedia"] as? Bool, "\(name): an empty Media")

            if let settings = testCase["expectSettings"] as? [String: Any] {
                let written: [String: Any] = plan.settingsValues()
                for (key, value) in settings {
                    let actual: NSObject? = written[key] as? NSObject
                    XCTAssertTrue(
                        actual?.isEqual(value) == true,
                        "\(name): settings key \(key) is \(String(describing: written[key])), the contract says \(value)"
                    )
                }
            }

            if let after = testCase["afterImporting"] as? [String: Any] {
                try await checkAfterImporting(classURL: classURL, plan: plan, rules: after, name: name)
            }
        }
    }

    /// The contract's `afterImporting` rules, asked of a REAL import.
    func checkAfterImporting(classURL: URL, plan: OlderCourseLayout.Plan, rules: [String: Any], name: String) async throws {
        let made: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(classURL)
        let files: [String: Data] = try OlderLayoutImportTests.regularFiles(under: made.courseURL)
        XCTAssertGreaterThan(files.count, 0, "\(name): the course is empty")

        if let forbidden = rules["noFileContains"] as? String {
            for (path, contents) in files {
                XCTAssertNil(
                    contents.range(of: Data(forbidden.utf8)),
                    "\(name): \(path) carries a forbidden key. Its value is not printed."
                )
            }
        }
        for path in (rules["noPath"] as? [String]) ?? [] {
            XCTAssertNil(
                OlderCourseLayout.kind(of: made.courseURL.appendingPathComponent(path)),
                "\(name): \(path) came across"
            )
        }
        if rules["noLinks"] as? Bool == true {
            XCTAssertEqual(OlderLayoutImportTests.links(under: made.courseURL), [], "\(name): a link came across")
        }
        if rules["filesAreThePlacedOnesPlusTheSettings"] as? Bool == true {
            var placedFiles: Int = 0
            for entry in plan.placements where !entry.item.isDirectory {
                placedFiles += 1
            }
            XCTAssertEqual(files.count, placedFiles + 1, "\(name): files out are the files placed plus course_config.json")
        }
    }

    // MARK: - What only a real import can prove

    /// No link, of any shape, reaches a reference course — and the census
    /// agrees AND is complete, so a course holding a link cannot pass by
    /// counting fewer.
    func testNoLinkReachesAReferenceCourse() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        // A resolving link, a nested one, and one inside a shared folder.
        try FileManager.default.createSymbolicLink(
            atPath: made.classURL.appendingPathComponent("Thread 1/Shortcut.md").path,
            withDestinationPath: made.sharedURL.appendingPathComponent("Learning Goals.md").path
        )
        try FileManager.default.createSymbolicLink(
            atPath: made.sharedURL.appendingPathComponent("Concepts/Elsewhere").path,
            withDestinationPath: rootURL.path
        )

        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        guard case .importedWithSomethingMissing(_, false, let leftOut) = imported.outcome else {
            return XCTFail("Two links below the top were left out, and it did not say so: \(imported.outcome)")
        }
        XCTAssertEqual(leftOut.sorted(), ["Concepts/Elsewhere", "Thread 1/Shortcut.md"])
        let files: [String: Data] = try OlderLayoutImportTests.regularFiles(under: imported.courseURL)
        // 2 obsidian + 5 class pages + 4 shared pages + 2 pictures + settings.
        XCTAssertEqual(files.count, 14, "Files out: \(files.keys.sorted())")
        XCTAssertEqual(OlderLayoutImportTests.links(under: imported.courseURL), [])

        let census: ReferenceLock.Census = ReferenceLock.census(courseDirectory: imported.courseURL)
        XCTAssertTrue(census.agrees, "\(census)")
        var ordinaryFiles: Int = 0
        for path in files.keys where !path.hasPrefix(".obsidian/") && path != "course_config.json" {
            ordinaryFiles += 1
        }
        XCTAssertEqual(census.shouldBeLocked, ordinaryFiles, "The census counted fewer files than are there.")
    }

    /// A picture reached through a link BELOW the top of the class folder is
    /// left out — and the import says so, by name, in the summary and on
    /// the trail, rather than calling itself complete. (#254 fixes, item 1:
    /// the first shape reported `.imported` and "nothing missing".)
    func testANestedLinkLeftOutIsCountedAndNamed() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        try FileManager.default.createSymbolicLink(
            atPath: made.classURL.appendingPathComponent("Thread 1/diagram.png").path,
            withDestinationPath: made.sharedURL.appendingPathComponent("Media/App\u{00e9}tit.png").path
        )
        // A link inside the add-ons, which are left behind BY DESIGN: not a
        // loss, and not to be reported as one.
        try FileManager.default.createSymbolicLink(
            atPath: made.classURL.appendingPathComponent(".obsidian/plugins/devlinked").path,
            withDestinationPath: made.sharedURL.path
        )
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        guard case .importedWithSomethingMissing(let madeCourse, false, let leftOut) = imported.outcome else {
            return XCTFail("A picture was dropped and the import called itself complete: \(imported.outcome)")
        }
        XCTAssertEqual(leftOut, ["Thread 1/diagram.png"])
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.line(for: imported.outcome),
            ReferenceImportWording.imported(
                course: madeCourse.displayCode, year: SchoolYear.label(forStartingYear: 2023), sections: 1
            ) + ". " + ReferenceImportWording.olderLayoutLeftOut(count: 1, names: ["Thread 1/diagram.png"])
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("left out 1: Thread 1/diagram.png"), "The trail does not name it: \(trail)")
        XCTAssertEqual(OlderLayoutImportTests.links(under: imported.courseURL), [])
    }

    /// Which sentence a ticked row gets when its code and year clash —
    /// decided outside the view, so it can be pinned. A clash only with a
    /// row ticked above it in the same sheet never says "You already have…".
    func testAClashInsideOneSheetIsNotCalledAlreadyKept() throws {
        let exemplars: ReferenceImportSource.FoundCourse = OlderLayoutImportTests.row("ICD2O-Exemplars")
        let first: ReferenceImportSource.FoundCourse = OlderLayoutImportTests.row("ICD2O-S1-2023-24")
        let second: ReferenceImportSource.FoundCourse = OlderLayoutImportTests.row("ICD2O-S2-2023-24")
        var years: [String: Int?] = [:]
        years[exemplars.id] = .some(2023)
        years[first.id] = .some(2023)
        years[second.id] = .some(2023)

        // A non-section row above S1: the neutral in-sheet sentence.
        let withExemplars: [String: String] = ImportCoursesForReferenceSheet.troubleByCourse(
            courses: [exemplars, first], ticked: [exemplars.id, first.id], years: years, onTheShelf: []
        )
        XCTAssertNil(withExemplars[exemplars.id])
        XCTAssertEqual(
            withExemplars[first.id],
            ReferenceImportWording.alsoTickedForThatYear(folder: "ICD2O-Exemplars", course: "ICD2O")
        )

        // Two sections: they say they are sections.
        let twoSections: [String: String] = ImportCoursesForReferenceSheet.troubleByCourse(
            courses: [first, second], ticked: [first.id, second.id], years: years, onTheShelf: []
        )
        XCTAssertEqual(
            twoSections[second.id],
            ReferenceImportWording.olderLayoutAnotherSectionOfTheSameCourse(folder: "ICD2O-S1-2023-24")
        )

        // Something really on the shelf: then "You already have…" is true.
        let shelf: [ReferenceCourseRule.Shelved] = [
            ReferenceCourseRule.Shelved(displayCode: "ICD2O", schoolYear: 2023, folderName: "ICD2O-2023"),
        ]
        let alreadyKept: [String: String] = ImportCoursesForReferenceSheet.troubleByCourse(
            courses: [first], ticked: [first.id], years: years, onTheShelf: shelf
        )
        XCTAssertEqual(
            alreadyKept[first.id],
            ReferenceCourseRule.Trouble.codeAlreadyInThatYear(code: "ICD2O", schoolYear: 2023).sentence
        )
    }

    /// The copier refuses a link handed to it, so a planner bug fails loudly.
    func testTheCopierRefusesALink() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
            courseAt: made.classURL, leavingBehind: []
        )
        var aLink: ReferenceTreeCopier.Item?
        for item in survey.items where item.isSymbolicLink {
            aLink = item
        }
        let link: ReferenceTreeCopier.Item = try XCTUnwrap(aLink, "The fixture has no link to hand over.")
        let destination: URL = rootURL.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            try await ReferenceTreeCopier.copy(
                placements: [ReferenceTreeCopier.Placement(
                    sourceRoot: made.classURL, item: link, destination: link.relativePath
                )],
                into: destination,
                progress: { _ in }
            )
            XCTFail("A link was copied.")
        } catch {
            XCTAssertEqual(OlderLayoutImportTests.links(under: destination), [])
        }
    }

    /// The publishing add-on and its credential never come across; the rest
    /// of `.obsidian` does, and reading view is still set.
    func testNoAddOnOrItsCredentialComesAcross() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        let files: [String: Data] = try OlderLayoutImportTests.regularFiles(under: imported.courseURL)
        XCTAssertNotNil(files[".obsidian/appearance.json"], "The rest of .obsidian did not come.")
        for (path, contents) in files {
            XCTAssertNil(contents.range(of: Data("githubToken".utf8)), "\(path) carries the add-on's credential key.")
            XCTAssertFalse(path.hasPrefix(".obsidian/plugins"), "\(path) came across.")
        }
        XCTAssertNil(files[".obsidian/community-plugins.json"])
        let appSettings: String = String(decoding: try XCTUnwrap(files[".obsidian/app.json"]), as: UTF8.self)
        XCTAssertTrue(appSettings.contains("defaultViewMode"), "Reading view was not set: \(appSettings)")
    }

    /// Every page is the same bytes — `Home.md` as `section1/index.md`, the
    /// one rename — and every shared file is the shared folder's, under
    /// exactly its own name bytes, an accent either way.
    func testEveryPageAndPictureIsTheSameBytesUnderTheSameName() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        let courseURL: URL = imported.courseURL

        let pairs: [(String, URL)] = [
            ("section1/index.md", made.classURL.appendingPathComponent("Home.md")),
            ("section1/Thread 1/Day 1.md", made.classURL.appendingPathComponent("Thread 1/Day 1.md")),
            ("section1/Thread 1/Day 2.md", made.classURL.appendingPathComponent("Thread 1/Day 2.md")),
            ("section1/Thread 4/Day 15.md", made.classURL.appendingPathComponent("Thread 4/Day 15.md")),
            ("section1/All Prior Classes.md", made.classURL.appendingPathComponent("All Prior Classes.md")),
            ("Concepts/Lists.md", made.sharedURL.appendingPathComponent("Concepts/Lists.md")),
            ("Concepts/Loops.md", made.sharedURL.appendingPathComponent("Concepts/Loops.md")),
            ("Learning Goals.md", made.sharedURL.appendingPathComponent("Learning Goals.md")),
            ("Tasks/Task 1.md", made.sharedURL.appendingPathComponent("Tasks/Task 1.md")),
        ]
        for (destination, source) in pairs {
            XCTAssertEqual(
                try Data(contentsOf: courseURL.appendingPathComponent(destination)),
                try Data(contentsOf: source),
                "\(destination) is not byte-identical to its source"
            )
        }
        let home: String = try String(contentsOf: courseURL.appendingPathComponent("section1/index.md"), encoding: .utf8)
        XCTAssertTrue(home.contains("dg-home: true"), "The dg-* keys are kept exactly (decision 3).")
        XCTAssertNil(OlderCourseLayout.kind(of: courseURL.appendingPathComponent("Not Named.md")))
        XCTAssertNil(OlderCourseLayout.kind(of: courseURL.appendingPathComponent("section1/Home.md")))

        let sourceNames: Set<[UInt8]> = Set(ReferenceTreeCopier.names(inFolderAt: made.sharedURL.appendingPathComponent("Media")))
        let copiedNames: Set<[UInt8]> = Set(ReferenceTreeCopier.names(inFolderAt: courseURL.appendingPathComponent("Media")))
        XCTAssertEqual(copiedNames, sourceNames, "A picture's name changed its bytes on the way in.")
        XCTAssertTrue(copiedNames.contains(Array("App\u{00e9}tit.png".utf8)))
        XCTAssertTrue(copiedNames.contains(Array("Cre\u{0300}me.png".utf8)))
    }

    /// The settings: one section, the class's name, its Thread folders, and
    /// a frozen reference course.
    func testTheSettingsMakeAFrozenSingleSectionReferenceCourse() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        XCTAssertEqual(imported.courseURL.lastPathComponent, "ICS3U-2023")

        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: imported.courseURL.appendingPathComponent("course_config.json")
        )
        XCTAssertTrue(configuration.keptForReference)
        XCTAssertEqual(configuration.referenceSchoolYear, 2023)
        XCTAssertEqual(configuration.courseCode, "ICS3U")
        XCTAssertEqual(configuration.values["course_name"] as? String, "ICS3U-S1-2023-24")
        XCTAssertEqual(configuration.values["section_numbers"] as? [Int], [1])
        XCTAssertEqual(configuration.values["per_section_folders"] as? [String], ["Thread 1", "Thread 4"])
        XCTAssertEqual(configuration.values["shared_folders"] as? [String], ["Concepts", "Tasks"])
        // Off through the app's OWN reader. A per-section map read as ON
        // here, and in setup_course.py's bool(...) (#254 fixes, item 2).
        XCTAssertFalse(configuration.includesCurriculumCoverage)
        XCTAssertEqual(configuration.values["include_curriculum_coverage"] as? Bool, false)
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath))
        XCTAssertTrue(ReferenceLock.isLocked(imported.courseURL.appendingPathComponent("section1/index.md")))
        XCTAssertTrue(ReferenceLock.isLocked(imported.courseURL.appendingPathComponent("Concepts/Lists.md")))
    }

    /// Found by NAME: links that resolve to a DIFFERENT folder, holding
    /// different bytes, are not followed.
    func testTheSharedFolderIsFoundByItsNameNotByFollowing() async throws {
        try prepare()
        let decoyURL: URL = rootURL.appendingPathComponent("Decoy")
        try write("DECOY", to: decoyURL, "/Concepts/Lists.md")
        try write("DECOY", to: decoyURL, "/Learning Goals.md")
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        for name in ["Concepts", "Learning Goals.md"] {
            let linkURL: URL = made.classURL.appendingPathComponent(name)
            try FileManager.default.removeItem(at: linkURL)
            try FileManager.default.createSymbolicLink(
                atPath: linkURL.path, withDestinationPath: decoyURL.appendingPathComponent(name).path
            )
        }
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        XCTAssertEqual(
            try Data(contentsOf: imported.courseURL.appendingPathComponent("Concepts/Lists.md")),
            try Data(contentsOf: made.sharedURL.appendingPathComponent("Concepts/Lists.md"))
        )
        XCTAssertEqual(
            try Data(contentsOf: imported.courseURL.appendingPathComponent("Learning Goals.md")),
            try Data(contentsOf: made.sharedURL.appendingPathComponent("Learning Goals.md"))
        )
    }

    /// No shared folder anywhere: it imports anyway, says so in the summary,
    /// and has an empty Media folder.
    func testWithoutItsSharedFolderItStillImportsAndSaysSo() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U(withShared: false)
        guard case .found(let source) = read(classWebsiteURL), let course = source.courses.first else {
            return XCTFail("The folder of classes was refused.")
        }
        XCTAssertEqual(course.olderLayout?.shared.state, .notFound)
        XCTAssertEqual(
            OlderCourseLayout.sentence(about: try XCTUnwrap(course.olderLayout).shared),
            ReferenceImportWording.olderLayoutSharedNotFound(count: 4)
        )

        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheClass(made.classURL)
        guard case .importedWithSomethingMissing(let madeCourse, true, []) = imported.outcome else {
            return XCTFail("The summary does not say the shared pages are missing: \(imported.outcome)")
        }
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.line(for: imported.outcome),
            ReferenceImportWording.olderLayoutImportedWithSharedMissing(
                course: madeCourse.displayCode, year: SchoolYear.label(forStartingYear: 2023)
            )
        )
        XCTAssertEqual(OlderCourseLayout.kind(of: imported.courseURL.appendingPathComponent("Media")), S_IFDIR)
        XCTAssertEqual(OlderLayoutImportTests.links(under: imported.courseURL), [])
    }

    /// The source — the class folder AND the shared folder — is exactly as
    /// it was: every entry's bytes, size, time and link text.
    func testTheSourceIsNeverWritten() async throws {
        try prepare()
        try makeICS3U(linksResolve: true)
        let before: [String: String] = try OlderLayoutImportTests.manifest(of: classWebsiteURL)
        guard case .found(let source) = read(classWebsiteURL) else {
            return XCTFail("The folder of classes was refused.")
        }
        let outcomes: [ReferenceImporter.Outcome] = await importCourses(source.courses)
        guard case .imported = try XCTUnwrap(outcomes.first) else {
            return XCTFail("Nothing was imported, so nothing could have been written: \(outcomes)")
        }
        let after: [String: String] = try OlderLayoutImportTests.manifest(of: classWebsiteURL)
        XCTAssertEqual(before, after, "The folder the class was read from changed.")
    }

    /// Stopped before the first file: nothing of it is left.
    func testStoppingLeavesNothing() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        guard case .found(let source) = read(made.classURL), let course = source.courses.first else {
            return XCTFail("The class folder was refused.")
        }
        let coursesDirectoryURL: URL = self.coursesDirectoryURL
        let classWebsiteURL: URL = self.classWebsiteURL
        let run: Task<[ReferenceImporter.Outcome], Never> = Task { @MainActor in
            return await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: course, schoolYear: 2023)],
                into: coursesDirectoryURL,
                existingFolderNames: [],
                alreadyShelved: [],
                from: classWebsiteURL,
                progress: { _ in }
            )
        }
        run.cancel()
        let outcomes: [ReferenceImporter.Outcome] = await run.value
        XCTAssertEqual(outcomes, [ReferenceImporter.Outcome.stopped])
        let left: [String] = try FileManager.default.contentsOfDirectory(atPath: coursesDirectoryURL.path)
        var leftovers: [String] = []
        for name in left where name != ".internal" {
            leftovers.append(name)
        }
        XCTAssertEqual(leftovers, [], "Something of the stopped class is still there.")
    }

    /// Two lines: the ordinary one, naming the CLASS folder, and the older
    /// layout's own, naming the shared folder and how it was found. Names
    /// only — never a page's words.
    func testTheTrailSaysWhereTheSharedPagesCameFrom() async throws {
        try prepare()
        let made: (classURL: URL, sharedURL: URL) = try makeICS3U()
        _ = try await importTheClass(made.classURL)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("imported ICS3U for reference from ICS3U-S1-2023-24 as ICS3U-2023"),
            "The ordinary line does not name the class folder: \(trail)"
        )
        XCTAssertTrue(
            trail.contains("imported ICS3U-S1-2023-24 from the older layout as ICS3U-2023 — shared pages from "
                           + "ICS3U-2024-25 Shared (found by its name), 4 of 4 brought across; nothing missing; "
                           + "4 links replaced by the shared folder's own; nothing else left out"),
            "The older layout's own line is missing or wrong: \(trail)"
        )
        XCTAssertFalse(trail.contains("Day 15"), "A page's words reached the trail.")
        XCTAssertFalse(trail.contains("githubToken"))
        XCTAssertFalse(trail.contains("not-a-real-credential"))
    }

    // MARK: - The sentences

    func testTheSentencesAreTheContractsSentences() throws {
        let wording: [String: Any] = try OlderLayoutImportTests.wordingRules()
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutSharedFound(folder: "{folder}"),
            wording["olderLayoutSharedFound"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutSharedPartlyFound(folder: "{folder}", missing: ["{names}"]),
            wording["olderLayoutSharedPartlyFound"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutSharedNotFound(count: 7),
            (wording["olderLayoutSharedNotFound"] as? String)?.replacingOccurrences(of: "{count}", with: "7")
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutChooseSharedButton, wording["olderLayoutChooseSharedButton"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutChosenFolderHasNone(folder: "{folder}"),
            wording["olderLayoutChosenFolderHasNone"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutChosenFolderIsAClass(folder: "{folder}"),
            wording["olderLayoutChosenFolderIsAClass"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutChosenFolderIsForAnotherCourse(
                folder: "{folder}", code: "{code}", course: "{course}"
            ),
            wording["olderLayoutChosenFolderIsForAnotherCourse"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutThatIsTheSharedFolder(folder: "{folder}"),
            wording["olderLayoutThatIsTheSharedFolder"] as? String
        )
        XCTAssertEqual(ReferenceImportWording.olderLayoutNoCourseCode, wording["olderLayoutNoCourseCode"] as? String)
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutAnotherSectionOfTheSameCourse(folder: "{folder}"),
            wording["olderLayoutAnotherSectionOfTheSameCourse"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutImportedWithSharedMissing(course: "{course}", year: "{year}"),
            wording["olderLayoutImportedWithSharedMissing"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutAddOnsAreLeftBehind, wording["olderLayoutAddOnsAreLeftBehind"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutLeftOut(count: 7, names: ["{names}"]),
            (wording["olderLayoutLeftOut"] as? String)?.replacingOccurrences(of: "{count}", with: "7")
        )
        XCTAssertEqual(
            ReferenceImportWording.alsoTickedForThatYear(folder: "{folder}", course: "{course}"),
            wording["alsoTickedForThatYear"] as? String
        )
        XCTAssertEqual(
            ReferenceImportWording.olderLayoutChooseOneCourseAtATime(folder: "{folder}"),
            wording["olderLayoutChooseOneCourseAtATime"] as? String
        )
        XCTAssertEqual(ReferenceImportWording.list(["Concepts", "Media", "Tasks"]), "Concepts, Media and Tasks")
    }

    /// Rule 1 for the new sentences, with the words this piece is most
    /// likely to leak: how the old folders were joined up.
    func testNoNewSentenceNamesTheMachinery() throws {
        let wording: [String: Any] = try OlderLayoutImportTests.wordingRules()
        let forbidden: [String] = ["symlink", "link", "vault", "plugin", "token", "script", "container", "toolchain"]
        for (key, value) in wording where key.hasPrefix("olderLayout") && key != "olderLayoutRule" {
            let sentence: String = try XCTUnwrap(value as? String)
            for word in forbidden {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(key) says “\(word)”")
            }
        }
    }

    // MARK: - Helpers

    private func write(_ text: String, to folderURL: URL, _ relative: String) throws {
        let fileURL: URL = URL(fileURLWithPath: folderURL.path + relative)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: fileURL)
    }

    private static func contractRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let reference: [String: Any] = try XCTUnwrap(all["referenceCourses"] as? [String: Any])
        return try XCTUnwrap(reference["importing"] as? [String: Any])
    }

    private static func olderLayoutRules() throws -> [String: Any] {
        return try XCTUnwrap(
            try OlderLayoutImportTests.contractRules()["olderLayout"] as? [String: Any],
            "No referenceCourses.importing.olderLayout in shared-rules.json"
        )
    }

    private static func wordingRules() throws -> [String: Any] {
        return try XCTUnwrap(try OlderLayoutImportTests.contractRules()["wording"] as? [String: Any])
    }

    private static func contractDay() throws -> CalendarDay {
        let text: String = try XCTUnwrap(try OlderLayoutImportTests.olderLayoutRules()["today"] as? String)
        return try XCTUnwrap(CalendarDay(text: text))
    }

    /// One found course against one of the contract's `expectCourses`.
    private static func check(
        _ course: ReferenceImportSource.FoundCourse,
        against wanted: [String: Any],
        in name: String
    ) throws {
        XCTAssertEqual(course.folderName, wanted["folder"] as? String, "\(name): the row")
        XCTAssertEqual(course.courseCode, wanted["code"] as? String, "\(name): the code")
        if wanted["olderLayout"] as? Bool == false {
            XCTAssertNil(course.olderLayout, "\(name): read as the older layout")
            return
        }
        let facts: OlderCourseLayout.Facts = try XCTUnwrap(course.olderLayout, "\(name): not read as the older layout")
        XCTAssertEqual(course.suggestedSchoolYear, wanted["year"] as? Int, "\(name): \(course.folderName)'s year")
        XCTAssertEqual(facts.shared.state.rawValue, wanted["shared"] as? String, "\(name): \(course.folderName)'s shared")
        XCTAssertEqual(facts.shared.folderName, wanted["sharedFolder"] as? String, "\(name): which shared folder")
        XCTAssertEqual(facts.shared.missingNames, wanted["missing"] as? [String], "\(name): what is missing")
        if let key = wanted["problem"] as? String {
            XCTAssertEqual(course.problem, OlderLayoutImportTests.sentence(forKey: key, folder: course.folderName))
        } else {
            XCTAssertNil(course.problem, "\(name): \(course.folderName) has a problem: \(course.problem ?? "")")
        }
    }

    /// A sheet row for an older-layout class, measured from nothing but its
    /// name — enough for the rule that picks a row's sentence.
    private static func row(_ folderName: String) -> ReferenceImportSource.FoundCourse {
        let names: OlderCourseLayout.NameFacts = OlderCourseLayout.nameFacts(of: folderName)
        return ReferenceImportSource.FoundCourse(
            folderName: folderName,
            courseCode: names.code ?? folderName,
            courseName: folderName,
            sectionNumbers: [1],
            pageCount: 1,
            fileCount: 1,
            byteCount: 1,
            problem: nil,
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

    private static func sentence(forKey key: String, folder: String) -> String? {
        switch key {
        case "olderLayoutNoCourseCode":
            return ReferenceImportWording.olderLayoutNoCourseCode
        case "olderLayoutChosenFolderHasNone":
            return ReferenceImportWording.olderLayoutChosenFolderHasNone(folder: folder)
        case "olderLayoutChosenFolderIsAClass":
            return ReferenceImportWording.olderLayoutChosenFolderIsAClass(folder: folder)
        default:
            return nil
        }
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
        case .theSharedFolder:
            return "theSharedFolder"
        case .aFolderOfOlderCourses:
            return "aFolderOfOlderCourses"
        case .partOfAClassWebsite:
            return "checkoutLayoutChooseTheWholeFolder"
        case .onlyTheFirstSection:
            return "checkoutLayoutOnlyTheFirstSection"
        case .severalClassWebsiteCourses:
            return "checkoutLayoutChooseOneCourseAtATime"
        case .shortcutTrouble:
            return "checkoutLayoutShortcut"
        }
    }

    /// Builds a contract tree: see `olderLayout.treeEntries`.
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
                continue
            }
            guard let described = entry as? [String: Any] else {
                continue
            }
            if described["link"] != nil {
                // Made after every file, so a resolving link has something
                // to resolve to.
                links.append(described)
                continue
            }
            let path: String = try XCTUnwrap(described["file"] as? String)
            let fileURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text: String = (described["text"] as? String) ?? "something"
            try Data(text.utf8).write(to: fileURL)
            if let changed = described["changed"] as? String {
                let day: CalendarDay = try XCTUnwrap(CalendarDay(text: changed))
                var components: DateComponents = DateComponents()
                components.year = day.year
                components.month = day.month
                components.day = day.day
                components.hour = 12
                let moment: Date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
                try fileManager.setAttributes([.modificationDate: moment], ofItemAtPath: fileURL.path)
            }
        }
        for described in links {
            let path: String = try XCTUnwrap(described["link"] as? String)
            let linkURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var target: String = "/nowhere-\(UUID().uuidString)/\(path)"
            if let to = described["to"] as? String {
                target = folderURL.appendingPathComponent(to).path
            }
            try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: target)
        }
    }

    /// Every regular file under a folder, by relative path, with its bytes.
    /// Never follows a link.
    private static func regularFiles(under folderURL: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: folderURL, leavingBehind: [])
        for item in survey.items where !item.isDirectory && !item.isSymbolicLink {
            result[item.text] = try Data(contentsOf: ReferenceTreeCopier.url(named: item.relativePath, inFolderAt: folderURL))
        }
        return result
    }

    /// Every link under a folder, by relative path.
    private static func links(under folderURL: URL) -> [String] {
        var result: [String] = []
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: folderURL, leavingBehind: [])
        for item in survey.items where item.isSymbolicLink {
            result.append(item.text)
        }
        return result
    }

    /// Every entry under a folder — files, folders AND links, never followed —
    /// with its size, modification time, contents' digest and link text.
    private static func manifest(of folderURL: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: folderURL, leavingBehind: [])
        for item in survey.items {
            let url: URL = ReferenceTreeCopier.url(named: item.relativePath, inFolderAt: folderURL)
            var status: stat = stat()
            _ = lstat(url.path, &status)
            var line: String = "mode \(status.st_mode) size \(status.st_size) "
                + "time \(status.st_mtimespec.tv_sec).\(status.st_mtimespec.tv_nsec) flags \(status.st_flags)"
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

/// Why a helper above gave up, so the test that called it stops there.
enum OlderLayoutTestFailure: Error {
    case refused
    case notImported
}
