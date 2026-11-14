import XCTest
@testable import QuartzTeachers

/// Restore from Backup…'s "Restore Section N" for a backup made for one
/// section (#897, piece C), and the staged swap the assistant window's
/// "Restore Section N…" now shares (Russell's ruling on #897, 2026-11-13).
///
/// Each test is one of the faults that reported success before: another
/// section's work coming back, a section half old and half new, a section
/// emptied by a failure part way, and a shared page made after the backup
/// left published to the section.
final class OneSectionRestoreTests: XCTestCase {

    // MARK: - Only this section comes back

    /// Section 1's folder and Section 1's keys on a shared page stay byte for
    /// byte as they are now; Section 2's come back from the backup.
    @MainActor
    func testOnlySectionTwoComesBackAndSectionOneIsLeftByteForByte() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()

        // The evening's marking in Section 1, and a ruined Section 2.
        try "Section one, marked tonight.".write(to: fixture.page(in: 1), atomically: true, encoding: .utf8)
        try "ruined".write(to: fixture.page(in: 2), atomically: true, encoding: .utf8)
        let outlineNow: String = """
        ---
        title: Course Outline
        publishForSection1: false
        publishForSection2: true
        ---
        The outline every section shares.
        """
        try outlineNow.write(to: fixture.outlineURL, atomically: true, encoding: .utf8)
        let sectionOneBefore: [String: Data] = try OneSectionFixture.snapshot(of: fixture.sectionURL(1))

