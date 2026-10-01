import XCTest
@testable import QuartzTeachers

/// Reading what a teacher has archived.
final class ArchivedItemTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAnArchivedCourseIsRecognised() {
        let url: URL = URL(fileURLWithPath: "/w/courses/_backups/IZN2O/IZN2O_2026-08-10_143005.zip")
        let item = ArchivedItem.from(fileURL: url, courseCode: "IZN2O")
        XCTAssertNotNil(item)
        XCTAssertNil(item?.sectionNumber, "The whole course was archived")
        XCTAssertEqual(item?.title, "IZN2O")
    }

    @MainActor
    func testAnArchivedSectionIsRecognised() {
        let url: URL = URL(fileURLWithPath: "/w/courses/_backups/IZN2O/IZN2O-section2_2026-08-10_143005.zip")
        let item = ArchivedItem.from(fileURL: url, courseCode: "IZN2O")
        XCTAssertEqual(item?.sectionNumber, 2)
        XCTAssertEqual(item?.title, "IZN2O — Section 2")
    }

    @MainActor
    func testTheWizardsAutomaticBackupIsNotListedAsArchived() {
        // The setup wizard backs a course up before changing it, naming the
        // file by timestamp alone. That is not something a teacher put away.
        let url: URL = URL(fileURLWithPath: "/w/courses/_backups/IZN2O/2026-08-10_143005.zip")
        XCTAssertNil(ArchivedItem.from(fileURL: url, courseCode: "IZN2O"))
    }

    @MainActor
    func testUnrelatedFilesAreIgnored() {
        XCTAssertNil(ArchivedItem.from(fileURL: URL(fileURLWithPath: "/w/courses/_backups/IZN2O/notes.txt"), courseCode: "IZN2O"))
        XCTAssertNil(ArchivedItem.from(fileURL: URL(fileURLWithPath: "/w/courses/_backups/IZN2O/OTHER_2026-08-10_143005.zip"), courseCode: "IZN2O"))
    }

    @MainActor
    func testTheDateIsReadFromTheName() {
        let url: URL = URL(fileURLWithPath: "/w/courses/_backups/IZN2O/IZN2O_2026-08-10_143005.zip")
        let item = ArchivedItem.from(fileURL: url, courseCode: "IZN2O")
        // Read back through a GREGORIAN calendar, not `Calendar.current`. The
        // stamp is Gregorian by construction (`ArchiveStamp`), so asking the
        // machine's own calendar what year it is would make this test agree
        // with itself on a Buddhist Mac — 2026 CE reads as 2569 there — and
        // that is the one machine it exists to be right about.
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: item!.archivedAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 10)
    }

    @MainActor
    func testTheSidebarListsArchivesNewestFirst() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arch-\(UUID().uuidString)")
        let courseArchives: URL = root.appendingPathComponent("_backups/IZN2O")
        try FileManager.default.createDirectory(at: courseArchives, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["IZN2O-section1_2026-08-09_090000.zip",
                     "IZN2O-section2_2026-08-10_143005.zip",
                     "2026-08-01_120000.zip"] {
            try Data().write(to: courseArchives.appendingPathComponent(name))
        }

        let found = WorkspaceModel.findArchivedItems(in: root)
        XCTAssertEqual(found.count, 2, "The wizard's automatic backup must not be listed")
        XCTAssertEqual(found.first?.sectionNumber, 2, "Newest first")
        XCTAssertEqual(found.last?.sectionNumber, 1)
    }

    @MainActor
    func testTheDeleteWarningKnowsWhatDeletingWouldLeaveBehind() {
        // One live course, ICS3U, with sections 1 and 2.
        let configuration: CourseConfiguration = CourseConfiguration(
            values: ["course_code": "ICS3U", "section_numbers": [1, 2]],
            lastSavedData: Data()
        )
        let liveCourses: [Course] = [
            Course(code: "ICS3U", directoryURL: URL(fileURLWithPath: "/w/courses/ICS3U"), configuration: configuration)
        ]
        let stamp: Date = Date()

        func archive(_ code: String, section: Int? = nil, file: String) -> ArchivedItem {
            return ArchivedItem(
                courseCode: code, sectionNumber: section, archivedAt: stamp,
                fileURL: URL(fileURLWithPath: "/w/courses/_backups/\(code)/\(file)")
            )
        }

        let liveCourseArchive: ArchivedItem = archive("ICS3U", file: "a.zip")
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(liveCourseArchive, among: liveCourses, archives: [liveCourseArchive], backups: []),
            .liveInCourses
        )

        let goneSectionArchive: ArchivedItem = archive("ICS3U", section: 3, file: "s3.zip")
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(goneSectionArchive, among: liveCourses, archives: [goneSectionArchive], backups: []),
            .onlyRemainingCopy,
            "The live course no longer has section 3, and nothing else covers it"
        )

        // Two archives of a course that is gone: neither is the only copy.
        let first: ArchivedItem = archive("ICD2O", file: "one.zip")
        let second: ArchivedItem = archive("ICD2O", file: "two.zip")
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(first, among: liveCourses, archives: [first, second], backups: []),
            .otherCopiesRemain
        )
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(second, among: liveCourses, archives: [first, second], backups: []),
            .otherCopiesRemain
        )

        // Alone, the last archive of a gone course IS the only copy…
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(first, among: liveCourses, archives: [first], backups: []),
            .onlyRemainingCopy
        )

        // …unless a backup of the course still exists.
        let backup: BackupItem = BackupItem(
            courseCode: "ICD2O", backedUpAt: stamp,
            fileURL: URL(fileURLWithPath: "/w/courses/_backups/ICD2O/ICD2O_backup_x.zip"),
            maker: .teacher
        )
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(first, among: liveCourses, archives: [first], backups: [backup]),
            .otherCopiesRemain
        )

        // A surviving SECTION archive does not make a course archive
        // deletable-without-loss: it covers one section, not the course.
        let sectionOnly: ArchivedItem = archive("ICD2O", section: 1, file: "s1.zip")
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(first, among: liveCourses, archives: [first, sectionOnly], backups: []),
            .onlyRemainingCopy
        )
        // The reverse IS covered: a whole-course archive contains the section.
        XCTAssertEqual(
            WorkspaceModel.archiveStanding(sectionOnly, among: liveCourses, archives: [first, sectionOnly], backups: []),
            .otherCopiesRemain
        )
    }
}
