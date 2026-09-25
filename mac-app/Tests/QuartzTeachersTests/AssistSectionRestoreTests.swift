import XCTest
@testable import QuartzTeachers

/// Putting ONE section back to how it was when an assistant conversation
/// started.
///
/// What is pinned here is the SCOPE of the restore, because the scope is the
/// whole safety of the feature. The assistant's backup is a zip of the entire
/// course, and putting the entire course back would be a one-click way to
/// destroy an evening's marking in a section nobody was talking about. So each
/// test below is really the same question asked from a different side: does
/// anything outside this section move?
final class AssistSectionRestoreTests: XCTestCase {

    // MARK: - The section's own pages

    /// The first promise: a section goes back to how it was.
    @MainActor
    func testTheSectionsPagesComeBack() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()

        // The conversation makes a mess of section 1.
        try "ruined".write(to: fixture.sectionOnePageURL, atomically: true, encoding: .utf8)
        let strayURL: URL = fixture.courseURL.appendingPathComponent("section1/stray.md")
        try "stray".write(to: strayURL, atomically: true, encoding: .utf8)

        try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        let restored: String = try String(contentsOf: fixture.sectionOnePageURL, encoding: .utf8)
        XCTAssertEqual(restored, SectionRestoreFixture.sectionOnePage,
                       "The section's page comes back exactly as it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: strayURL.path),
                       "A file the conversation added to this section goes away again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.fileURL.path),
                      "The copy stays — a teacher may want it again")
    }

    /// The section folder is a folder inside Obsidian's vault, and its watcher
    /// is anchored to folder identity: swap the folder and Obsidian shows
    /// stale files until the vault is reopened. Only the CONTENTS may move.
    @MainActor
    func testTheSectionFolderItselfStaysInPlace() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }
        let fileManager: FileManager = FileManager.default

        let item: BackupItem = try fixture.backUp()
        let sectionURL: URL = fixture.courseURL.appendingPathComponent("section1")
        let identityBefore: Any? =
            try fileManager.attributesOfItem(atPath: sectionURL.path)[.systemFileNumber]

        try "ruined".write(to: fixture.sectionOnePageURL, atomically: true, encoding: .utf8)
        try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        let identityAfter: Any? =
            try fileManager.attributesOfItem(atPath: sectionURL.path)[.systemFileNumber]
        XCTAssertEqual(identityBefore as? Int, identityAfter as? Int,
                       "The section folder must be the SAME folder after a restore")
    }

    // MARK: - Everything that must NOT move

    /// The reason this exists at all. A teacher can be marking Section 2 in
    /// Obsidian while they chat about Section 1; a whole-course restore would
    /// throw that away without a word.
    @MainActor
    func testWorkInAnotherSectionSurvivesUntouched() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()

        // While the conversation about section 1 is going on, the teacher
        // writes tomorrow's class for section 2 in Obsidian.
        let marking: URL = fixture.courseURL.appendingPathComponent("section2/Unit 4, Day 2.md")
        try "an evening's work".write(to: marking, atomically: true, encoding: .utf8)
        try "section two, edited".write(to: fixture.sectionTwoPageURL, atomically: true, encoding: .utf8)

        try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: marking.path),
                      "A file added to ANOTHER section during the conversation must survive")
        XCTAssertEqual(try String(contentsOf: marking, encoding: .utf8), "an evening's work")
        XCTAssertEqual(try String(contentsOf: fixture.sectionTwoPageURL, encoding: .utf8),
                       "section two, edited",
                       "Another section's edited page must not be put back")
    }

    /// The part that is easy to miss. Publishing a SHARED page for one section
    /// writes into a file every section reads, so the section folder alone is
    /// not the whole of what a conversation could have changed — and the other
    /// sections' keys sit on the very same lines.
    @MainActor
    func testOnlyThisSectionsKeysComeBackInASharedPage() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()

        // The assistant publishes the shared outline for section 1; the
        // teacher, separately, publishes it for section 2.
        var edited: String = SectionRestoreFixture.sharedPage
        edited = edited.replacingOccurrences(of: "publishForSection1: false", with: "publishForSection1: true")
        edited = edited.replacingOccurrences(of: "publishForSection2: false", with: "publishForSection2: true")
        try edited.write(to: fixture.sharedPageURL, atomically: true, encoding: .utf8)

        try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        let after: String = try String(contentsOf: fixture.sharedPageURL, encoding: .utf8)
        XCTAssertEqual(
            AssistPageVisibility.statedPublishing(in: after, forSection: 1),
            false,
            "This section's publishing must go back to what the copy had"
        )
        XCTAssertEqual(
            AssistPageVisibility.statedPublishing(in: after, forSection: 2),
            true,
            "Another section's key in the SAME file must be left exactly as it is"
        )
        XCTAssertTrue(after.contains("The outline every section shares."),
                      "The page body is none of this restore's business")
        XCTAssertTrue(after.contains("title: Course Outline"),
                      "Nor is the rest of the frontmatter")
    }

    /// A key the conversation ADDED where the page had none is not "left as
    /// it is" — it did not exist when the conversation started, so it goes.
    @MainActor
    func testAKeyTheConversationAddedIsTakenBackOut() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()

        let added: String = try String(contentsOf: fixture.plainSharedPageURL, encoding: .utf8)
        let published: (text: String, outcome: FrontmatterWriteOutcome) = AssistPageVisibility.setting(
            published: false, in: added, forSection: 1, isSectionLocal: false
        )
        XCTAssertEqual(published.outcome, .written)
        try published.text.write(to: fixture.plainSharedPageURL, atomically: true, encoding: .utf8)

        try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        let after: String = try String(contentsOf: fixture.plainSharedPageURL, encoding: .utf8)
        XCTAssertFalse(after.contains("publishForSection1"),
                       "A key that was not there when the conversation started must not be left behind")
        XCTAssertEqual(after, SectionRestoreFixture.plainSharedPage,
                       "…and nothing else on the page moves either")
    }

    /// A shared page with no room for a new key cannot take this section's
    /// setting back: it is left exactly as it is, the restore returns how
    /// many such pages there were, and the transcript's sentence says so —
    /// "back to how it was" would not be true of that page (#182).
    @MainActor
    func testAPageWhoseSettingCouldNotBePutBackIsCountedAndSaid() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()
        let noRoom: String = "---\n  a: 1\n---\nThe outline every section shares.\n"
        try noRoom.write(to: fixture.sharedPageURL, atomically: true, encoding: .utf8)

        let notPutBack: Int = try CourseRestorer.restoreSection(
            1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL
        )
        XCTAssertEqual(notPutBack, 1)
        XCTAssertEqual(try String(contentsOf: fixture.sharedPageURL, encoding: .utf8), noRoom,
                       "The page is left byte for byte")

        let said: String = AssistSectionRestore.doneMessage(
            courseCode: "ICS3U", sectionNumber: 1, settingsNotPutBack: notPutBack
        )
        XCTAssertTrue(
            said.hasSuffix(AssistWording.sharedPagesWhoseSettingsCouldNotBePutBack(count: 1, section: "1")),
            "The restore must say it left a page's setting as it was: \(said)"
        )
        XCTAssertEqual(
            AssistSectionRestore.doneMessage(courseCode: "ICS3U", sectionNumber: 1, settingsNotPutBack: 0),
            AssistSectionRestore.doneMessage(courseCode: "ICS3U", sectionNumber: 1),
            "With nothing left undone the message is exactly what it always was"
        )
    }

    /// And a restore that could put everything back returns 0.
    @MainActor
    func testAnOrdinaryRestoreLeavesNothingUndone() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }
        let item: BackupItem = try fixture.backUp()
        XCTAssertEqual(
            try CourseRestorer.restoreSection(1, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL),
            0
        )
    }

    // MARK: - When there is nothing to go back to

    /// A conversation that has only READ has saved no copy. Asking to restore
    /// it is refused in words, not with a crash and not by doing something
    /// arbitrary.
    @MainActor
    func testRestoringWithNoBackupIsRefused() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        XCTAssertThrowsError(
            try AssistSectionRestore.restore(
                backupURL: nil,
                courseCode: "ICS3U",
                sectionNumber: 1,
                coursesDirectoryURL: fixture.coursesDirectoryURL
            )
        ) { error in
            let message: String = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("nothing to put back"), "Got: \(message)")
        }

        XCTAssertEqual(try String(contentsOf: fixture.sectionOnePageURL, encoding: .utf8),
                       SectionRestoreFixture.sectionOnePage,
                       "A refused restore must leave every file alone")
    }

    /// A backup that predates the section has nothing of it to give back, and
    /// says so rather than emptying the folder.
    @MainActor
    func testASectionMissingFromTheCopyIsRefused() throws {
        let fixture: SectionRestoreFixture = try SectionRestoreFixture()
        defer { fixture.tearDown() }

        let item: BackupItem = try fixture.backUp()

        XCTAssertThrowsError(
            try CourseRestorer.restoreSection(7, from: item, coursesDirectoryURL: fixture.coursesDirectoryURL)
        ) { error in
            let message: String = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("no Section 7"), "Got: \(message)")
        }
    }

    // MARK: - What the teacher is told

    /// The confirmation has to carry three things, and the third is the one
    /// that surprises people. A restore offered without it reads as free.
    @MainActor
    func testTheConfirmationSaysAllThreeThings() {
        let message: String = AssistSectionRestore.confirmationMessage(
            courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertTrue(message.contains("when this conversation started"),
                      "It must say what it goes back TO")
        XCTAssertTrue(message.contains("Your other sections are not touched."),
                      "It must say the other sections are safe")
        XCTAssertTrue(message.contains("Obsidian"),
                      "It must say the teacher's own work in this section goes too")
    }
}