        _ = try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertEqual(try OneSectionFixture.snapshot(of: fixture.sectionURL(1)), sectionOneBefore,
                       "Section 1's folder is byte for byte what it was")
        XCTAssertEqual(try String(contentsOf: fixture.page(in: 2), encoding: .utf8), OneSectionFixture.sectionPage(2))
        let outlineAfter: String = try String(contentsOf: fixture.outlineURL, encoding: .utf8)
        XCTAssertTrue(outlineAfter.contains("publishForSection1: false"), "Section 1's key is the live one")
        XCTAssertTrue(outlineAfter.contains("publishForSection2: false"), "Section 2's key is the backup's")
    }

    // MARK: - The files outside the section's folder

    /// After a rollover sets the record aside and the dates move, the
    /// pre-rollover backup puts back the class dates and the published
    /// record; a file the backup had none of goes away.
    @MainActor
    func testTheClassDatesAndThePublishedRecordComeBackFromBeforeARollover() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let timetable: URL = fixture.outside(".internal/timetable/section2.json")
        let record: URL = fixture.outside(".publish_state/section2.published-pages")
        try fixture.write("{\"days\":[\"2025-09-03\"]}", to: timetable)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
        try fixture.write("{\"places\":[\"Unit 1, Day 1\"]}", to: record.appendingPathComponent("a.json"))
        let item: BackupItem = try await fixture.backUp()

        // The rollover: this year's dates, the record set aside, and an
        // answer the backup never had.
        try fixture.write("{\"days\":[\"2026-09-02\"]}", to: timetable)
        try FileManager.default.removeItem(at: record)
        let notToday: URL = fixture.outside(".publish_state/section2.front-page-not-today.json")
        try fixture.write("{\"day\":\"2026-09-02\",\"class\":\"x\"}", to: notToday)

        _ = try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertEqual(try String(contentsOf: timetable, encoding: .utf8), "{\"days\":[\"2025-09-03\"]}")
        XCTAssertEqual(
            try String(contentsOf: record.appendingPathComponent("a.json"), encoding: .utf8),
            "{\"places\":[\"Unit 1, Day 1\"]}"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: notToday.path),
                       "A file the backup had none of is removed")
    }

    /// The deploy stamp and the website markers describe the live site and
    /// stay; the links checklist offer goes with the built site; and the
    /// finished line is told the website record differs.
    @MainActor
    func testTheWebsiteRecordsStayAndTheChecklistOfferGoes() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()
        let marker: URL = fixture.outside(".netlify_sites/section2.json")
        let stamp: URL = fixture.outside(".publish_state/section2.json")
        let offer: URL = fixture.outside(".publish_state/section2.links-checklist.json")
        try fixture.write("{\"site_id\":\"made-after\"}", to: marker)
        try fixture.write("{\"at\":\"now\"}", to: stamp)
        try fixture.write("{}", to: offer)

        let outcome: OneSectionRestore.Outcome = try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "{\"site_id\":\"made-after\"}")
        XCTAssertEqual(try String(contentsOf: stamp, encoding: .utf8), "{\"at\":\"now\"}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: offer.path))
        XCTAssertTrue(outcome.websiteRecordDiffers)
    }

    // MARK: - A failure never empties the section

    /// Stopped between staging and the swap: nothing in the course has moved,
    /// and the staging folder is gone.
    @MainActor
    func testARestoreInterruptedBetweenStagingAndTheSwapLeavesTheSectionAsItWas() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()
        try "tonight's work".write(to: fixture.page(in: 2), atomically: true, encoding: .utf8)
        let before: [String: Data] = try OneSectionFixture.snapshot(of: fixture.courseURL)

        let hooks: CourseRestorer.SectionSwapHooks = CourseRestorer.SectionSwapHooks(
            move: { (source: URL, destination: URL) throws in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            reached: { (point: CourseRestorer.SwapPoint) throws in
                if point == .staged {
                    throw OneSectionFixture.Stop.here
                }
            }
        )
        XCTAssertThrowsError(try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks
        ))

        XCTAssertEqual(try OneSectionFixture.snapshot(of: fixture.courseURL), before)
        XCTAssertEqual(fixture.leftInRestoring(), 0, "Nothing is left staged")
    }

    /// A move that fails part way through the swap sends every moved file
    /// back: the section, and the files outside it, are as they were.
    @MainActor
    func testAMoveThatFailsPartWayLeavesTheSectionAsItWas() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        try fixture.write("{\"days\":[\"2025-09-03\"]}", to: fixture.outside(".internal/timetable/section2.json"))
        let item: BackupItem = try await fixture.backUp()
        try "tonight's work".write(to: fixture.page(in: 2), atomically: true, encoding: .utf8)
        try "another".write(to: fixture.sectionURL(2).appendingPathComponent("second.md"), atomically: true, encoding: .utf8)
        try fixture.write("{\"days\":[\"2026-09-02\"]}", to: fixture.outside(".internal/timetable/section2.json"))
        let before: [String: Data] = try OneSectionFixture.snapshot(of: fixture.courseURL)

        let counter: OneSectionFixture.MoveCounter = OneSectionFixture.MoveCounter(failFrom: 4, failUntil: 4)
        XCTAssertThrowsError(try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: counter.hooks
        )) { (error: Error) in
            guard case CourseRestorer.Problem.sectionLeftAsItWas(2, _) = error else {
                XCTFail("Expected sectionLeftAsItWas, got \(error)")
                return
            }
        }

        XCTAssertEqual(try OneSectionFixture.snapshot(of: fixture.courseURL), before)
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// When sending things back fails too, nothing is deleted: what the
    /// section held is kept aside, and the teacher is told.
    @MainActor
    func testAWayBackThatCannotFinishDeletesNothing() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()
        try "tonight's work".write(to: fixture.page(in: 2), atomically: true, encoding: .utf8)

        // The first move (the live page out) works; every move after fails.
        let counter: OneSectionFixture.MoveCounter = OneSectionFixture.MoveCounter(failFrom: 2, failUntil: Int.max)
        XCTAssertThrowsError(try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: counter.hooks
        )) { (error: Error) in
            guard case CourseRestorer.Problem.sectionRestoreStoppedPartWay(2) = error else {
                XCTFail("Expected sectionRestoreStoppedPartWay, got \(error)")
                return
            }
        }
        XCTAssertTrue(fixture.restoringHolds(text: "tonight's work"),
                      "The live page is kept in courses/.internal/restoring")
    }

    /// The assistant window's restore shares the swap (Russell's ruling):
    /// a failed move leaves its section as it was too, and on success it
    /// brings back the folder alone, as before.
    @MainActor
    func testTheWindowsRestoreIsStagedAndOtherwiseUnchanged() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let timetable: URL = fixture.outside(".internal/timetable/section2.json")
        try fixture.write("{\"days\":[\"2025-09-03\"]}", to: timetable)
        let item: BackupItem = try await fixture.backUp()
        try "tonight's work".write(to: fixture.page(in: 2), atomically: true, encoding: .utf8)
        try fixture.write("{\"days\":[\"2026-09-02\"]}", to: timetable)
        let madeSince: URL = fixture.courseURL.appendingPathComponent("Made Since.md")
        try "---\ntitle: Made Since\n---\nNew.".write(to: madeSince, atomically: true, encoding: .utf8)
        let before: [String: Data] = try OneSectionFixture.snapshot(of: fixture.courseURL)

        let counter: OneSectionFixture.MoveCounter = OneSectionFixture.MoveCounter(failFrom: 2, failUntil: 2)
        XCTAssertThrowsError(try CourseRestorer.restoreSection(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: counter.hooks
        ))
        XCTAssertEqual(try OneSectionFixture.snapshot(of: fixture.courseURL), before,
                       "The window's failed restore leaves the section as it was")

        try CourseRestorer.restoreSection(2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)
        XCTAssertEqual(try String(contentsOf: fixture.page(in: 2), encoding: .utf8), OneSectionFixture.sectionPage(2))
        XCTAssertEqual(try String(contentsOf: timetable, encoding: .utf8), "{\"days\":[\"2026-09-02\"]}",
                       "The window's restore leaves the class dates as they are, as it always has")
        XCTAssertEqual(try String(contentsOf: madeSince, encoding: .utf8), "---\ntitle: Made Since\n---\nNew.",
                       "The window's restore leaves a page made since alone, as it always has")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    // MARK: - A shared page made since the backup

    /// Three shapes of a page the backup does not have: one already hidden
    /// for Section 2 by its own key (left byte for byte, never published),
    /// one hidden by its plain line but published for Section 2, and one
    /// with no keys at all. The last two are hidden from Section 2 and still
    /// shown to Section 1.
    @MainActor
    func testASharedPageMadeSinceTheBackupIsHiddenFromTheSection() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()
        let hiddenByItsKey: String = "---\ntitle: A\npublish: true\npublishForSection2: false\n---\nA."
        let publishedByItsKey: String = "---\ntitle: B\npublish: false\npublishForSection2: true\n---\nB."
        let saysNothing: String = "---\ntitle: C\n---\nC."
        let urlA: URL = fixture.courseURL.appendingPathComponent("Reference/A.md")
        let urlB: URL = fixture.courseURL.appendingPathComponent("Reference/B.md")
        let urlC: URL = fixture.courseURL.appendingPathComponent("C.md")
        try hiddenByItsKey.write(to: urlA, atomically: true, encoding: .utf8)
        try publishedByItsKey.write(to: urlB, atomically: true, encoding: .utf8)
        try saysNothing.write(to: urlC, atomically: true, encoding: .utf8)

        let outcome: OneSectionRestore.Outcome = try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertEqual(try String(contentsOf: urlA, encoding: .utf8), hiddenByItsKey,
                       "Taking its key off would have PUBLISHED it (amendment 18)")
        let afterB: String = try String(contentsOf: urlB, encoding: .utf8)
        let afterC: String = try String(contentsOf: urlC, encoding: .utf8)
        XCTAssertEqual(AssistPageVisibility.answer(in: afterB, forSection: 2), .hidden)
        XCTAssertEqual(AssistPageVisibility.answer(in: afterC, forSection: 2), .hidden)
        XCTAssertTrue(AssistPageVisibility.publishes(in: afterC, forSection: 1), "Section 1 still sees it")
        XCTAssertEqual(outcome.pagesMadeSinceHidden, 2)
    }

    // MARK: - Refusals

    /// The course's word for a unit changed since the backup: refused, and
    /// nothing moves.
    @MainActor
    func testARestoreIsRefusedWhenTheCoursesNamingChanged() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()
        try fixture.writeConfig(unitWord: "Module")
        let before: [String: Data] = try OneSectionFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreSectionFromTheMenu(
            2, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )) { (error: Error) in
            guard case CourseRestorer.Problem.namingChangedSinceTheBackup("ICS3U", 2) = error else {
                XCTFail("Expected namingChangedSinceTheBackup, got \(error)")
                return
            }
        }
        XCTAssertEqual(try OneSectionFixture.snapshot(of: fixture.courseURL), before)
    }

    // MARK: - What the alert reads from a zip

    /// The zip's listing says which section folders it holds, and its
    /// settings file its naming, without unpacking anything else.
    @MainActor
    func testTheBackupsFactsAreReadFromItsListing() async throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try await fixture.backUp()

        let facts: OneSectionRestore.BackupFacts = try XCTUnwrap(OneSectionRestore.readFacts(ofBackupAt: item.fileURL))
        XCTAssertEqual(facts.sectionsInside, [1, 2])
        XCTAssertEqual(facts.naming, OneSectionRestore.Naming(word: "Unit", scheme: "unit_day", classFolder: "All Classes"))
    }

    /// Each path in the list is the one the file's owner writes, so a file
    /// that moves cannot leave the restore pointing at nothing.
    @MainActor
    func testTheListNamesTheSameFilesTheirOwnersDo() throws {
        let fixture: OneSectionFixture = try OneSectionFixture()
        defer { fixture.tearDown() }
        let course: Course = fixture.course
        let directory: URL = course.directoryURL
        var expected: [String] = [
            SectionTimetableStore.fileURL(forSection: 2, in: course).path,
            PublishedPagesRecord.folderURL(courseDirectory: directory, section: 2).path,
            LinksChecklistAnswered.fileURL(courseDirectory: directory, section: 2).path,
            ClassesDatedLater.KeptRecord.fileURL(courseDirectory: directory, section: 2).path,
            TodaysClassOnTheFrontPage.NotToday.fileURL(courseDirectory: directory, section: 2).path,
            LinksChecklistOffer.fileURL(courseDirectory: directory, section: 2).path,
            SectionPublishState.stampURL(courseDirectory: directory, sectionNumber: 2).path,
        ]
        for destinationType in ["netlify", "cloudflare_pages"] {
            if let marker = DeployCommand.firstDeployMarkerURL(forSection: 2, in: course, destinationType: destinationType) {
                expected.append(marker.path)
            }
        }
        var listed: [String] = []
        for file in OneSectionRestore.filesOutsideTheSection {
            listed.append(directory.appendingPathComponent(file.path(forSection: 2)).path)
        }
        XCTAssertEqual(listed, expected)
    }

    /// The trail line names the backup, the archive and a count, never a page.
    @MainActor
    func testTheTrailLineNamesFilesAndACount() {
        XCTAssertEqual(
            ActivityTrail.restoredOneSectionFromTheMenuLine(
                backupFileName: "ICS3U_backup_2026-11-13_201500_menu-section2.zip",
                archiveFileName: "ICS3U_2026-11-13_210000.zip",
                pagesMadeSinceHidden: 2
            ),
            "put the section back from ICS3U_backup_2026-11-13_201500_menu-section2.zip, from Restore from Backup…; "
                + "the course as it was is in Archived as ICS3U_2026-11-13_210000.zip; "
                + "2 shared pages made since the backup are now hidden from this section"
        )
    }
}

