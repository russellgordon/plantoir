import XCTest
import AppKit
@testable import QuartzTeachers

/// Backups: saved copies of whole courses, made on purpose before risky
/// editing, listed in their own sidebar group, restorable, and deletable
/// for good.
final class BackupTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testABackupNameIsRecognizedAndOthersAreNot() {
        let folder: URL = URL(fileURLWithPath: "/folder/_backups/ICS3U")

        let backup: BackupItem? = BackupItem.from(
            fileURL: folder.appendingPathComponent("ICS3U_backup_2026-08-11_221530.zip"),
            courseCode: "ICS3U"
        )
        XCTAssertNotNil(backup)
        XCTAssertEqual(backup?.courseCode, "ICS3U")
        XCTAssertEqual(backup?.title, "ICS3U")

        // An archive is not a backup…
        XCTAssertNil(BackupItem.from(
            fileURL: folder.appendingPathComponent("ICS3U_2026-08-11_221530.zip"),
            courseCode: "ICS3U"
        ))
        // …nor is the wizard's automatic zip…
        XCTAssertNil(BackupItem.from(
            fileURL: folder.appendingPathComponent("2026-08-11_221530.zip"),
            courseCode: "ICS3U"
        ))
        // …nor anything that merely resembles one.
        XCTAssertNil(BackupItem.from(
            fileURL: folder.appendingPathComponent("ICS3U_backup_notadate.zip"),
            courseCode: "ICS3U"
        ))
    }

    /// Every backup made before provenance existed is one the teacher made
    /// themselves — so an old name must still parse, and must read that way.
    /// If it did not, a teacher's own backups would vanish from the list.
    @MainActor
    func testAnOldNameStillParsesAndReadsAsTheTeachersOwn() throws {
        let fileURL: URL = URL(fileURLWithPath:
            "/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530.zip")
        let backup: BackupItem = try XCTUnwrap(
            BackupItem.from(fileURL: fileURL, courseCode: "ICS3U")
        )
        XCTAssertEqual(backup.maker, .teacher)
        XCTAssertTrue(backup.subtitle.hasPrefix("Backed up "))
        XCTAssertTrue(backup.subtitle.hasSuffix("made by you"), backup.subtitle)
    }

    /// The assistant's own say so in the name, and the list says what the
    /// backup was FOR — which is the question a teacher choosing between five
    /// copies of one course is actually asking.
    @MainActor
    func testAnAssistantsBackupSaysWhichSectionItWasFor() throws {
        let fileURL: URL = URL(fileURLWithPath:
            "/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530_assistant-section3.zip")
        let backup: BackupItem = try XCTUnwrap(
            BackupItem.from(fileURL: fileURL, courseCode: "ICS3U")
        )
        XCTAssertEqual(backup.maker, .assistant(sectionNumber: 3))
        XCTAssertTrue(backup.subtitle.contains("before an assistant chat about Section 3"),
                      backup.subtitle)
        let teachersOwn: BackupItem = BackupItem(
            courseCode: "ICS3U", backedUpAt: backup.backedUpAt, fileURL: fileURL, maker: .teacher
        )
        XCTAssertNotEqual(backup.symbolName, teachersOwn.symbolName,
                          "The two kinds are told apart down a list without reading a word")
        for name in [backup.symbolName, teachersOwn.symbolName] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil),
                            "\(name) is not a symbol this system knows — the row would show no icon")
        }

        // A maker nobody recognises makes the whole name unrecognised, rather
        // than quietly reading as one of the teacher's own.
        XCTAssertNil(BackupItem.from(
            fileURL: URL(fileURLWithPath:
                "/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530_somethingelse.zip"),
            courseCode: "ICS3U"
        ))
    }

    /// An assistant's backup is still a backup, and still invisible to the
    /// archived list it shares a folder with.
    @MainActor
    func testAnAssistantsBackupIsInvisibleToTheArchivedList() {
        let fileURL: URL = URL(fileURLWithPath:
            "/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530_assistant-section1.zip")
        XCTAssertNil(ArchivedItem.from(fileURL: fileURL, courseCode: "ICS3U"))
    }

    /// Pruning is the assistant clearing up after itself, and nothing more.
    ///
    /// The assistant saves a copy every conversation whether or not anybody
    /// asked, so a term of chats would fill a disk. A teacher's own backup is
    /// the opposite: they pressed Back Up because they were about to do
    /// something they were unsure of. Deciding on their behalf that it has
    /// expired is the app overruling them about their own work.
    @MainActor
    func testOnlyTheAssistantsOwnBackupsArePruned() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        let folderURL: URL = fixture.coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent("ICS3U")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Seven of the assistant's, newest first, and seven of the teacher's
        // interleaved among them — more than the limit, deliberately, so that
        // counting them together would prune some of the teacher's.
        var assistantNames: [String] = []
        var teacherNames: [String] = []
        for daysAgo in 1...7 {
            let assistantStamp: String = BackupTests.stamp(daysAgo: daysAgo)
            let teacherStamp: String = BackupTests.stamp(daysAgo: daysAgo, extraSeconds: 30)
            assistantNames.append("ICS3U_backup_\(assistantStamp)_assistant-section1.zip")
            teacherNames.append("ICS3U_backup_\(teacherStamp).zip")
        }
        // Neither of these is a backup, and neither is ours to delete.
        let archiveName: String = "ICS3U_\(BackupTests.stamp(daysAgo: 8)).zip"
        let wizardName: String = "\(BackupTests.stamp(daysAgo: 9)).zip"

        var namesToPlant: [String] = assistantNames
        namesToPlant.append(contentsOf: teacherNames)
        namesToPlant.append(archiveName)
        namesToPlant.append(wizardName)
        for name in namesToPlant {
            try Data("planted".utf8).write(to: folderURL.appendingPathComponent(name))
        }

        CourseArchiver.pruneBackups(
            forCourseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        // EVERY teacher backup survives, all seven of them.
        for name in teacherNames {
            XCTAssertTrue(
                fileManager.fileExists(atPath: folderURL.appendingPathComponent(name).path),
                "\(name) was made by the teacher and must never be pruned"
            )
        }

        // The assistant's five newest survive…
        for index in 0...4 {
            XCTAssertTrue(
                fileManager.fileExists(atPath: folderURL.appendingPathComponent(assistantNames[index]).path),
                "\(assistantNames[index]) is among the assistant's five newest"
            )
        }
        // …and its two oldest are gone.
        for index in 5...6 {
            XCTAssertFalse(
                fileManager.fileExists(atPath: folderURL.appendingPathComponent(assistantNames[index]).path),
                "\(assistantNames[index]) is one of the assistant's oldest and should have gone"
            )
        }

        XCTAssertTrue(
            fileManager.fileExists(atPath: folderURL.appendingPathComponent(archiveName).path),
            "An archive is not a backup and must never be pruned"
        )
        XCTAssertTrue(
            fileManager.fileExists(atPath: folderURL.appendingPathComponent(wizardName).path),
            "The setup wizard's own zip must never be pruned"
        )
    }

    /// A backup whose stamp cannot be true is never counted and never
    /// deleted — because this list is sorted by date before its tail is
    /// thrown away.
    ///
    /// The name here is what a Buddhist-calendar Mac wrote before 2026-09-10,
    /// carried to this one in a working folder. Nothing can tell that 2569
    /// was ever meant to be 2026 — reading it as Buddhist would mean deciding
    /// another machine's calendar on its behalf — so it keeps the date it
    /// has, and sorts as the newest thing in the folder. Counted, it would
    /// take one of the five kept places and push a real backup out of the
    /// list and off the disk.
    @MainActor
    func testABackupWhoseStampCannotBeTrueIsNeitherCountedNorDeleted() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        let folderURL: URL = fixture.coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent("ICS3U")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let carriedOver: String = "ICS3U_backup_2569-08-09_141530_assistant-section1.zip"
        var assistantNames: [String] = []
        for daysAgo in 1...5 {
            assistantNames.append(
                "ICS3U_backup_\(BackupTests.stamp(daysAgo: daysAgo))_assistant-section1.zip"
            )
        }

        var namesToPlant: [String] = assistantNames
        namesToPlant.append(carriedOver)
        for name in namesToPlant {
            try Data("planted".utf8).write(to: folderURL.appendingPathComponent(name))
        }

        CourseArchiver.pruneBackups(
            forCourseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        for name in assistantNames {
            XCTAssertTrue(
                fileManager.fileExists(atPath: folderURL.appendingPathComponent(name).path),
                "\(name) is one of the five real backups and must survive"
            )
        }
        XCTAssertTrue(
            fileManager.fileExists(atPath: folderURL.appendingPathComponent(carriedOver).path),
            "A backup with an unreadable date is still the teacher's, and is not ours to delete"
        )
        XCTAssertNotNil(
            BackupItem.from(fileURL: folderURL.appendingPathComponent(carriedOver), courseCode: "ICS3U"),
            "…and it goes on being listed, so they can restore or delete it themselves"
        )
    }

    /// A course with nothing but the teacher's own backups loses none of
    /// them, however many there are.
    @MainActor
    func testATeachersBackupsAreNeverPrunedHoweverMany() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        let folderURL: URL = fixture.coursesDirectoryURL
            .appendingPathComponent("_backups")
            .appendingPathComponent("ICS3U")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var names: [String] = []
        for daysAgo in 1...12 {
            names.append("ICS3U_backup_\(BackupTests.stamp(daysAgo: daysAgo)).zip")
        }
        for name in names {
            try Data("planted".utf8).write(to: folderURL.appendingPathComponent(name))
        }

        CourseArchiver.pruneBackups(
            forCourseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        for name in names {
            XCTAssertTrue(
                fileManager.fileExists(atPath: folderURL.appendingPathComponent(name).path),
                "\(name) is the teacher's and must survive"
            )
        }
    }

    /// "2026-08-09_141530", that many days back from now — so the test means
    /// the same thing whenever it is run.
    ///
    /// Spelled by the app's own writer rather than by a formatter of its
    /// own: a fixture that spells a name a different way is a fixture that
    /// stops describing the product the moment the product changes.
    private static func stamp(daysAgo: Int, extraSeconds: TimeInterval = 0) -> String {
        let secondsPerDay: TimeInterval = 24 * 60 * 60
        let moment: Date = Date()
            .addingTimeInterval(-secondsPerDay * TimeInterval(daysAgo))
            .addingTimeInterval(extraSeconds)
        return ArchiveStamp.text(for: moment)
    }

    @MainActor
    func testABackupNameIsInvisibleToTheArchivedList() {
        // The two lists share a folder; only the name separates them.
        let fileURL: URL = URL(fileURLWithPath: "/folder/_backups/ICS3U/ICS3U_backup_2026-08-11_221530.zip")
        XCTAssertNil(ArchivedItem.from(fileURL: fileURL, courseCode: "ICS3U"),
                     "A backup must never appear among archived items")
    }

    @MainActor
    func testBackingUpCopiesTheCourseAndLeavesItInPlace() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }

        let backupURL: URL = try CourseArchiver.backUpCourse(
            fixture.course, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        // The whole name, not just its beginning — this is the one test that
        // watches the REAL writer, and the fault it guards against is in the
        // half a prefix check never looks at. A Buddhist-calendar Mac with an
        // unpinned formatter writes "ICS3U_backup_2569-…", which has the same
        // prefix and is not a name Plantoir writes.
        let name: String = backupURL.lastPathComponent
        let thisYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
        XCTAssertNotNil(
            name.range(of: "^ICS3U_backup_\\d{4}-\\d{2}-\\d{2}_\\d{6}\\.zip$", options: .regularExpression),
            "“\(name)” is not the name the contract describes"
        )
        XCTAssertTrue(
            name.contains("ICS3U_backup_\(thisYear)-"),
            "“\(name)” is not stamped in the Gregorian year it was made in"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.pageURL.path),
                      "Backing up must not move or remove the course")

        let items: [BackupItem] = WorkspaceModel.findBackupItems(in: fixture.coursesDirectoryURL)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].courseCode, "ICS3U")
    }

    @MainActor
    func testRestoringABackupBringsTheOldContentBackAndKeepsTheZip() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        _ = try CourseArchiver.backUpCourse(
            fixture.course, coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        // The LLM makes a mess: a ruined page and a stray new file.
        try Data("ruined".utf8).write(to: fixture.pageURL)
        let strayURL: URL = fixture.courseURL.appendingPathComponent("stray.md")
        try Data("stray".utf8).write(to: strayURL)

        // The app archives the current version (without removing it),
        // then restores the backup in place.
        try CourseArchiver.archiveCourse(
            fixture.course, coursesDirectoryURL: fixture.coursesDirectoryURL
        )
        let items: [BackupItem] = WorkspaceModel.findBackupItems(in: fixture.coursesDirectoryURL)
        XCTAssertEqual(items.count, 1)
        try CourseRestorer.restoreBackup(items[0], coursesDirectoryURL: fixture.coursesDirectoryURL)

        let restored: String = try String(contentsOf: fixture.pageURL, encoding: .utf8)
        XCTAssertEqual(restored, "original", "The backup's content is back")
        XCTAssertFalse(fileManager.fileExists(atPath: strayURL.path),
                       "Files that were not in the backup are gone after restoring")
        XCTAssertTrue(fileManager.fileExists(atPath: items[0].fileURL.path),
                      "Restoring keeps the backup — only deleting removes it")
        XCTAssertFalse(
            fileManager.fileExists(atPath: fixture.courseURL.appendingPathComponent(".merged_output").path),
            "Rebuildable output stays out of backups"
        )
    }

    @MainActor
    func testRestoringKeepsTheCourseFolderItselfInPlace() throws {
        // The course folder is Obsidian's vault, and Obsidian's file
        // watcher is anchored to the folder's identity: replace the
        // folder and Obsidian shows stale files until the vault is
        // reopened; replace only its CONTENTS and it refreshes itself.
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        _ = try CourseArchiver.backUpCourse(
            fixture.course, coursesDirectoryURL: fixture.coursesDirectoryURL
        )
        let identityBefore: Any? =
            try fileManager.attributesOfItem(atPath: fixture.courseURL.path)[.systemFileNumber]

        try Data("ruined".utf8).write(to: fixture.pageURL)
        let items: [BackupItem] = WorkspaceModel.findBackupItems(in: fixture.coursesDirectoryURL)
        try CourseRestorer.restoreBackup(items[0], coursesDirectoryURL: fixture.coursesDirectoryURL)

        let identityAfter: Any? =
            try fileManager.attributesOfItem(atPath: fixture.courseURL.path)[.systemFileNumber]
        XCTAssertEqual(identityBefore as? Int, identityAfter as? Int,
                       "The vault folder must be the SAME folder after a restore")
        let restored: String = try String(contentsOf: fixture.pageURL, encoding: .utf8)
        XCTAssertEqual(restored, "original")
    }

    @MainActor
    func testRestoringIntoAMissingCourseRecreatesIt() throws {
        let fixture: BackupFixture = try BackupFixture()
        defer { fixture.tearDown() }

        _ = try CourseArchiver.backUpCourse(
            fixture.course, coursesDirectoryURL: fixture.coursesDirectoryURL
        )
        try FileManager.default.removeItem(at: fixture.courseURL)

        let items: [BackupItem] = WorkspaceModel.findBackupItems(in: fixture.coursesDirectoryURL)
        try CourseRestorer.restoreBackup(items[0], coursesDirectoryURL: fixture.coursesDirectoryURL)

        let restored: String = try String(contentsOf: fixture.pageURL, encoding: .utf8)
        XCTAssertEqual(restored, "original", "A removed course comes back whole from its backup")
    }
}

