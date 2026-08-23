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
            default:
                XCTAssertNil(backup, "\(name) must not be read as a backup")
                XCTAssertNil(archive, "\(name) must not be read as an archive")
            }
        }
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
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
            }
            try? FileManager.default.removeItem(at: root)
        }
        try "<plist></plist>".write(
            to: ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1),
            atomically: true,
            encoding: .utf8
        )

        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        return RenameFixture(
            coursesURL: coursesURL,
            course: Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
        )
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