/// A course with two sections, a shared outline and a shared folder, backed
/// up by the Section menu before a change to Section 2.
@MainActor
final class OneSectionFixture {

    // MARK: - Types

    enum Stop: Error {
        case here
        case failedMove
    }

    /// Counts moves and fails the ones in `failFrom...failUntil` (1-based).
    @MainActor
    final class MoveCounter {

        // MARK: - Stored properties

        let failFrom: Int
        let failUntil: Int
        var count: Int = 0

        // MARK: - Computed properties

        var hooks: CourseRestorer.SectionSwapHooks {
            return CourseRestorer.SectionSwapHooks(
                move: { (source: URL, destination: URL) throws in
                    self.count += 1
                    if self.count >= self.failFrom && self.count <= self.failUntil {
                        throw Stop.failedMove
                    }
                    try FileManager.default.moveItem(at: source, to: destination)
                },
                reached: { (_: CourseRestorer.SwapPoint) throws in
                }
            )
        }

        // MARK: - Initializer

        init(failFrom: Int, failUntil: Int) {
            self.failFrom = failFrom
            self.failUntil = failUntil
        }
    }

    // MARK: - Stored properties

    let coursesDirectoryURL: URL
    let courseURL: URL
    var course: Course

    // MARK: - Computed properties

    var outlineURL: URL {
        return courseURL.appendingPathComponent("Course Outline.md")
    }