/// A throwaway courses folder holding one small course with one page and
/// some rebuildable output that must stay out of backups.
@MainActor
struct BackupFixture {

    // MARK: - Stored properties

    let coursesDirectoryURL: URL
    let courseURL: URL
    let pageURL: URL
    let course: Course

    // MARK: - Initializer

    init() throws {
        let fileManager: FileManager = FileManager.default
        coursesDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)")
        courseURL = coursesDirectoryURL.appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1"),
            withIntermediateDirectories: true
        )
        pageURL = courseURL.appendingPathComponent("section1/index.md")
        try Data("original".utf8).write(to: pageURL)

        let configValues: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Backup Test Course",
            "section_numbers": [1],
        ]
        let configData: Data = try JSONSerialization.data(withJSONObject: configValues)
        try configData.write(to: courseURL.appendingPathComponent("course_config.json"))

        // Rebuildable output, which backups must leave out.
        let mergedURL: URL = courseURL.appendingPathComponent(".merged_output/section1")
        try fileManager.createDirectory(at: mergedURL, withIntermediateDirectories: true)
        try Data("built".utf8).write(to: mergedURL.appendingPathComponent("site.html"))

        let configuration: CourseConfiguration = CourseConfiguration(
            values: configValues, lastSavedData: configData
        )
        course = Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    // MARK: - Functions

    func tearDown() {
        try? FileManager.default.removeItem(at: coursesDirectoryURL)
    }
}
