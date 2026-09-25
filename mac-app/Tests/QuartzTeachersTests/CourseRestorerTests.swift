import XCTest
@testable import QuartzTeachers

/// Bringing an archived course or section back.
final class CourseRestorerTests: XCTestCase {

    // MARK: - Functions

    /// A working folder holding one course with two sections.
    @MainActor
    func makeWorkspace() throws -> (courses: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("restore-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("IZN2O")
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section2"), withIntermediateDirectories: true)
        try "# one".write(to: courseURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8)

        let configuration: [String: Any] = [
            "course_code": "IZN2O",
            "course_name": "Test Course",
            "section_numbers": [1, 2],
            "num_sections": 2,
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        let course: Course = Course(code: "IZN2O", directoryURL: courseURL, configuration: loaded)
        return (coursesURL, course)
    }

    @MainActor
    func testASectionComesBackAndIsListedAgain() throws {
        let (coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

        let archiveURL: URL = try CourseArchiver.archiveAndRemoveSection(1, from: course, coursesDirectoryURL: coursesURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: course.sectionDirectoryURL(forSection: 1).path))
        XCTAssertEqual(course.sectionNumbers, [2], "Archiving takes the section out of the settings")

        let item = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "IZN2O"))
        try CourseRestorer.restore(item, coursesDirectoryURL: coursesURL, courses: [course])

        XCTAssertTrue(FileManager.default.fileExists(atPath: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("index.md").path),
                      "The section's content should be back")
        let reloaded: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        XCTAssertEqual(reloaded.sectionNumbers, [1, 2], "The section must be listed again, in order")
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path), "A restored item is no longer archived")
    }

    @MainActor
    func testAWholeCourseComesBack() throws {
        let (coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

        let archiveURL: URL = try CourseArchiver.archiveAndRemoveCourse(course, coursesDirectoryURL: coursesURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: course.directoryURL.path))

        let item = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "IZN2O"))
        try CourseRestorer.restore(item, coursesDirectoryURL: coursesURL, courses: [])

        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("course_config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("section1/index.md").path))
    }

    @MainActor
    func testASectionWillNotRestoreWithoutItsCourse() throws {
        let (coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

        let archiveURL: URL = try CourseArchiver.archiveAndRemoveSection(1, from: course, coursesDirectoryURL: coursesURL)
        let item = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "IZN2O"))

        XCTAssertThrowsError(try CourseRestorer.restore(item, coursesDirectoryURL: coursesURL, courses: [])) { error in
            let message: String = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("Restore the course first"), "Got: \(message)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path), "A refused restore must leave the archive alone")
    }

    @MainActor
    func testNothingIsWrittenOverAnExistingSection() throws {
        let (coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

        let archiveURL: URL = try CourseArchiver.archiveAndRemoveSection(1, from: course, coursesDirectoryURL: coursesURL)
        // The teacher makes a new section 1 before restoring the old one.
        try FileManager.default.createDirectory(at: course.sectionDirectoryURL(forSection: 1), withIntermediateDirectories: true)
        try "# new work".write(to: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "IZN2O"))
        XCTAssertThrowsError(try CourseRestorer.restore(item, coursesDirectoryURL: coursesURL, courses: [course]))

        let survived: String = try String(contentsOf: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("index.md"), encoding: .utf8)
        XCTAssertEqual(survived, "# new work", "Newer work must not be overwritten")
    }

    @MainActor
    func testACourseWillNotRestoreOverOneThatIsBack() throws {
        let (coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: coursesURL.deletingLastPathComponent()) }

        let archiveURL: URL = try CourseArchiver.archiveAndRemoveCourse(course, coursesDirectoryURL: coursesURL)
        try FileManager.default.createDirectory(at: course.directoryURL, withIntermediateDirectories: true)

        let item = try XCTUnwrap(ArchivedItem.from(fileURL: archiveURL, courseCode: "IZN2O"))
        XCTAssertThrowsError(try CourseRestorer.restore(item, coursesDirectoryURL: coursesURL, courses: [])) { error in
            let message: String = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("already in Courses & Clubs"), "Got: \(message)")
        }
    }

    // MARK: - A value that lives on the lines BELOW a per-section key (#182)

    /// Every line of a page that belongs to NO per-section key — the lines a
    /// restore of one section must leave exactly where they are.
    @MainActor
    private func linesOutsideEverySection(of pageText: String) -> [String] {
        var owned: Set<Int> = []
        for index in CourseRestorer.perSectionLineIndices(forSection: nil, in: pageText) {
            owned.insert(index)
        }
        var kept: [String] = []
        for (index, line) in pageText.components(separatedBy: "\n").enumerated() where !owned.contains(index) {
            kept.append(line)
        }
        return kept
    }

    /// Restores section 1 and checks what every row checks: the bytes, what
    /// this app then says about BOTH sections, and that nothing belonging to
    /// no section moved. The whole-file cases both platforms run are
    /// `course-management.json → backups.restoringOneSectionsKeys`; these are
    /// the shapes beside them, each measured on the site 2026-09-25.
    @MainActor
    private func checkRestore(
        live: String,
        backup: String,
        expected: String,
        sectionOne: PageVisibilityAnswer,
        sectionTwo: PageVisibilityAnswer,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let restored: (text: String, couldNotBePutBack: Bool) =
            CourseRestorer.settingPerSectionKeys(1, in: live, asIn: backup)
        XCTAssertEqual(restored.text, expected, message, file: file, line: line)
        XCTAssertFalse(restored.couldNotBePutBack, message, file: file, line: line)
        XCTAssertEqual(
            PageVisibilityReader.answer(in: restored.text, forSection: 1), sectionOne,
            "\(message) — section 1", file: file, line: line
        )
        XCTAssertEqual(
            PageVisibilityReader.answer(in: restored.text, forSection: 2), sectionTwo,
            "\(message) — section 2", file: file, line: line
        )
        XCTAssertEqual(
            linesOutsideEverySection(of: restored.text), linesOutsideEverySection(of: live),
            "\(message) — a restore of one section moved a line belonging to no section",
            file: file, line: line
        )
    }

    /// Restoring section 1 never moves section 2 — the finding the plan for
    /// #182 added: placed after the last line that merely NAMES a key,
    /// section 1's line split section 2's `>-` from its `  false` and section
    /// 2 was PUBLISHED. Measured 2026-09-25: section 2 hidden before and after.
    @MainActor
    func testRestoringSectionOneLeavesSectionTwoHidden() {
        checkRestore(
            live: "---\ntitle: x\npublishForSection2: >-\n  false\n---\nBody.\n",
            backup: "---\npublishForSection1: false\ntitle: x\n---\nBody.\n",
            expected: "---\ntitle: x\npublishForSection2: >-\n  false\npublishForSection1: false\n---\nBody.\n",
            sectionOne: .hidden, sectionTwo: .cannotTell,
            "Section 2's value is a block scalar this app will not read, and the site hides it"
        )
    }

    /// The other shapes, beside the shared cases: a backup key over a live
    /// mapping, a column-0 list at the end of the block, a block scalar at the
    /// end, and a note under a key that is dropped while section 2 stays.
    @MainActor
    func testTheBackupsKeysComeBackWithTheirLinesAndTheLiveOnesGoWithTheirs() {
        checkRestore(
            live: "---\npublishForSection1:\n  a: 1\ntitle: x\n---\nBody.\n",
            backup: "---\npublishForSection1: true\ntitle: x\n---\nBody.\n",
            expected: "---\npublishForSection1: true\ntitle: x\n---\nBody.\n",
            sectionOne: .visible, sectionTwo: .saysNothing,
            "The mapping goes with the live key it belonged to"
        )
        checkRestore(
            live: "---\ntitle: x\ntags:\n- a\n---\nBody.\n",
            backup: "---\npublishForSection1: false\n---\nBody.\n",
            expected: "---\ntitle: x\ntags:\n- a\npublishForSection1: false\n---\nBody.\n",
            sectionOne: .hidden, sectionTwo: .saysNothing,
            "A column-0 list at the end of the block: the new key goes after it, at column 0"
        )
        checkRestore(
            live: "---\ntitle: x\ndescription: |\n  one\n---\nBody.\n",
            backup: "---\npublishForSection1: false\n---\nBody.\n",
            expected: "---\ntitle: x\ndescription: |\n  one\npublishForSection1: false\n---\nBody.\n",
            sectionOne: .hidden, sectionTwo: .saysNothing,
            "A block scalar at the end of the block: a column-0 key ends it"
        )
        checkRestore(
            live: "---\npublishForSection1: false\n  # held back\npublishForSection2: true\n---\nBody.\n",
            backup: "---\npublishForSection1: true\npublishForSection2: true\n---\nBody.\n",
            expected: "---\npublishForSection1: true\npublishForSection2: true\n---\nBody.\n",
            sectionOne: .visible, sectionTwo: .visible,
            "The dropped key's indented note goes with it, and section 2's line stays"
        )
    }

    /// A page with no column-0 level for a new key is left byte for byte, and
    /// the restore SAYS it could not put the setting back — the count
    /// `restoreSection` returns, and the sentence the teacher reads.
    /// [Issue #182](https://github.com/russellgordon/plantoir/issues/182).
    @MainActor
    func testAPageWithNoRoomForTheBackupsKeyIsLeftAsItIsAndCounted() {
        let live: String = "---\n  a: 1\n---\nBody.\n"
        let restored: (text: String, couldNotBePutBack: Bool) = CourseRestorer.settingPerSectionKeys(
            1, in: live, asIn: "---\npublishForSection1: false\n---\nBody.\n"
        )
        XCTAssertEqual(restored.text, live)
        XCTAssertTrue(restored.couldNotBePutBack)

        let nothingToPutBack: (text: String, couldNotBePutBack: Bool) = CourseRestorer.settingPerSectionKeys(
            1, in: live, asIn: "---\ntitle: x\n---\nBody.\n"
        )
        XCTAssertEqual(nothingToPutBack.text, live)
        XCTAssertFalse(
            nothingToPutBack.couldNotBePutBack,
            "A backup with no key for this section had nothing to put back, so nothing was left undone"
        )
    }
}

