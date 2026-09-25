import XCTest
@testable import QuartzTeachers

/// Runs `contracts/course-management.json` — the names a course's files carry,
/// and the rules for adding a section.
///
/// **Why the naming grammar has to be shared rather than described.** The two
/// apps list each other's files. A course backed up on a Mac and opened on
/// Windows must appear in the Backups list; a parser rewritten from memory on
/// the other side makes it vanish, and a teacher looking for the copy they
/// made before a risky edit finds nothing. Worse in the other direction: an
/// archive that reads as a backup is a teacher restoring the wrong thing.
@MainActor
final class CourseManagementContractTests: XCTestCase {

    // MARK: - Three kinds of zip, told apart by name

    func testTheZipNamesAreReadAsTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("zipNames")
        let code: String = try XCTUnwrap(section["courseCode"] as? String)
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("names")

        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let kind: String = try XCTUnwrap(testCase["kind"] as? String)
            let url: URL = folder.appendingPathComponent(name)

            let backup: BackupItem? = BackupItem.from(fileURL: url, courseCode: code)
            let archive: ArchivedItem? = ArchivedItem.from(fileURL: url, courseCode: code)

            switch kind {
            case "backup":
                XCTAssertNotNil(backup, "\(name) should be read as a backup")
                XCTAssertNil(archive, "\(name) must NOT also read as an archive")
                CourseManagementContractTests.assertMoment(backup?.backedUpAt, is: testCase["moment"] as? String, in: name)
                if let expectedSection = testCase["section"] as? Int {
                    XCTAssertEqual(
                        backup?.maker, .assistant(sectionNumber: expectedSection),
                        "\(name): the assistant's own backups say so in the name"
                    )
                } else if testCase["maker"] as? String == "teacher" {
                    XCTAssertEqual(backup?.maker, .teacher, name)
                }
            case "archive":
                XCTAssertNotNil(archive, "\(name) should be read as an archive")
                XCTAssertNil(backup, "\(name) must NOT also read as a backup")
                XCTAssertEqual(archive?.sectionNumber, testCase["section"] as? Int, name)
                CourseManagementContractTests.assertMoment(archive?.archivedAt, is: testCase["moment"] as? String, in: name)
            default:
                XCTAssertNil(backup, "\(name) must not be read as a backup")
                XCTAssertNil(archive, "\(name) must not be read as an archive")
            }
        }
    }

    /// The moment a name is read as, checked against the contract.
    ///
    /// **Taken apart with a GREGORIAN calendar, and never re-spelled with the
    /// app's own writer.** Asking `ArchiveStamp.text(for:)` to spell the date
    /// back out and comparing THAT would be a round trip: it stays green
    /// while the reader and the writer are wrong together, which is exactly
    /// the state issue #160 found them in. Asking `Calendar.current` would be
    /// worse again — on a Buddhist-calendar Mac it renders 2026 CE as 2569
    /// and the test agrees with the bug.
    private static func assertMoment(_ read: Date?, is expected: String?, in name: String) {
        guard let expected else {
            return
        }
        guard let read else {
            XCTFail("\(name) was not read at all, so it has no moment")
            return
        }
        var gregorian: Calendar = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone.current
        let pieces: DateComponents = gregorian.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: read
        )
        let spelled: String = String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            pieces.year ?? 0, pieces.month ?? 0, pieces.day ?? 0,
            pieces.hour ?? 0, pieces.minute ?? 0, pieces.second ?? 0
        )
        XCTAssertEqual(spelled, expected, "\(name) is stamped with a moment the contract does not agree with")
    }

    // MARK: - Whether a stamp could be true

    /// The rule that decides what gets DELETED, so both apps run it.
    ///
    /// Every case is ASCII digits read as Gregorian, which is what makes the
    /// list portable: it means the same thing under `en_US_POSIX` and under
    /// `CultureInfo.InvariantCulture`. The mac's own migration — reading the
    /// spellings an older build wrote in the machine's calendar — is
    /// deliberately not here, and `ArchiveStampTests` covers it.
    func testWhetherAStampCouldBeTrueIsWhatTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("zipNames")
        let rule: [String: Any] = try XCTUnwrap(section["couldHaveBeenStamped"] as? [String: Any])

        // The bounds themselves, so a change to either goes red HERE and on
        // Windows rather than only in the Swift that happens to hold them.
        XCTAssertEqual(rule["earliest"] as? String, "2025-01-01 00:00:00")
        XCTAssertEqual(rule["futureAllowanceDays"] as? Int, 2)

        let secondsPerDay: TimeInterval = 24 * 60 * 60
        for testCase in try XCTUnwrap(rule["cases"] as? [[String: Any]]) {
            let expected: Bool = try XCTUnwrap(testCase["expect"] as? Bool)

            if let daysFromNow = testCase["daysFromNow"] as? Int {
                let moment: Date = Date().addingTimeInterval(secondsPerDay * TimeInterval(daysFromNow))
                XCTAssertEqual(
                    ArchiveStamp.couldHaveBeenStamped(moment), expected,
                    "\(daysFromNow) days from now"
                )
                continue
            }

            let stamp: String = try XCTUnwrap(testCase["stamp"] as? String)
            let read: Date = try XCTUnwrap(
                CourseManagementContractTests.readAsGregorian(stamp),
                "\(stamp) should parse as an ordinary Gregorian stamp, whatever it means"
            )
            XCTAssertEqual(ArchiveStamp.couldHaveBeenStamped(read), expected, stamp)
        }
    }

    /// The stamp read the one way both platforms read it — no machine
    /// calendar, no fallback. What the contract's cases are ABOUT.
    private static func readAsGregorian(_ stamp: String) -> Date? {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = ArchiveStamp.format
        return formatter.date(from: stamp)
    }

    // MARK: - The name a new course starts with

    func testANewCourseStartsWithTheShortName() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("defaultCourseName")
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let code: String = try XCTUnwrap(testCase["code"] as? String)
            let expected: String? = testCase["expect"] as? String
            XCTAssertEqual(
                CourseNameCatalog.defaultName(forCode: code), expected,
                "\(code) should start life named \(expected ?? "nothing")"
            )
        }
    }

    // MARK: - Adding a section

    func testTheSuggestedSectionNumberIsTheSmallestFree() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("sectionNumbers")
        for testCase in try XCTUnwrap(section["suggested"] as? [[String: Any]]) {
            let existing: [Int] = try XCTUnwrap(testCase["existing"] as? [Int])
            XCTAssertEqual(
                SectionAdder.suggestedNumber(existing: existing),
                testCase["expect"] as? Int,
                "existing \(existing)"
            )
        }
    }

    func testTheEntryProblemsAreWordedAsTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("sectionNumbers")
        for testCase in try XCTUnwrap(section["entryProblems"] as? [[String: Any]]) {
            let entry: String = try XCTUnwrap(testCase["entry"] as? String)
            XCTAssertEqual(
                SectionAdder.entryProblem(
                    entry, existing: try XCTUnwrap(testCase["existing"] as? [Int]), courseCode: "ICS3U"
                ),
                testCase["expectProblem"] as? String,
                "entry “\(entry)”"
            )
        }
        for testCase in try XCTUnwrap(section["addable"] as? [[String: Any]]) {
            let entry: String = try XCTUnwrap(testCase["entry"] as? String)
            XCTAssertEqual(
                SectionAdder.entryIsAddable(
                    entry, existing: try XCTUnwrap(testCase["existing"] as? [Int])
                ),
                testCase["expect"] as? Bool,
                "entry “\(entry)”"
            )
        }
    }

    /// A new section's keys, added to a page however its frontmatter is
    /// fenced — and nothing else about the page changed (GitHub #175).
    ///
    /// Compared as BYTES, whole file: a test for the new key's presence
    /// passes a splice that leaves a stray character on the new date, and
    /// Swift's `==` reads "\r\n" as one character, which is exactly the
    /// difference the Windows-line-ending case is about.
    func testAddingASectionsKeysToAPageIsWhatTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("sectionNumbers")
        let rule: [String: Any] = try XCTUnwrap(section["addingKeysToAPage"] as? [String: Any])
        let created: String = try XCTUnwrap(rule["created"] as? String)
        let newSection: Int = try XCTUnwrap(rule["section"] as? Int)
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adding-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for testCase in cases {
            let shape: String = try XCTUnwrap(testCase["shape"] as? String)
            let before: String = try XCTUnwrap(testCase["before"] as? String)
            let after: String = try XCTUnwrap(testCase["after"] as? String)
            let pageURL: URL = folder.appendingPathComponent("Loops.md")
            try Data(before.utf8).write(to: pageURL)

            SectionAdder.extendFrontmatter(ofPageAt: pageURL, toInclude: newSection, created: created)

            let written: Data = try Data(contentsOf: pageURL)
            XCTAssertEqual(
                written, Data(after.utf8),
                "\(shape): wrote \(String(decoding: written, as: UTF8.self).debugDescription)"
            )
        }
    }

    /// Putting one section's per-section keys back from a backup, carried and
    /// dropped WITH the lines each key owns (GitHub #182), and a page with no
    /// room for a new key left exactly as it is and counted (#186's shape).
    ///
    /// Compared as BYTES, whole file, for the reason the adding-keys cases
    /// give above. Windows' restore does not read this list yet; it is owed
    /// with #177.
    func testRestoringOneSectionsKeysIsWhatTheContractSays() throws {
        let backups: [String: Any] = try CourseManagementContractTests.section("backups")
        let group: [String: Any] = try XCTUnwrap(backups["restoringOneSectionsKeys"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(group["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "backups.restoringOneSectionsKeys has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let sectionNumber: Int = try XCTUnwrap(testCase["section"] as? Int)
            let live: String = try XCTUnwrap(testCase["live"] as? String)
            let backup: String = try XCTUnwrap(testCase["backup"] as? String)
            let after: String = try XCTUnwrap(testCase["after"] as? String)
            let notPutBack: Bool = try XCTUnwrap(testCase["expectCouldNotBePutBack"] as? Bool)
            let restored: (text: String, couldNotBePutBack: Bool) = CourseRestorer.settingPerSectionKeys(
                sectionNumber, in: live, asIn: backup
            )
            XCTAssertEqual(
                Data(restored.text.utf8), Data(after.utf8),
                "\(name): wrote \(restored.text.debugDescription)"
            )
            XCTAssertEqual(restored.couldNotBePutBack, notPutBack, name)
        }
    }

    // MARK: - What a course code says about the grade

    func testTheGradeLabelsAreWhatTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("gradeLabels")
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let code: String = try XCTUnwrap(testCase["code"] as? String)
            XCTAssertEqual(SectionAdder.gradeLabel(forCourseCode: code), testCase["expect"] as? String, code)
        }
    }

    // MARK: - The stamp new pages carry

    /// Matched exactly so a page added in March sits beside a page made at
    /// setup without a teacher ever seeing two forms of the same field.
    func testTheTimestampMatchesTheWizardsForm() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("timestampFormat")
        let written: String = SectionAdder.timestamp(for: Date(timeIntervalSince1970: 1_786_000_000))

        // Shape rather than value: the offset is this machine's.
        XCTAssertEqual(written.count, try XCTUnwrap(section["example"] as? String).count)
        XCTAssertTrue(written.contains("T"), written)
        XCTAssertTrue(written.contains(".000"), written)
        let head: String = String(written.prefix(10))
        XCTAssertNotNil(CalendarDay(text: head), "\(head) should be a yyyy-MM-dd date")
    }

    // MARK: - What a course code may be

    /// The rule the New Course wizard and renaming BOTH ask. They used to
    /// ask separately, and a wizard that accepts a code renaming refuses is
    /// a course a teacher can create and then never re-type.
    func testTheCourseCodeRuleIsWordedAsTheContractSays() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("courseCode")

        XCTAssertEqual(
            CourseCodeRule.mostCharacters,
            section["mostCharacters"] as? Int,
            "The limit the sentence quotes has to be the limit the rule enforces"
        )

        for testCase in try XCTUnwrap(section["normalized"] as? [[String: Any]]) {
            let typed: String = try XCTUnwrap(testCase["typed"] as? String)
            XCTAssertEqual(
                CourseCodeRule.normalized(typed), testCase["expect"] as? String, "typed “\(typed)”"
            )
        }

        for testCase in try XCTUnwrap(section["problems"] as? [[String: Any]]) {
            let typed: String = try XCTUnwrap(testCase["typed"] as? String)
            let existing: [String] = try XCTUnwrap(testCase["existing"] as? [String])
            let current: String? = testCase["currentCode"] as? String

            XCTAssertEqual(
                CourseCodeRule.problem(typed, existingCodes: existing, currentCode: current),
                testCase["expectProblem"] as? String,
                "typed “\(typed)”"
            )
            // The SHORT form is teacher-facing too — it is what the sidebar
            // row shows while a course is being renamed — so it is pinned
            // here rather than left to whatever fits that day.
            XCTAssertEqual(
                CourseCodeRule.shortProblem(typed, existingCodes: existing, currentCode: current),
                testCase["expectShort"] as? String,
                "typed “\(typed)”, short form"
            )
        }

        // Whether a code names a club. Contract-run rather than checked in
        // the wizard, because the wizard is not the only thing that asks —
        // Windows asks the identical question, and had the identical bug
        // (its one-line fallback read every BC course as a club).
        let clubDetection: [String: Any] = try XCTUnwrap(section["clubDetection"] as? [String: Any])
        for testCase in try XCTUnwrap(clubDetection["cases"] as? [[String: Any]]) {
            let code: String = try XCTUnwrap(testCase["code"] as? String)
            XCTAssertEqual(
                ClubCodeRule.isClub(code),
                try XCTUnwrap(testCase["expectClub"] as? Bool),
                "code “\(code)”"
            )
        }
    }

    // MARK: - What renaming touches, and what it leaves alone

    /// Drives a REAL rename over a real folder and checks each effect the
    /// contract names. The list is the interesting half: renaming is defined
    /// as much by what it refuses to touch — the teacher's own course name,
    /// their backups, the address their students have — as by the move
    /// itself.
    func testRenamingHasTheEffectsTheContractNames() throws {
        let section: [String: Any] = try CourseManagementContractTests.section("courseCode")
        let fileManager: FileManager = FileManager.default
        let fixture: RenameFixture = try makeCourseReadyToRename()

        let oldCourseURL: URL = fixture.course.directoryURL
        let oldBackupURL: URL = fixture.coursesURL
            .appendingPathComponent("_backups")
            .appendingPathComponent("ICS3U")
            .appendingPathComponent("ICS3U_backup_2026-01-01_120000.zip")
        let scheduledURL: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1)

        let outcome: CourseRenamer.Outcome = try CourseRenamer.rename(
            fixture.course,
            to: "ICS4U",
            coursesDirectoryURL: fixture.coursesURL,
            existingCodes: ["ICS3U"],
            runner: SilentLaunchControl()
        )

        let newCourseURL: URL = fixture.coursesURL.appendingPathComponent("ICS4U")
        let written: CourseConfiguration = try CourseConfiguration(
            contentsOf: newCourseURL.appendingPathComponent("course_config.json")
        )

        for effect in try XCTUnwrap(section["renameEffects"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(effect["effect"] as? String)
            let expected: Bool = try XCTUnwrap(effect["expect"] as? Bool)

            switch name {
            case "courseFolderMoves":
                let moved: Bool = fileManager.fileExists(atPath: newCourseURL.path)
                    && !fileManager.fileExists(atPath: oldCourseURL.path)
                XCTAssertEqual(moved, expected, name)
                XCTAssertTrue(
                    fileManager.fileExists(atPath: newCourseURL.appendingPathComponent("section1").path),
                    "everything inside travels with the folder"
                )
            case "courseCodeInSettingsRewritten":
                XCTAssertEqual(written.courseCode == "ICS4U", expected, name)
            case "courseNameRewritten":
                XCTAssertEqual(
                    written.courseName != "Introduction to Computer Science", expected, name
                )
            case "backupsAndArchivesMove":
                let backupsMoved: Bool = fileManager.fileExists(
                    atPath: fixture.coursesURL
                        .appendingPathComponent("_backups")
                        .appendingPathComponent("ICS4U").path
                )
                XCTAssertEqual(backupsMoved, expected, name)
                XCTAssertTrue(
                    fileManager.fileExists(atPath: oldBackupURL.path),
                    "and the copy itself is never touched — it is the way back"
                )
            case "publishingIdentityTravelsWithTheFolder":
                let travelled: Bool = fileManager.fileExists(
                    atPath: newCourseURL
                        .appendingPathComponent(".netlify_sites")
                        .appendingPathComponent("section1.json").path
                )
                XCTAssertEqual(travelled, expected, name)
            case "scheduledPublishingCancelled":
                let cancelled: Bool = !fileManager.fileExists(atPath: scheduledURL.path)
                    && outcome.stoppedScheduledSections == [1]
                XCTAssertEqual(cancelled, expected, name)
                XCTAssertNotNil(
                    CourseRenamer.noticeAfterRenaming(outcome),
                    "and the teacher is told, because a scheduled publish that quietly stops is the failure worth an alert"
                )
            default:
                XCTFail("The contract names a rename effect no test drives: \(name)")
            }
        }
    }

    // MARK: - Private

    /// What a rename needs around it: a course with a section, a publishing
    /// marker, a backup, and one section set to publish on its own.
    struct RenameFixture {

        // MARK: - Stored properties

        let coursesURL: URL
        let course: Course
    }

    private func makeCourseReadyToRename() throws -> RenameFixture {
        let fileManager: FileManager = FileManager.default
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rename-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")

        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        let markersURL: URL = courseURL.appendingPathComponent(".netlify_sites")
        try fileManager.createDirectory(at: markersURL, withIntermediateDirectories: true)
        try "{}".write(
            to: markersURL.appendingPathComponent("section1.json"), atomically: true, encoding: .utf8
        )

        let backupsURL: URL = coursesURL
            .appendingPathComponent("_backups")
            .appendingPathComponent("ICS3U")
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        try "not really a zip".write(
            to: backupsURL.appendingPathComponent("ICS3U_backup_2026-01-01_120000.zip"),
            atomically: true,
            encoding: .utf8
        )

        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        let values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
        ]
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted]).write(to: configURL)

        let agentsURL: URL = root.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: agentsURL, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsURL
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            agentsURL.deletingLastPathComponent().appendingPathComponent("scheduled")
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
            }
            try? FileManager.default.removeItem(at: root)
        }
        // A REAL agent rather than the `<plist></plist>` placeholder this used
        // to write. Since 2026-09-20 a rename asks each agent which working
        // folder it belongs to and leaves alone anything belonging to
        // another — a label is the course code and section and nothing else,
        // so without that a teacher holding two working folders with the same
        // course code would have a rename in one cancel the other's live
        // deploy. Every release since v1.0.0 writes `WorkingDirectory`, so a
        // plist that does not name a folder is not something a teacher can
        // have; the placeholder was.
        let agentPlist: [String: Any] = [
            "Label": ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1),
            "WorkingDirectory": root.path,
            "ProgramArguments": [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                ScheduledDeploy.runFlag,
                "/tmp/scheduled.sh",
                ScheduledDeploy.sectionFlag,
                root.path,
                "ICS3U",
                "1",
            ],
        ]
        try PropertyListSerialization.data(
            fromPropertyList: agentPlist, format: .xml, options: 0
        ).write(to: ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1))

        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        return RenameFixture(
            coursesURL: coursesURL,
            course: Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
        )
    }


    // MARK: - Backups (#242)

    /// The rules the pane and the pruning keep, as the contract states them.
    func testTheBackupRulesAreTheOnesTheContractStates() throws {
        let backups: [String: Any] = try CourseManagementContractTests.section("backups")
        XCTAssertEqual(backups["assistantKept"] as? Int, CourseArchiver.mostBackupsKept)
        XCTAssertEqual(backups["teacherBackupsPruned"] as? String, "never")
        XCTAssertEqual(backups["mediaIsAlwaysIncluded"] as? Bool, true)
        XCTAssertEqual(backups["sizeIsLogical"] as? Bool, true)
        XCTAssertEqual(backups["neverDeletedWhileAConversationCanRestoreFromIt"] as? Bool, true)
        XCTAssertFalse(
            CourseArchiver.excludedFromArchives.contains("Media"),
            "a backup without Media was REJECTED: restoring one would delete the course's Media"
        )
    }

    /// What the pruning after a new backup deletes: the assistant's oldest
    /// beyond five, and never a teacher's, an archive or a wizard zip.
    func testThePruneCasesAreWhatTheContractSays() throws {
        let backups: [String: Any] = try CourseManagementContractTests.section("backups")
        for testCase in try XCTUnwrap(backups["pruneCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: String = try XCTUnwrap(testCase["course"] as? String)
            let existing: [String] = try XCTUnwrap(testCase["existing"] as? [String])
            let expectDeleted: [String] = try XCTUnwrap(testCase["expectDeleted"] as? [String])

            let coursesURL: URL = try CourseManagementContractTests.scratchCoursesFolder()
            defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }
            let folder: URL = coursesURL.appendingPathComponent("_backups/\(course)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for fileName in existing {
                FileManager.default.createFile(atPath: folder.appendingPathComponent(fileName).path, contents: Data())
            }

            CourseArchiver.pruneBackups(forCourseCode: course, coursesDirectoryURL: coursesURL)

            for fileName in existing {
                let stillThere: Bool = FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
                XCTAssertEqual(stillThere, !expectDeleted.contains(fileName), "\(name): \(fileName)")
            }
        }
    }

    /// What the Backups header and All Backups count: backups only, per course
    /// and in total, by their LOGICAL size.
    func testTheSizeCasesAreCountedAsTheContractSays() async throws {
        let backups: [String: Any] = try CourseManagementContractTests.section("backups")
        for testCase in try XCTUnwrap(backups["sizeCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let coursesURL: URL = try CourseManagementContractTests.scratchCoursesFolder()
            defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

            for file in try XCTUnwrap(testCase["files"] as? [[String: Any]]) {
                let course: String = try XCTUnwrap(file["course"] as? String)
                let fileName: String = try XCTUnwrap(file["name"] as? String)
                let bytes: Int = try XCTUnwrap(file["bytes"] as? Int)
                let folder: URL = coursesURL.appendingPathComponent("_backups/\(course)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url: URL = folder.appendingPathComponent(fileName)
                // Sparse: the logical size is set, and no data is written.
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle: FileHandle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: UInt64(bytes))
                try handle.close()
                if file["sparse"] as? Bool == true {
                    let onDisk: Int = try XCTUnwrap(
                        url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
                    )
                    XCTAssertLessThan(onDisk, bytes / 100, "\(name): the file is not sparse, so the case proves nothing")
                }
            }

            let items: [BackupItem] = WorkspaceModel.findBackupItems(in: coursesURL)
            var fileURLs: [URL] = []
            for item in items {
                fileURLs.append(item.fileURL)
            }
            let sizes: [String: Int64] = await BackupSizes.measure(fileURLs)
            let space: BackupSpace = BackupSpace.of(items, sizes: sizes)

            XCTAssertTrue(space.isComplete, name)
            XCTAssertEqual(space.totalCount, testCase["expectTotalCount"] as? Int, name)
            XCTAssertEqual(space.totalBytes, Int64(try XCTUnwrap(testCase["expectTotalBytes"] as? Int)), name)
            var expected: [BackupSpace.CourseShare] = []
            for share in try XCTUnwrap(testCase["expectCourses"] as? [[String: Any]]) {
                expected.append(BackupSpace.CourseShare(
                    courseCode: try XCTUnwrap(share["courseCode"] as? String),
                    count: try XCTUnwrap(share["count"] as? Int),
                    bytes: Int64(try XCTUnwrap(share["bytes"] as? Int))
                ))
            }
            XCTAssertEqual(space.courses, expected, name)
        }
    }

    /// What a delete removes and what it keeps — never the backup an open
    /// assistant conversation can restore from.
    func testTheDeleteCasesAreWhatTheContractSays() throws {
        let backups: [String: Any] = try CourseManagementContractTests.section("backups")
        for testCase in try XCTUnwrap(backups["deleteCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let coursesURL: URL = try CourseManagementContractTests.scratchCoursesFolder()
            let rootURL: URL = coursesURL.deletingLastPathComponent()
            defer {
                AssistActivity.store.active = nil
                AssistActivity.store.heldBackups = nil
                try? FileManager.default.removeItem(at: rootURL)
            }
            let folder: URL = coursesURL.appendingPathComponent("_backups/ICS3U", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for fileName in try XCTUnwrap(testCase["backups"] as? [String]) {
                FileManager.default.createFile(atPath: folder.appendingPathComponent(fileName).path, contents: Data())
            }
            var held: [URL] = []
            for fileName in try XCTUnwrap(testCase["heldByAnOpenConversation"] as? [String]) {
                held.append(folder.appendingPathComponent(fileName))
            }
            // A constant for the closure to capture: `held` is built above and
            // never changes again, and saying so keeps the compiler from
            // warning that a captured variable might.
            let heldURLs: [URL] = held
            if !heldURLs.isEmpty {
                AssistActivity.begin(folderPath: rootURL.path, courseCode: "ICS3U", sectionNumber: 2)
                AssistActivity.holdBackups(folderPath: rootURL.path, courseCode: "ICS3U", sectionNumber: 2) {
                    return heldURLs
                }
            }

            let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
            model.chooseWorkspace(at: rootURL)
            let asked: [String] = try XCTUnwrap(testCase["delete"] as? [String])
            var items: [BackupItem] = []
            for item in model.backupItems where asked.contains(item.fileURL.lastPathComponent) {
                items.append(item)
            }
            XCTAssertEqual(items.count, asked.count, "\(name): a backup to delete is not in the list")

            let deletion: WorkspaceModel.BackupDeletion = model.deleteBackups(items, following: [])

            var deletedNames: [String] = []
            for item in deletion.deleted {
                deletedNames.append(item.fileURL.lastPathComponent)
            }
            var keptNames: [String] = []
            for item in deletion.keptForTheAssistant {
                keptNames.append(item.fileURL.lastPathComponent)
            }
            XCTAssertEqual(Set(deletedNames), Set(try XCTUnwrap(testCase["expectDeleted"] as? [String])), name)
            XCTAssertEqual(Set(keptNames), Set(try XCTUnwrap(testCase["expectKept"] as? [String])), name)
            for fileName in deletedNames {
                XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path), name)
            }
            for fileName in keptNames {
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path), name)
            }
        }
    }

    /// A scratch working folder's `courses` folder, under the temporary
    /// directory — never a real working folder (#240's lesson).
    private static func scratchCoursesFolder() throws -> URL {
        let coursesURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backups-contract-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("courses", isDirectory: true)
        try FileManager.default.createDirectory(at: coursesURL, withIntermediateDirectories: true)
        // A working folder is recognised by its launcher; without one the
        // folder is not read at all.
        FileManager.default.createFile(
            atPath: coursesURL.deletingLastPathComponent().appendingPathComponent("preview.sh").path,
            contents: Data()
        )
        return coursesURL
    }

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/course-management.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in course-management.json")
    }
}