    // MARK: - Initializer

    init() throws {
        let fileManager: FileManager = FileManager.default
        let workingFolder: URL = fileManager.temporaryDirectory
            .appendingPathComponent("one-section-restore-\(UUID().uuidString)")
        coursesDirectoryURL = workingFolder.appendingPathComponent("courses")
        courseURL = coursesDirectoryURL.appendingPathComponent("ICS3U")
        for number in [1, 2] {
            let folder: URL = courseURL.appendingPathComponent("section\(number)")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try OneSectionFixture.sectionPage(number).write(
                to: folder.appendingPathComponent("index.md"), atomically: true, encoding: .utf8
            )
        }
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Reference"), withIntermediateDirectories: true
        )
        let outline: String = """
        ---
        title: Course Outline
        publishForSection1: true
        publishForSection2: false
        ---
        The outline every section shares.
        """
        try outline.write(to: courseURL.appendingPathComponent("Course Outline.md"), atomically: true, encoding: .utf8)
        course = Course(
            code: "ICS3U",
            directoryURL: courseURL,
            configuration: CourseConfiguration(values: [:], lastSavedData: Data())
        )
        try writeConfig(unitWord: nil)
    }

    // MARK: - Functions

    static func sectionPage(_ number: Int) -> String {
        return "---\ntitle: Section \(number)\npublish: true\n---\nSection \(number)'s landing page."
    }

    func writeConfig(unitWord: String?) throws {
        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "One Section Restore Test Course",
            "section_numbers": [1, 2],
            "per_section_folders": ["All Classes"],
        ]
        if let unitWord {
            values["unit_word"] = unitWord
        }
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        course = Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: CourseConfiguration(values: values, lastSavedData: data)
        )
    }

    func sectionURL(_ number: Int) -> URL {
        return courseURL.appendingPathComponent("section\(number)")
    }

    func page(in section: Int) -> URL {
        return sectionURL(section).appendingPathComponent("index.md")
    }

    func outside(_ relativePath: String) -> URL {
        return courseURL.appendingPathComponent(relativePath)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The copy the Section menu saves before changing Section 2.
    func backUp() async throws -> BackupItem {
        let backupURL: URL = try await CourseArchiver.backUpCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .menu(sectionNumber: 2)
        )
        return try XCTUnwrap(BackupItem.from(fileURL: backupURL, courseCode: "ICS3U"))
    }

    /// How many restores are still staged under `courses/.internal/restoring`.
    func leftInRestoring() -> Int {
        let folder: URL = coursesDirectoryURL.appendingPathComponent(".internal/restoring")
        let entries: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: []
        )) ?? []
        return entries.count
    }

    /// Whether any file kept under `courses/.internal/restoring` holds this text.
    func restoringHolds(text: String) -> Bool {
        let folder: URL = coursesDirectoryURL.appendingPathComponent(".internal/restoring")
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            return false
        }
        while let entry = walker.nextObject() as? URL {
            if let contents = try? String(contentsOf: entry, encoding: .utf8), contents == text {
                return true
            }
        }
        return false
    }

    /// Every file under a folder, by relative path, with its bytes.
    static func snapshot(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let rootPath: String = folder.standardizedFileURL.path + "/"
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return result
        }
        while let entry = walker.nextObject() as? URL {
            let values: URLResourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                continue
            }
            let path: String = entry.standardizedFileURL.path
            result[String(path.dropFirst(rootPath.count))] = try Data(contentsOf: entry)
        }
        return result
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: coursesDirectoryURL.deletingLastPathComponent())
    }
}