/// What an archive leaves out.
final class ArchiveExclusionTests: XCTestCase {

    // MARK: - Functions

    /// Lists an archive's entries using the system's own tool.
    func entries(in archiveURL: URL) throws -> String {
        let lister: Process = Process()
        lister.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        lister.arguments = ["-l", archiveURL.path]
        let output: Pipe = Pipe()
        lister.standardOutput = output
        try lister.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        lister.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @MainActor
    func testBuiltOutputIsLeftOutOfAnArchive() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("exclude-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("IZN2O")
        let fileManager: FileManager = FileManager.default
        defer { try? fileManager.removeItem(at: root) }

        // The course a teacher wrote…
        try fileManager.createDirectory(at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try "# real work".write(to: courseURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8)
        let configuration: [String: Any] = ["course_code": "IZN2O", "section_numbers": [1]]
        try JSONSerialization.data(withJSONObject: configuration).write(to: courseURL.appendingPathComponent("course_config.json"))

        // …and the parts that are rebuilt, which should not be archived.
        try fileManager.createDirectory(at: courseURL.appendingPathComponent(".merged_output/section1/public"), withIntermediateDirectories: true)
        try "built".write(to: courseURL.appendingPathComponent(".merged_output/section1/public/index.html"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: courseURL.appendingPathComponent(".merged_output/section1/node_modules/left-pad"), withIntermediateDirectories: true)
        try "dep".write(to: courseURL.appendingPathComponent(".merged_output/section1/node_modules/left-pad/index.js"), atomically: true, encoding: .utf8)

        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        let course: Course = Course(code: "IZN2O", directoryURL: courseURL, configuration: loaded)
        let archiveURL: URL = try CourseArchiver.archiveAndRemoveCourse(course, coursesDirectoryURL: coursesURL)

        let listing: String = try entries(in: archiveURL)
        XCTAssertTrue(listing.contains("section1/index.md"), "The teacher's own work must be archived")
        XCTAssertTrue(listing.contains("course_config.json"), "So must the course's settings")
        XCTAssertFalse(listing.contains("index.html"), "Built output must not be archived — it is rebuilt from the content")
        XCTAssertFalse(listing.contains("node_modules"), "Nor its dependencies")
    }
}