/// A throwaway courses folder holding one course with two sections and two
/// shared pages: one carrying per-section keys, one carrying none.
@MainActor
struct SectionRestoreFixture {

    // MARK: - Stored properties

    let coursesDirectoryURL: URL
    let courseURL: URL
    let course: Course

    // MARK: - Computed properties

    var sectionOnePageURL: URL {
        return courseURL.appendingPathComponent("section1/index.md")
    }

    var sectionTwoPageURL: URL {
        return courseURL.appendingPathComponent("section2/index.md")
    }

    var sharedPageURL: URL {
        return courseURL.appendingPathComponent("Course Outline.md")
    }

    var plainSharedPageURL: URL {
        return courseURL.appendingPathComponent("Reference/Glossary.md")
    }

    /// A shared page as the course installer writes one: a per-section pair
    /// for every section, and a body that is nobody's business but the
    /// teacher's.
    static let sharedPage: String = """
    ---
    title: Course Outline
    createdSection1: 2026-08-01T07:00:00.000-0400
    publishForSection1: false
    createdSection2: 2026-08-01T07:00:00.000-0400
    publishForSection2: false
    ---
    The outline every section shares.
    """

    /// A shared page with no per-section keys at all — which is to say, one
    /// published in every section by Quartz's own default.
    static let plainSharedPage: String = """
    ---
    title: Glossary
    created: 2026-08-01T07:00:00.000-0400
    ---
    Words and what they mean.
    """

