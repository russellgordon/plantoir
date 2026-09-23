import XCTest
@testable import QuartzTeachers

/// Importing the first section of a class kept in Russell's 2024–25 layout —
/// a whole website folder per class, reached directly or through Finder
/// shortcuts — as a reference course. Issue #256.
///
/// Runs `contracts/shared-rules.json` → `referenceCourses.importing
/// .quartzCheckoutLayout` (recognition, the year, the class pages' word and
/// where every file lands), and then proves what a contract case cannot say
/// on its own: a symlink is never taken for a shortcut, no link reaches a
/// reference course, every page arrives as the same bytes under the same
/// name, the copy in the folder pointed at is the one used, machinery left
/// behind is never reported as a loss, and the source is never written.
@MainActor
final class QuartzCheckoutImportTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    /// The day every case is read on, from the contract.
    var today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 23) ?? CalendarDay.today()

    // MARK: - Setting up

    /// A destination working folder under a throwaway root, with the trail
    /// redirected there too.
    func prepare() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("website-layout-\(UUID().uuidString)")
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
        if let day = try? QuartzCheckoutImportTests.contractDay() {
            today = day
        }
    }

    /// A website folder shaped like the real ICS3U S1: the program's files,
    /// `content/` made of links with relative text, an editing folder of
    /// links, section 2's pages, add-ons in `.obsidian`, a placeholder class
    /// page, and two pictures whose names are spelled the two ways an accent
    /// can be.
    @discardableResult
    func makeWebsite(at websiteURL: URL, marker: String = "S1's copy") throws -> URL {
        let program: URL = websiteURL.appendingPathComponent("quartz")
        let content: URL = program.appendingPathComponent("content")
        let pages: URL = content.appendingPathComponent("source-ics3u")

        try write("export default {}", to: program, "quartz.config.ts")
        try write("{}", to: program, "package.json")
        try write("<html></html>", to: program, "public/index.html")
        try write("build()", to: program, "quartz/build.ts")
        try write("finder", to: program, ".DS_Store")

        try write("{}", to: content, ".obsidian/app.json")
        try write("{\"theme\": \"minimal\"}", to: content, ".obsidian/appearance.json")
        try write("[\"publisher\"]", to: content, ".obsidian/community-plugins.json")
        try write("{\"token\": \"not-a-real-credential\"}", to: content, ".obsidian/plugins/publisher/data.json")

        try write("---\ntitle: Grade 11, Section 1\n---\n![[Thread 1, Day 2]]\n", to: pages, "s1/index.md")
        try write("# Key Links\n", to: pages, "s1/Key Links.md")
        try write("---\ndraft: true\n---\n# Private\n", to: pages, "s1/Private Notes.md")
        try write("# All\n", to: pages, "s1/All Classes/index.md")
        try write("---\ncreated: 2024-09-05\n---\n# Day 1\n", to: pages, "s1/All Classes/Thread 1, Day 1.md")
        try write("# Day 2\n![[Appétit.png]]\n", to: pages, "s1/All Classes/Thread 1, Day 2.md")
        try write("# placeholder\n", to: pages, "s1/All Classes/Thread 2, Day x.md")
        try write("# S2\n", to: pages, "s2/index.md")
        try write("---\ndraftSectionTwo: true\n---\n", to: pages, "s2/All Classes/Thread 1, Day 1.md")
        try write("# Lists — \(marker)\n", to: pages, "shared/Concepts/Lists.md")
        try write("# Goals\n", to: pages, "shared/Learning Goals.md")
        try write("finder", to: pages, "shared/.DS_Store")
        let media: URL = pages.appendingPathComponent("shared/Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try ReferenceTreeCopier.create(
            Data("composed picture".utf8), named: Array("App\u{00e9}tit.png".utf8), inFolderAt: media
        )
        try ReferenceTreeCopier.create(
            Data("decomposed picture".utf8), named: Array("Cre\u{0300}me.png".utf8), inFolderAt: media
        )

        let links: [(String, String)] = [
            ("index.md", "./source-ics3u/s1/index.md"),
            ("Key Links.md", "./source-ics3u/s1/Key Links.md"),
            ("Private Notes.md", "./source-ics3u/s1/Private Notes.md"),
            ("All Classes", "./source-ics3u/s1/All Classes"),
            ("Concepts", "./source-ics3u/shared/Concepts"),
            ("Learning Goals.md", "./source-ics3u/shared/Learning Goals.md"),
            ("Media", "./source-ics3u/shared/Media"),
        ]
        for (name, text) in links {
            try FileManager.default.createSymbolicLink(
                atPath: content.appendingPathComponent(name).path, withDestinationPath: text
            )
        }
        try write("{}", to: content, "vault-ics3u-s1/.obsidian/app.json")
        try FileManager.default.createSymbolicLink(
            atPath: content.appendingPathComponent("vault-ics3u-s1/Concepts").path,
            withDestinationPath: "../source-ics3u/shared/Concepts"
        )
        return websiteURL
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

    /// The one course a chosen folder offers ticked, imported under 2024,
    /// with the outcome asserted FIRST — a test about what is inside a
    /// course must not pass because no course was made.
    func importTheTicked(_ chosenURL: URL) async throws -> (outcome: ReferenceImporter.Outcome, courseURL: URL) {
        guard case .found(let source) = read(chosenURL) else {
            XCTFail("\(chosenURL.lastPathComponent) was refused.")
            throw WebsiteLayoutTestFailure.refused
        }
        var ticked: ReferenceImportSource.FoundCourse?
        for course in source.courses where source.tickedWhenOpened.contains(course.id) {
            ticked = course
        }
        let course: ReferenceImportSource.FoundCourse = try XCTUnwrap(ticked, "Nothing was ticked.")
        let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: course, schoolYear: 2024)],
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: [],
            from: source.rootURL,
            progress: { _ in }
        )
        let outcome: ReferenceImporter.Outcome = try XCTUnwrap(outcomes.first)
        switch outcome {
        case .imported(let made), .importedWithSomethingMissing(let made, _, _):
            return (outcome: outcome, courseURL: coursesDirectoryURL.appendingPathComponent(made.folderName))
        default:
            XCTFail("The class was not imported: \(outcomes)")
            throw WebsiteLayoutTestFailure.notImported
        }
    }

    // MARK: - The contract's cases

    func testRecognitionIsTheContractsCases() throws {
        let recognition: [String: Any] = try XCTUnwrap(try QuartzCheckoutImportTests.block()["recognition"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(recognition["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 31, "The contract's recognition cases did not load.")

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case")
            try build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)
            let chosenPath: String = try XCTUnwrap(testCase["choose"] as? String)
            var chosenURL: URL = caseURL
            if chosenPath != "." {
                chosenURL = caseURL.appendingPathComponent(chosenPath)
            }
            let expectation: String = try XCTUnwrap(testCase["expect"] as? String)

            switch read(chosenURL) {
            case .refused(let refusal):
                XCTAssertEqual(expectation, "refused", "\(name): refused, and the contract accepts it (\(refusal)).")
                XCTAssertEqual(QuartzCheckoutImportTests.name(of: refusal), testCase["refusal"] as? String, "\(name): the refusal")
                try QuartzCheckoutImportTests.checkRefusalDetails(refusal, against: testCase, in: name)
            case .found(let found):
                XCTAssertEqual(expectation, "accepted", "\(name): accepted, and the contract refuses it.")
                let expected: [[String: Any]] = try XCTUnwrap(testCase["expectCourses"] as? [[String: Any]])
                XCTAssertEqual(found.courses.count, expected.count, "\(name): how many rows")
                let skipYear: Bool = testCase["yearFromPages"] as? Bool == true
                var index: Int = 0
                for wanted in expected where index < found.courses.count {
                    try QuartzCheckoutImportTests.check(found.courses[index], against: wanted, skipYear: skipYear, in: name)
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

    func testTheYearIsTheContractsCases() throws {
        let recognition: [String: Any] = try XCTUnwrap(try QuartzCheckoutImportTests.block()["recognition"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(recognition["yearCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 3)
        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let websiteURL: URL = rootURL.appendingPathComponent("case")
                .appendingPathComponent(try XCTUnwrap(testCase["website"] as? String))
            try makeWebsite(at: websiteURL)
            let day: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(testCase["pagesChanged"] as? String)))
            try QuartzCheckoutImportTests.touchEveryFile(under: websiteURL, on: day)
            guard case .found(let source) = read(websiteURL), let course = source.courses.first else {
                XCTFail("\(name): refused")
                continue
            }
            XCTAssertEqual(course.suggestedSchoolYear, testCase["expectYear"] as? Int, "\(name): the year")
        }
    }

    func testTheClassPagesWordIsTheContractsCases() throws {
        let placement: [String: Any] = try XCTUnwrap(try QuartzCheckoutImportTests.block()["placement"] as? [String: Any])
        let unitWord: [String: Any] = try XCTUnwrap(placement["unitWord"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(unitWord["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for testCase in cases {
            let pages: [String] = try XCTUnwrap(testCase["pages"] as? [String])
            let found: (word: String?, placeholders: Int) = QuartzCheckoutLayout.unitWord(amongPageNames: pages)
            XCTAssertEqual(found.word, testCase["word"] as? String, "\(pages): the word")
            XCTAssertEqual(found.placeholders, testCase["placeholders"] as? Int, "\(pages): placeholders")
        }
    }

    func testPlacementIsTheContractsCases() async throws {
        let placement: [String: Any] = try XCTUnwrap(try QuartzCheckoutImportTests.block()["placement"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(placement["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 3)

        for testCase in cases {
            try prepare()
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let caseURL: URL = rootURL.appendingPathComponent("case")
            try build(tree: try XCTUnwrap(testCase["tree"] as? [Any]), at: caseURL)
            let websiteURL: URL = caseURL.appendingPathComponent(try XCTUnwrap(testCase["website"] as? String))
            let facts: QuartzCheckoutLayout.Facts = QuartzCheckoutLayout.facts(of: QuartzCheckoutLayout.Candidate(
                rowName: websiteURL.lastPathComponent, websiteURL: websiteURL, shortcutName: nil, trouble: nil, disk: nil
            ))
            let plan: QuartzCheckoutLayout.Plan = QuartzCheckoutLayout.plan(
                facts: facts, leavingBehind: ReferenceImporter.leftBehindNames
            )
            XCTAssertEqual(plan.unreadableFolders, [], "\(name): nothing should be unreadable")

            let contentPath: String = QuartzCheckoutLayout.contentURL(of: websiteURL).path + "/"
            var placed: [String: String] = [:]
            for entry in plan.placements where !entry.item.isDirectory {
                let full: String = entry.sourceRoot.path + "/" + entry.item.text
                placed[entry.destinationText] = String(full.dropFirst(contentPath.count))
            }
            XCTAssertEqual(placed, try XCTUnwrap(testCase["expectPlaced"] as? [String: String]), "\(name): where every file lands")

            // Left behind and lost, asserted SEPARATELY: an implementation
            // that lumps them cannot pass.
            let wantedBehind: [String: Int] = try XCTUnwrap(testCase["expectLeftBehind"] as? [String: Int])
            for kind in QuartzCheckoutLayout.LeftBehindKind.allCases {
                XCTAssertEqual(plan.leftBehind[kind] ?? 0, wantedBehind[kind.rawValue], "\(name): left behind, \(kind.rawValue)")
            }
            var lost: [String] = []
            for entry in plan.lost {
                lost.append("\(entry.path) | \(entry.reason.rawValue)")
            }
            lost.sort()
            var wantedLost: [String] = []
            for entry in try XCTUnwrap(testCase["expectLost"] as? [[String: Any]]) {
                wantedLost.append("\(try XCTUnwrap(entry["path"] as? String)) | \(try XCTUnwrap(entry["reason"] as? String))")
            }
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

            // And a real import of the same folder: complete exactly when
            // nothing is lost, whatever was left behind.
            let outcome: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
            if wantedLost.isEmpty {
                guard case .imported = outcome.outcome else {
                    return XCTFail("\(name): left behind was reported as missing: \(outcome.outcome)")
                }
            } else {
                guard case .importedWithSomethingMissing(_, false, let named) = outcome.outcome else {
                    return XCTFail("\(name): a loss was not reported: \(outcome.outcome)")
                }
                XCTAssertEqual(named.count, wantedLost.count, "\(name): every loss is named")
            }
            XCTAssertEqual(QuartzCheckoutImportTests.links(under: outcome.courseURL), [], "\(name): a link came across")
        }
    }

    // MARK: - What only a real import can prove

    /// `isAliasFileKey` is true for a symbolic link too, and resolving one
    /// FOLLOWS it. A link is never a shortcut — neither alone in a folder
    /// nor chosen on its own.
    func testASymlinkIsNeverTakenForAShortcut() throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let chosenURL: URL = rootURL.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: chosenURL, withIntermediateDirectories: true)
        let linkURL: URL = chosenURL.appendingPathComponent("S1")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: websiteURL.path)

        let values: URLResourceValues = try linkURL.resourceValues(forKeys: [.isAliasFileKey])
        XCTAssertEqual(values.isAliasFile, true, "The trap this test exists for: a link says it is an alias.")
        XCTAssertEqual(QuartzCheckoutLayout.shortcutTarget(of: linkURL), .notAShortcut)
        XCTAssertFalse(QuartzCheckoutLayout.isShortcut(linkURL))

        guard case .refused(.noCoursesThere) = read(chosenURL) else {
            return XCTFail("A folder holding only a link to a website folder was read through the link.")
        }

        // A real shortcut beside it IS read through.
        try QuartzCheckoutImportTests.makeShortcut(at: chosenURL.appendingPathComponent("S1 shortcut"), to: websiteURL)
        guard case .found(let source) = read(chosenURL) else {
            return XCTFail("A real shortcut was not read through.")
        }
        XCTAssertEqual(source.courses.count, 1)
        XCTAssertEqual(source.courses.first?.folderName, "S1 shortcut")
    }

    /// No link reaches a reference course, the census agrees AND is
    /// complete, and the file count is exact — so none of it can pass by a
    /// course having been made empty.
    func testNoLinkReachesAReferenceCourse() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
        guard case .imported = imported.outcome else {
            return XCTFail("The real shape was not imported complete: \(imported.outcome)")
        }
        let files: [String: Data] = try QuartzCheckoutImportTests.regularFiles(under: imported.courseURL)
        // .obsidian 2 + section 7 + shared 2 pages + 2 pictures + settings.
        XCTAssertEqual(files.count, 14, "Files out: \(files.keys.sorted())")
        XCTAssertEqual(QuartzCheckoutImportTests.links(under: imported.courseURL), [])

        let census: ReferenceLock.Census = ReferenceLock.census(courseDirectory: imported.courseURL)
        XCTAssertTrue(census.agrees, "\(census)")
        var ordinaryFiles: Int = 0
        for path in files.keys where !path.hasPrefix(".obsidian/") && path != "course_config.json" {
            ordinaryFiles += 1
        }
        XCTAssertEqual(census.shouldBeLocked, ordinaryFiles, "The census counted fewer files than are there.")
    }

    /// Every page and picture is the same bytes under the same name bytes,
    /// the front page included — it is already `index.md`, so nothing is
    /// renamed.
    func testEveryPageAndPictureIsTheSameBytesUnderTheSameName() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let pages: URL = websiteURL.appendingPathComponent("quartz/content/source-ics3u")
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
        let courseURL: URL = imported.courseURL
        let pairs: [(String, String)] = [
            ("section1/index.md", "s1/index.md"),
            ("section1/Key Links.md", "s1/Key Links.md"),
            ("section1/Private Notes.md", "s1/Private Notes.md"),
            ("section1/All Classes/Thread 1, Day 1.md", "s1/All Classes/Thread 1, Day 1.md"),
            ("section1/All Classes/Thread 1, Day 2.md", "s1/All Classes/Thread 1, Day 2.md"),
            ("section1/All Classes/Thread 2, Day x.md", "s1/All Classes/Thread 2, Day x.md"),
            ("Concepts/Lists.md", "shared/Concepts/Lists.md"),
            ("Learning Goals.md", "shared/Learning Goals.md"),
        ]
        for (destination, source) in pairs {
            XCTAssertEqual(
                try Data(contentsOf: courseURL.appendingPathComponent(destination)),
                try Data(contentsOf: pages.appendingPathComponent(source)),
                "\(destination) is not byte-identical to its source"
            )
        }
        let sourceNames: Set<[UInt8]> = Set(ReferenceTreeCopier.names(inFolderAt: pages.appendingPathComponent("shared/Media")))
        let copiedNames: Set<[UInt8]> = Set(ReferenceTreeCopier.names(inFolderAt: courseURL.appendingPathComponent("Media")))
        XCTAssertEqual(copiedNames, sourceNames, "A picture's name changed its bytes on the way in.")
        XCTAssertTrue(copiedNames.contains(Array("App\u{00e9}tit.png".utf8)))
        XCTAssertTrue(copiedNames.contains(Array("Cre\u{0300}me.png".utf8)))
    }

    /// Two website folders, both called S1, reached through two shortcuts,
    /// with different shared pages: each row carries ITS OWN folder's bytes,
    /// and section 2's pages never come across from either.
    func testTheCopyInsideTheFolderPointedAtIsTheOneUsed() async throws {
        try prepare()
        let older: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2023-24/ICS3U/S1"), marker: "older")
        let newer: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"), marker: "newer")
        let shortcuts: URL = rootURL.appendingPathComponent("Class Websites")
        try FileManager.default.createDirectory(at: shortcuts, withIntermediateDirectories: true)
        try QuartzCheckoutImportTests.makeShortcut(at: shortcuts.appendingPathComponent("Older"), to: older)
        try QuartzCheckoutImportTests.makeShortcut(at: shortcuts.appendingPathComponent("Newer"), to: newer)

        guard case .found(let source) = read(shortcuts) else {
            return XCTFail("The folder of shortcuts was refused.")
        }
        XCTAssertEqual(source.courses.count, 2)
        for course in source.courses {
            let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: course, schoolYear: course.suggestedSchoolYear)],
                into: coursesDirectoryURL,
                existingFolderNames: [],
                alreadyShelved: [],
                from: source.rootURL,
                progress: { _ in }
            )
            guard case .imported(let made) = try XCTUnwrap(outcomes.first) else {
                return XCTFail("\(course.folderName) was not imported: \(outcomes)")
            }
            let lists: String = try String(
                contentsOf: coursesDirectoryURL.appendingPathComponent(made.folderName)
                    .appendingPathComponent("Concepts/Lists.md"),
                encoding: .utf8
            )
            let expected: String = course.folderName == "Older" ? "older" : "newer"
            XCTAssertTrue(lists.contains(expected), "\(course.folderName) carried another folder's page: \(lists)")
            XCTAssertNil(OlderCourseLayout.kind(of: coursesDirectoryURL.appendingPathComponent(made.folderName)
                .appendingPathComponent("section2")))
        }
    }

    /// The program's files, the editing folder, section 2's pages, the
    /// add-ons and the replaced links are ALL absent from the course, and the
    /// import is still complete: machinery is not a loss.
    func testWhatIsLeftBehindIsNotALoss() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
        guard case .imported = imported.outcome else {
            return XCTFail("Something left behind by design was reported as missing: \(imported.outcome)")
        }
        let files: [String: Data] = try QuartzCheckoutImportTests.regularFiles(under: imported.courseURL)
        for path in files.keys {
            XCTAssertFalse(path.hasPrefix("quartz"), "\(path): a program file came across")
            XCTAssertFalse(path.hasPrefix("vault-"), "\(path): an editing folder came across")
            XCTAssertFalse(path.hasPrefix(".obsidian/plugins"), "\(path): an add-on came across")
            XCTAssertFalse(path.hasPrefix("source-"), "\(path): the pages folder came across whole")
            XCTAssertNil(files[path]?.range(of: Data("draftSectionTwo".utf8)), "\(path): section 2's page came across")
        }
        XCTAssertNil(files[".obsidian/community-plugins.json"])
        XCTAssertNil(files["public/index.html"])
        let appSettings: String = String(decoding: try XCTUnwrap(files[".obsidian/app.json"]), as: UTF8.self)
        XCTAssertTrue(appSettings.contains("defaultViewMode"), "Reading view was not set: \(appSettings)")
    }

    /// A link at the top of `content/` naming something that is not there
    /// is a LOSS: the summary names it, the trail names it, and the import is
    /// not called complete.
    func testALinkWithNoPageIsALossAndIsNamed() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        try FileManager.default.createSymbolicLink(
            atPath: websiteURL.appendingPathComponent("quartz/content/Curriculum").path,
            withDestinationPath: "./source-ics3u/shared/Curriculum"
        )
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
        guard case .importedWithSomethingMissing(let made, false, let lost) = imported.outcome else {
            return XCTFail("A page the site showed is missing and the import called itself complete: \(imported.outcome)")
        }
        XCTAssertEqual(lost, ["Curriculum"])
        XCTAssertEqual(
            ImportCoursesForReferenceSheet.line(for: imported.outcome),
            ReferenceImportWording.imported(
                course: made.displayCode, year: SchoolYear.label(forStartingYear: 2024), sections: 1
            ) + ". " + ReferenceImportWording.olderLayoutLeftOut(count: 1, names: ["Curriculum"])
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("lost 1: Curriculum"), "The trail does not name it: \(trail)")
    }

    /// The settings: one section, the class pages' word even with a
    /// placeholder page among them, and a frozen reference course.
    func testTheSettingsWritten() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(websiteURL)
        XCTAssertEqual(imported.courseURL.lastPathComponent, "ICS3U-2024")
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: imported.courseURL.appendingPathComponent("course_config.json")
        )
        XCTAssertTrue(configuration.keptForReference)
        XCTAssertEqual(configuration.referenceSchoolYear, 2024)
        XCTAssertEqual(configuration.courseCode, "ICS3U")
        XCTAssertEqual(configuration.values["course_name"] as? String, "ICS3U S1")
        XCTAssertEqual(configuration.values["section_numbers"] as? [Int], [1])
        XCTAssertEqual(configuration.values["unit_word"] as? String, "Thread")
        XCTAssertEqual(configuration.values["per_section_folders"] as? [String], ["All Classes"])
        XCTAssertEqual(configuration.values["per_section_files"] as? [String], ["Key Links.md", "Private Notes.md"])
        XCTAssertEqual(configuration.values["shared_folders"] as? [String], ["Concepts"])
        XCTAssertEqual(configuration.values["shared_files"] as? [String], ["Learning Goals.md"])
        XCTAssertFalse(configuration.includesCurriculumCoverage)
        XCTAssertEqual(configuration.values["include_curriculum_coverage"] as? Bool, false)
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath))
        XCTAssertTrue(ReferenceLock.isLocked(imported.courseURL.appendingPathComponent("section1/index.md")))
        XCTAssertTrue(ReferenceLock.isLocked(imported.courseURL.appendingPathComponent("Media/App\u{00e9}tit.png")))
    }

    /// The website folder AND the folder of shortcuts are exactly as they
    /// were: every entry's bytes, size, time, flags, link text — and the
    /// shortcut files' own bytes.
    func testTheSourceIsNeverWritten() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let shortcuts: URL = rootURL.appendingPathComponent("Class Websites")
        try FileManager.default.createDirectory(at: shortcuts, withIntermediateDirectories: true)
        try QuartzCheckoutImportTests.makeShortcut(at: shortcuts.appendingPathComponent("S1"), to: websiteURL)
        let documents: URL = rootURL.appendingPathComponent("Documents")
        let before: [String: String] = try QuartzCheckoutImportTests.manifest(of: documents)
        let shortcutsBefore: [String: String] = try QuartzCheckoutImportTests.manifest(of: shortcuts)

        let imported: (outcome: ReferenceImporter.Outcome, courseURL: URL) = try await importTheTicked(shortcuts)
        guard case .imported = imported.outcome else {
            return XCTFail("Nothing was imported, so nothing could have been written: \(imported.outcome)")
        }
        XCTAssertEqual(try QuartzCheckoutImportTests.manifest(of: documents), before, "The website folder changed.")
        XCTAssertEqual(try QuartzCheckoutImportTests.manifest(of: shortcuts), shortcutsBefore, "The shortcuts changed.")
    }

    /// Stopped before the first file: nothing of it is left.
    func testStoppingLeavesNothing() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        guard case .found(let source) = read(websiteURL), let course = source.courses.first else {
            return XCTFail("The website folder was refused.")
        }
        let coursesDirectoryURL: URL = self.coursesDirectoryURL
        let run: Task<[ReferenceImporter.Outcome], Never> = Task { @MainActor in
            return await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: course, schoolYear: 2024)],
                into: coursesDirectoryURL,
                existingFolderNames: [],
                alreadyShelved: [],
                from: source.rootURL,
                progress: { _ in }
            )
        }
        run.cancel()
        let outcomes: [ReferenceImporter.Outcome] = await run.value
        XCTAssertEqual(outcomes, [ReferenceImporter.Outcome.stopped])
        var leftovers: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: coursesDirectoryURL.path) where name != ".internal" {
            leftovers.append(name)
        }
        XCTAssertEqual(leftovers, [], "Something of the stopped class is still there.")
    }

    /// The new trail line: where from, through which shortcut, which
    /// section and how it was told, the word, what was left behind by kind
    /// and that nothing was lost. Names and counts only.
    func testTheTrailLine() async throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: rootURL.appendingPathComponent("Documents/2024-25/ICS3U/S1"))
        let shortcuts: URL = rootURL.appendingPathComponent("Class Websites")
        try FileManager.default.createDirectory(at: shortcuts, withIntermediateDirectories: true)
        try QuartzCheckoutImportTests.makeShortcut(at: shortcuts.appendingPathComponent("S1"), to: websiteURL)
        _ = try await importTheTicked(shortcuts)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("imported ICS3U for reference from S1 as ICS3U-2024"), "\(trail)")
        XCTAssertTrue(trail.contains("imported ICS3U section 1 from "), "\(trail)")
        XCTAssertTrue(trail.contains("(through the shortcut S1) as ICS3U-2024 — section told by its front page"), "\(trail)")
        XCTAssertTrue(trail.contains("; 13 files from source-ics3u; class pages called Thread (1 placeholder pages set aside)"), "\(trail)")
        XCTAssertTrue(trail.contains(
            "; left behind, not lost: the website's own program files (4), 7 links replaced by what they showed, "
            + "editing folders vault-ics3u-s1 (2), other sections s2 (2), Obsidian add-on entries (2); nothing lost"
        ), "\(trail)")
        XCTAssertFalse(trail.contains("Grade 11"), "A page's words reached the trail.")
        XCTAssertFalse(trail.contains("not-a-real-credential"))
    }

    /// A shortcut leading INTO the folder this window has open is shown and
    /// cannot be ticked: a copy of a folder into itself.
    func testAShortcutIntoTheOpenFolderIsNotTickable() throws {
        try prepare()
        let websiteURL: URL = try makeWebsite(at: workingFolderURL.appendingPathComponent("Old/S1"))
        let shortcuts: URL = rootURL.appendingPathComponent("Class Websites")
        try FileManager.default.createDirectory(at: shortcuts, withIntermediateDirectories: true)
        try QuartzCheckoutImportTests.makeShortcut(at: shortcuts.appendingPathComponent("S1"), to: websiteURL)
        guard case .found(let source) = read(shortcuts), let course = source.courses.first else {
            return XCTFail("The folder of shortcuts was refused.")
        }
        XCTAssertEqual(course.problem, ReferenceImportWording.insideTheFolderYouHaveOpen(folder: "S1"))
        XCTAssertEqual(source.tickedWhenOpened, [])
    }

    // MARK: - The sentences

    func testTheSentencesAreTheContractsSentences() throws {
        let wording: [String: Any] = try QuartzCheckoutImportTests.wordingRules()
        let pairs: [(String, String)] = [
            (ReferenceImportWording.checkoutLayoutReadFrom(place: "{place}"), "checkoutLayoutReadFrom"),
            (
                ReferenceImportWording.checkoutLayoutReadThroughShortcut(shortcut: "{shortcut}", place: "{place}"),
                "checkoutLayoutReadThroughShortcut"
            ),
            (ReferenceImportWording.checkoutLayoutOnlyPagesComeAcross, "checkoutLayoutOnlyPagesComeAcross"),
            (
                ReferenceImportWording.checkoutLayoutChooseTheWholeFolder(folder: "{folder}", website: "{website}"),
                "checkoutLayoutChooseTheWholeFolder"
            ),
            (ReferenceImportWording.checkoutLayoutChooseOneCourseAtATime(folder: "{folder}"), "checkoutLayoutChooseOneCourseAtATime"),
            (ReferenceImportWording.checkoutLayoutMoreThanOneCourse, "checkoutLayoutMoreThanOneCourse"),
            (ReferenceImportWording.checkoutLayoutWhichSection, "checkoutLayoutWhichSection"),
            (ReferenceImportWording.checkoutLayoutShortcutGone(shortcut: "{shortcut}"), "checkoutLayoutShortcutGone"),
            (
                ReferenceImportWording.checkoutLayoutShortcutCouldNotBeOpened(shortcut: "{shortcut}"),
                "checkoutLayoutShortcutCouldNotBeOpened"
            ),
            (
                ReferenceImportWording.checkoutLayoutShortcutOnADiskNotConnected(shortcut: "{shortcut}", disk: "{disk}"),
                "checkoutLayoutShortcutOnADiskNotConnected"
            ),
            (ReferenceImportWording.checkoutLayoutShortcutToAFile(shortcut: "{shortcut}"), "checkoutLayoutShortcutToAFile"),
        ]
        for (sentence, key) in pairs {
            XCTAssertEqual(sentence, wording[key] as? String, key)
        }
        XCTAssertEqual(
            ReferenceImportWording.checkoutLayoutOnlyTheFirstSection(folder: "{folder}", section: 7),
            (wording["checkoutLayoutOnlyTheFirstSection"] as? String)?.replacingOccurrences(of: "{section}", with: "7")
        )
    }

    /// Rule 1 for the new sentences: "shortcut" is the one word allowed
    /// about how the folders were joined.
    func testNoNewSentenceNamesTheMachinery() throws {
        let wording: [String: Any] = try QuartzCheckoutImportTests.wordingRules()
        let forbidden: [String] = [
            "symlink", "link", "alias", "vault", "checkout", "quartz", "plugin", "script", "container", "toolchain",
        ]
        var checked: Int = 0
        for (key, value) in wording where key.hasPrefix("checkoutLayout") && key != "checkoutLayoutRule" {
            let sentence: String = try XCTUnwrap(value as? String)
            for word in forbidden {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(key) says “\(word)”")
            }
            checked += 1
        }
        XCTAssertEqual(checked, 12, "The new sentences did not load.")
    }

    // MARK: - Helpers

    private func write(_ text: String, to folderURL: URL, _ relative: String) throws {
        let fileURL: URL = URL(fileURLWithPath: folderURL.path + "/" + relative)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    /// A real Finder shortcut, the way Finder's Make Alias writes one.
    static func makeShortcut(at shortcutURL: URL, to targetURL: URL) throws {
        let data: Data = try targetURL.bookmarkData(
            options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        try FileManager.default.createDirectory(
            at: shortcutURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try URL.writeBookmarkData(data, to: shortcutURL)
    }

    /// Builds a contract tree: see `quartzCheckoutLayout.treeEntries`.
    private func build(tree: [Any], at folderURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var links: [[String: Any]] = []
        var shortcuts: [[String: Any]] = []
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
                    try JSONSerialization.data(withJSONObject: ["course_code": code, "section_numbers": [1]])
                        .write(to: fileURL)
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
            if described["alias"] != nil {
                shortcuts.append(described)
                continue
            }
            let path: String = try XCTUnwrap(described["file"] as? String)
            let fileURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(((described["text"] as? String) ?? "something").utf8).write(to: fileURL)
        }
        for described in links {
            let path: String = try XCTUnwrap(described["link"] as? String)
            let linkURL: URL = folderURL.appendingPathComponent(path)
            try fileManager.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var target: String = "/nowhere-\(UUID().uuidString)/\(path)"
            if let text = described["text"] as? String {
                target = text
            } else if let to = described["to"] as? String {
                target = folderURL.appendingPathComponent(to).path
            }
            try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: target)
        }
        for described in shortcuts {
            let path: String = try XCTUnwrap(described["alias"] as? String)
            let shortcutURL: URL = folderURL.appendingPathComponent(path)
            if let to = described["to"] as? String {
                try QuartzCheckoutImportTests.makeShortcut(at: shortcutURL, to: folderURL.appendingPathComponent(to))
            } else {
                // A folder that existed when the shortcut was made, and then
                // went.
                let gone: URL = folderURL.appendingPathComponent("gone-\(UUID().uuidString)")
                try fileManager.createDirectory(at: gone, withIntermediateDirectories: true)
                try QuartzCheckoutImportTests.makeShortcut(at: shortcutURL, to: gone)
                try fileManager.removeItem(at: gone)
            }
            if let lock = described["thenLock"] as? String {
                let lockURL: URL = folderURL.appendingPathComponent(lock)
                // Given back before the tree is removed: teardown blocks run
                // last-registered first.
                addTeardownBlock {
                    _ = chmod(lockURL.path, 0o755)
                }
                XCTAssertEqual(chmod(lockURL.path, 0), 0)
            }
        }
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

    private static func block() throws -> [String: Any] {
        return try XCTUnwrap(
            try QuartzCheckoutImportTests.contractRules()["quartzCheckoutLayout"] as? [String: Any],
            "No referenceCourses.importing.quartzCheckoutLayout in shared-rules.json"
        )
    }

    private static func wordingRules() throws -> [String: Any] {
        return try XCTUnwrap(try QuartzCheckoutImportTests.contractRules()["wording"] as? [String: Any])
    }

    private static func contractDay() throws -> CalendarDay {
        let text: String = try XCTUnwrap(try QuartzCheckoutImportTests.block()["today"] as? String)
        return try XCTUnwrap(CalendarDay(text: text))
    }

    /// One found row against one of the contract's `expectCourses`.
    private static func check(
        _ course: ReferenceImportSource.FoundCourse,
        against wanted: [String: Any],
        skipYear: Bool,
        in name: String
    ) throws {
        XCTAssertEqual(course.folderName, wanted["row"] as? String, "\(name): the row")
        if let route = wanted["route"] as? String {
            XCTAssertNil(course.checkoutLayout, "\(name): read as a class website")
            XCTAssertEqual(course.olderLayout != nil, route == "olderLayout", "\(name): which route")
            return
        }
        let facts: QuartzCheckoutLayout.Facts = try XCTUnwrap(course.checkoutLayout, "\(name): not read as a class website")
        XCTAssertEqual(course.courseCode, wanted["code"] as? String, "\(name): the code")
        XCTAssertEqual(facts.section, wanted["section"] as? Int, "\(name): the section")
        XCTAssertEqual(facts.sectionFrom?.rawValue, wanted["sectionFrom"] as? String, "\(name): how the section was told")
        XCTAssertEqual(facts.shortcutName, wanted["shortcut"] as? String, "\(name): the shortcut")
        if !skipYear {
            XCTAssertEqual(course.suggestedSchoolYear, wanted["year"] as? Int, "\(name): \(course.folderName)'s year")
        }
        if let key = wanted["problem"] as? String {
            XCTAssertEqual(
                course.problem,
                QuartzCheckoutImportTests.sentence(forKey: key, row: course.folderName, section: facts.section),
                "\(name): the problem"
            )
        } else {
            XCTAssertNil(course.problem, "\(name): \(course.folderName) has a problem: \(course.problem ?? "")")
        }
    }

    private static func sentence(forKey key: String, row: String, section: Int?) -> String? {
        switch key {
        case "checkoutLayoutOnlyTheFirstSection":
            return ReferenceImportWording.checkoutLayoutOnlyTheFirstSection(folder: row, section: section ?? 0)
        case "checkoutLayoutShortcutGone":
            return ReferenceImportWording.checkoutLayoutShortcutGone(shortcut: row)
        case "checkoutLayoutShortcutCouldNotBeOpened":
            return ReferenceImportWording.checkoutLayoutShortcutCouldNotBeOpened(shortcut: row)
        case "checkoutLayoutMoreThanOneCourse":
            return ReferenceImportWording.checkoutLayoutMoreThanOneCourse
        case "checkoutLayoutWhichSection":
            return ReferenceImportWording.checkoutLayoutWhichSection
        default:
            return nil
        }
    }

    private static func checkRefusalDetails(
        _ refusal: ReferenceImportSource.Refusal,
        against testCase: [String: Any],
        in name: String
    ) throws {
        switch refusal {
        case .partOfAClassWebsite(let folderName, let websiteName):
            XCTAssertEqual(folderName, testCase["refusalFolder"] as? String, "\(name): the folder named")
            XCTAssertEqual(websiteName, testCase["refusalWebsite"] as? String, "\(name): the website folder named")
        case .onlyTheFirstSection(let folderName, let section):
            XCTAssertEqual(folderName, testCase["refusalFolder"] as? String, "\(name): the folder named")
            XCTAssertEqual(section, testCase["refusalSection"] as? Int, "\(name): the section named")
        case .severalClassWebsiteCourses(let folderName):
            XCTAssertEqual(folderName, testCase["refusalFolder"] as? String, "\(name): the folder named")
        case .shortcutTrouble(let shortcut, _, _):
            XCTAssertEqual(shortcut, testCase["refusalShortcut"] as? String, "\(name): the shortcut named")
        default:
            break
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
        case .shortcutTrouble(_, let trouble, _):
            switch trouble {
            case .gone:
                return "checkoutLayoutShortcutGone"
            case .couldNotBeOpened:
                return "checkoutLayoutShortcutCouldNotBeOpened"
            case .diskNotConnected:
                return "checkoutLayoutShortcutOnADiskNotConnected"
            case .leadsToAFile:
                return "checkoutLayoutShortcutToAFile"
            }
        }
    }

    /// Sets every file's modification time to noon on a day.
    private static func touchEveryFile(under folderURL: URL, on day: CalendarDay) throws {
        var components: DateComponents = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        let moment: Date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: folderURL, leavingBehind: [])
        for item in survey.items where !item.isDirectory && !item.isSymbolicLink {
            let url: URL = ReferenceTreeCopier.url(named: item.relativePath, inFolderAt: folderURL)
            try FileManager.default.setAttributes([.modificationDate: moment], ofItemAtPath: url.path)
        }
    }

    /// Every regular file under a folder, by relative path, with its bytes.
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
    /// with its mode, size, times, flags, contents and link text.
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
enum WebsiteLayoutTestFailure: Error {
    case refused
    case notImported
}