    static let sectionOnePage: String = """
    ---
    title: Section 1
    publish: true
    ---
    Section one's landing page.
    """

    // MARK: - Initializer

    init() throws {
        let fileManager: FileManager = FileManager.default
        coursesDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("assist-restore-\(UUID().uuidString)")
        courseURL = coursesDirectoryURL.appendingPathComponent("ICS3U")

        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section2"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Reference"), withIntermediateDirectories: true
        )

        try SectionRestoreFixture.sectionOnePage.write(
            to: courseURL.appendingPathComponent("section1/index.md"),
            atomically: true, encoding: .utf8
        )
        try "section two".write(
            to: courseURL.appendingPathComponent("section2/index.md"),
            atomically: true, encoding: .utf8
        )
        try SectionRestoreFixture.sharedPage.write(
            to: courseURL.appendingPathComponent("Course Outline.md"),
            atomically: true, encoding: .utf8
        )
        try SectionRestoreFixture.plainSharedPage.write(
            to: courseURL.appendingPathComponent("Reference/Glossary.md"),
            atomically: true, encoding: .utf8
        )

        let configValues: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Assist Restore Test Course",
            "section_numbers": [1, 2],
        ]
        let configData: Data = try JSONSerialization.data(withJSONObject: configValues)
        try configData.write(to: courseURL.appendingPathComponent("course_config.json"))

        let configuration: CourseConfiguration = CourseConfiguration(
            values: configValues, lastSavedData: configData
        )
        course = Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    // MARK: - Functions

    /// The copy the assistant saves before the first change of a conversation
    /// about section 1.
    func backUp() throws -> BackupItem {
        let backupURL: URL = try CourseArchiver.backUpCourse(
            course,
            coursesDirectoryURL: coursesDirectoryURL,
            madeBy: .assistant(sectionNumber: 1)
        )
        guard let item = BackupItem.from(fileURL: backupURL, courseCode: "ICS3U") else {
            throw SectionRestoreFixtureError.unreadableBackupName(backupURL.lastPathComponent)
        }
        return item
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: coursesDirectoryURL)
    }
}

enum SectionRestoreFixtureError: Error {
    case unreadableBackupName(String)
}
