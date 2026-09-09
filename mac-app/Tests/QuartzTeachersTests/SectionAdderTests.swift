import XCTest
@testable import QuartzTeachers

/// Adding a brand-new section to an existing course — the reverse of
/// removing one.
final class SectionAdderTests: XCTestCase {

    // MARK: - Functions

    /// A working folder holding one course with sections 1 and 3 — a gap on
    /// purpose, since a teacher's section numbers need not be contiguous.
    @MainActor
    func makeWorkspace() throws -> (root: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("add-section-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section3"), withIntermediateDirectories: true)

        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 3],
            "num_sections": 2,
            "per_section_folders": ["All Classes", "Notes"],
            "per_section_files": ["Snippets.md", "Private Notes.md"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: courseURL.appendingPathComponent("course_config.json"))
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        return (root, course)
    }

    @MainActor
    func testAddingASectionScaffoldsWhatTheWizardWould() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try SectionAdder.addSection(2, to: course)

        let sectionURL: URL = course.sectionDirectoryURL(forSection: 2)
        let indexText: String = try String(contentsOf: sectionURL.appendingPathComponent("index.md"), encoding: .utf8)
        XCTAssertTrue(indexText.contains("title: Grade 11 Introduction to Computer Science, Section 2"),
                      "The landing page is titled the way the wizard titles one")
        XCTAssertTrue(indexText.contains("publish: true"))

        for folderName in ["All Classes", "Notes"] {
            let folderIndex: URL = sectionURL.appendingPathComponent(folderName).appendingPathComponent("index.md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: folderIndex.path),
                          "\(folderName) should be scaffolded with its own index")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sectionURL.appendingPathComponent("Snippets.md").path),
                      "Per-section files should be scaffolded too")

        // Even with no sibling to imitate (the fixture's sections are bare
        // folders), the teacher's private pages start held back — that is
        // what keeps them from being published.
        let privateNotes: String = try String(contentsOf: sectionURL.appendingPathComponent("Private Notes.md"), encoding: .utf8)
        XCTAssertTrue(privateNotes.contains("publish: false"),
                      "Private Notes.md must start unpublished")
        let snippets: String = try String(contentsOf: sectionURL.appendingPathComponent("Snippets.md"), encoding: .utf8)
        XCTAssertTrue(snippets.contains("publish: true"),
                      "An ordinary per-section file still starts published")

        let reloaded: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        XCTAssertEqual(reloaded.sectionNumbers, [1, 2, 3], "The new number joins the settings, in order")
    }

    @MainActor
    func testAClubGetsNoGradeInItsTitle() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        // Rename the course a club: the code has no grade digit.
        course.configuration.courseName = "Coding Club"
        XCTAssertEqual(SectionAdder.gradeLabel(forCourseCode: "CODING"), "")
        XCTAssertEqual(SectionAdder.gradeLabel(forCourseCode: "SNC1W"), "Grade 9")
        XCTAssertEqual(SectionAdder.gradeLabel(forCourseCode: "ICS3U"), "Grade 11")
        XCTAssertEqual(SectionAdder.gradeLabel(forCourseCode: "ABC5X"), "Grade ?")
    }

    @MainActor
    func testAnExistingSectionIsRefused() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try SectionAdder.addSection(3, to: course)) { error in
            XCTAssertTrue(error.localizedDescription.contains("already exists"),
                          "The refusal should say the section already exists")
        }
        let reloaded: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        XCTAssertEqual(reloaded.sectionNumbers, [1, 3], "A refused add changes nothing")
    }

    @MainActor
    func testALeftoverFolderIsNeverWrittenOver() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        // A section2 folder on disk but not in the settings — perhaps put
        // there by hand. Its content must survive an attempted add.
        let strayURL: URL = course.sectionDirectoryURL(forSection: 2)
        try FileManager.default.createDirectory(at: strayURL, withIntermediateDirectories: true)
        try "precious work".write(to: strayURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SectionAdder.addSection(2, to: course))
        let preserved: String = try String(contentsOf: strayURL.appendingPathComponent("notes.md"), encoding: .utf8)
        XCTAssertEqual(preserved, "precious work")
    }

    /// The Exemplar bug: a course whose sections keep some pages as
    /// unpublished drafts grew a new section whose copies of those pages
    /// were suddenly published. A new section must behave like the sections
    /// beside it, so each scaffolded file carries its sibling's frontmatter.
    @MainActor
    func testANewSectionKeepsItsSiblingsDraftsAndFlags() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let siblingSnippets: String = """
        ---
        title: Snippets
        draft: true
        created: 2020-01-15T07:00:00.000-0400
        transcludeTitleSize: h2
        ---
        Kept out of the published site on purpose.
        """
        try siblingSnippets.write(to: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("Snippets.md"), atomically: true, encoding: .utf8)

        let siblingIndex: String = """
        ---
        title: Grade 11 Introduction to Computer Science, Section 1
        created: 2020-01-15T07:00:00.000-0400
        enableToc: false
        excludeBacklinks: true
        draft: false
        ---
        # Most Recent Class
        """
        try siblingIndex.write(to: course.sectionDirectoryURL(forSection: 1).appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        try SectionAdder.addSection(2, to: course)

        let newSnippets: String = try String(contentsOf: course.sectionDirectoryURL(forSection: 2).appendingPathComponent("Snippets.md"), encoding: .utf8)
        XCTAssertTrue(newSnippets.contains("draft: true"),
                      "A page the siblings keep as a draft must start as a draft here too")
        XCTAssertTrue(newSnippets.contains("transcludeTitleSize: h2"),
                      "Display flags the teacher set should carry over")
        XCTAssertFalse(newSnippets.contains("2020-01-15"),
                       "created: should be freshened, not copied. The sibling's date is "
                       + "deliberately in the PAST: this assertion used to use a date that was "
                       + "\"today\" when it was written, and it began failing on 2026-09-08 when "
                       + "the clock reached it — the freshened value it was proving correct was "
                       + "the very string it was checking for.")

        let newIndex: String = try String(contentsOf: course.sectionDirectoryURL(forSection: 2).appendingPathComponent("index.md"), encoding: .utf8)
        XCTAssertTrue(newIndex.contains("title: Grade 11 Introduction to Computer Science, Section 2"),
                      "The landing page takes its sibling's title with the number swapped")
        XCTAssertTrue(newIndex.contains("enableToc: false"))
        XCTAssertTrue(newIndex.contains("excludeBacklinks: true"))
    }

    /// A page at the course level belongs to every section, and each
    /// section decides for itself when it appeared and whether it is
    /// published. A section added later must gain its own pair of keys, or
    /// it builds those pages with no date and no publishing state.
    @MainActor
    func testAddingASectionGivesCourseLevelPagesTheirOwnKeys() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shared: String = """
        ---
        title: Learning Goals
        createdSection1: 2026-09-08T07:00:00.000
        publishForSection1: true
        createdSection3: 2026-09-08T07:00:00.000
        publishForSection3: false
        enableToc: false
        ---
        A page with `draft: true` in its frontmatter is skipped.
        """
        let sharedURL: URL = course.directoryURL.appendingPathComponent("Learning Goals.md")
        try shared.write(to: sharedURL, atomically: true, encoding: .utf8)

        try SectionAdder.addSection(2, to: course)

        let updated: String = try String(contentsOf: sharedURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("createdSection2:"),
                      "The new section needs its own created date")
        XCTAssertTrue(updated.contains("publishForSection2: true"),
                      "It takes the LOWEST existing section's publishing state")
        XCTAssertTrue(updated.contains("createdSection1: 2026-09-08T07:00:00.000"),
                      "The sections already there are untouched")
        XCTAssertTrue(updated.contains("publishForSection3: false"),
                      "Including one deliberately held back")
        XCTAssertTrue(updated.contains("enableToc: false"),
                      "Everything else in the frontmatter survives")
        XCTAssertEqual(updated.components(separatedBy: "draft: true").count - 1, 1,
                       "Prose that mentions draft: true is not metadata and is left alone")
    }

    /// A course made before the `draft:` → `publish:` rename still carries
    /// `draftSectionN`, whose polarity is the OPPOSITE. Carrying that value
    /// across unchanged would publish a page the teacher had held back, so
    /// the old key is read and inverted.
    @MainActor
    func testALegacyDraftSectionKeyIsReadAndInverted() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shared: String = """
        ---
        title: Held Back Everywhere
        createdSection1: 2026-09-08T07:00:00.000
        draftSection1: true
        ---
        Not ready for students yet.
        """
        let sharedURL: URL = course.directoryURL.appendingPathComponent("Held Back Everywhere.md")
        try shared.write(to: sharedURL, atomically: true, encoding: .utf8)

        try SectionAdder.addSection(2, to: course)

        let updated: String = try String(contentsOf: sharedURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("publishForSection2: false"),
                      "draftSection1: true means held back, so the new section is publish false")
        XCTAssertFalse(updated.contains("publishForSection2: true"),
                       "Inverting the polarity is the whole point — this would publish it")
        XCTAssertTrue(updated.contains("draftSection1: true"),
                      "The existing section's own key is left exactly as it was")
    }

    /// A page written with plain `created:` applies to every section
    /// already, including the new one. Splitting it would change what the
    /// existing sections show, so it is left exactly as it is.
    @MainActor
    func testAPlainCreatedDateIsLeftAlone() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let shared: String = """
        ---
        title: Help Sessions
        created: 2026-09-08T07:00:00.000
        draft: false
        ---
        Thursdays at lunch.
        """
        let sharedURL: URL = course.directoryURL.appendingPathComponent("Help Sessions.md")
        try shared.write(to: sharedURL, atomically: true, encoding: .utf8)

        try SectionAdder.addSection(2, to: course)

        let updated: String = try String(contentsOf: sharedURL, encoding: .utf8)
        XCTAssertEqual(updated, shared, "A page with no per-section keys is not rewritten")
    }

    /// The other Exemplar bug: SNC1W is named "Grade 9 Science", and the
    /// scaffolded title read "Grade 9 Grade 9 Science, Section 3".
    @MainActor
    func testTheGradeSwitchAloneDecidesTheTitle() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        course.configuration.courseName = "Introduction to Computer Science"
        XCTAssertEqual(SectionAdder.sectionTitle(for: course, sectionNumber: 2),
                       "Grade 11 Introduction to Computer Science, Section 2")

        // Deliberately literal: the switch alone decides, even when the
        // name already carries the grade — the settings WARN about the
        // repetition, and resolving it is the teacher's call.
        course.configuration.courseName = "Computer Science, Grade 11, U"
        XCTAssertEqual(SectionAdder.sectionTitle(for: course, sectionNumber: 2),
                       "Grade 11 Computer Science, Grade 11, U, Section 2")

        // The switch is per section, like the marker: off for this one
        // turns the grade off entirely, and only here.
        course.configuration.setShowsGradeInTitle(false, forSection: 2)
        course.configuration.courseName = "Introduction to Computer Science"
        XCTAssertEqual(SectionAdder.sectionTitle(for: course, sectionNumber: 2),
                       "Introduction to Computer Science, Section 2")
        XCTAssertTrue(course.configuration.showsGradeInTitle(forSection: 3),
                      "Another section keeps its own default")
    }

    /// The warning that keeps the literal switch honest: it appears
    /// exactly when the grade would repeat, and never otherwise.
    @MainActor
    func testTheGradeRepetitionWarning() {
        XCTAssertNotNil(CourseConfiguration.gradeInTitleWarning(
            courseName: "Computer Science, Grade 11, U", courseCode: "ICS3U", showsGrade: true))
        XCTAssertNotNil(CourseConfiguration.gradeInTitleWarning(
            courseName: "Grade 11 Computer Science", courseCode: "ICS3U", showsGrade: true))
        XCTAssertNil(CourseConfiguration.gradeInTitleWarning(
            courseName: "Computer Science", courseCode: "ICS3U", showsGrade: true),
            "A clean name earns no warning")
        XCTAssertNil(CourseConfiguration.gradeInTitleWarning(
            courseName: "Computer Science, Grade 11, U", courseCode: "ICS3U", showsGrade: false),
            "With the switch off there is nothing to warn about")
        XCTAssertNil(CourseConfiguration.gradeInTitleWarning(
            courseName: "Coding Club", courseCode: "CODING", showsGrade: true),
            "A club has no grade to repeat")
    }

    @MainActor
    func testTheSuggestionIsTheSmallestFreeNumber() {
        XCTAssertEqual(SectionAdder.suggestedNumber(existing: [1, 3]), 2)
        XCTAssertEqual(SectionAdder.suggestedNumber(existing: [1, 2, 3]), 4)
        XCTAssertEqual(SectionAdder.suggestedNumber(existing: [2, 4, 5]), 1,
                       "Sections need not start at 1, so 1 can be the one that is missing")
        XCTAssertEqual(SectionAdder.suggestedNumber(existing: []), 1)
    }

    @MainActor
    func testTypedEntriesAreJudgedLikeTheWizardJudgesThem() {
        // Nothing typed yet: no warning, but nothing to add either.
        XCTAssertNil(SectionAdder.entryProblem("", existing: [1], courseCode: "ICS3U"))
        XCTAssertFalse(SectionAdder.entryIsAddable("", existing: [1]))

        // A duplicate is called out by name.
        XCTAssertEqual(SectionAdder.entryProblem("1", existing: [1], courseCode: "ICS3U"),
                       "Section 1 of ICS3U already exists.")
        XCTAssertFalse(SectionAdder.entryIsAddable("1", existing: [1]))

        // Zero is not a section, said the same careful way the wizard says it.
        XCTAssertEqual(SectionAdder.entryProblem("0", existing: [1], courseCode: "ICS3U"),
                       "“0” isn’t a section number — sections are 1 or higher.")

        // A fresh number passes without comment.
        XCTAssertNil(SectionAdder.entryProblem("2", existing: [1], courseCode: "ICS3U"))
        XCTAssertTrue(SectionAdder.entryIsAddable("2", existing: [1]))
    }

    @MainActor
    func testTheTimestampMatchesTheWizardsForm() {
        let stamp: String = SectionAdder.timestamp(for: Date(timeIntervalSince1970: 1_754_800_000))
        // e.g. 2026-08-10T14:26:40.000-0400 — digits, T, and a zone offset
        // with no colon, exactly as the wizard writes it.
        let pattern: String = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000[+-]\d{4}$"#
        XCTAssertNotNil(stamp.range(of: pattern, options: .regularExpression),
                        "\(stamp) should match the wizard's created: form")
    }

    /// When a section is added to a course that already has a sibling section,
    /// all class pages in All Classes/, transclusions, notes, links, and body
    /// content are replicated into the new section.
    @MainActor
    func testAddingASectionCopiesAllClassPagesAndBodiesFromSiblingSection() throws {
        let (root, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let sec1URL: URL = course.sectionDirectoryURL(forSection: 1)
        let allClassesURL: URL = sec1URL.appendingPathComponent("All Classes")
        try FileManager.default.createDirectory(at: allClassesURL, withIntermediateDirectories: true)

        let siblingIndex: String = """
        ---
        title: Grade 11 Introduction to Computer Science, Section 1
        created: 2026-08-10T14:30:00.000-0400
        enableToc: false
        excludeBacklinks: true
        publish: true
        ---
        # Most Recent Class
        ![[Unit 1, Day 2]]

        ![[Help Sessions]]
        ![[Key Links]]
        """
        try siblingIndex.write(to: sec1URL.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let siblingDay1: String = """
        ---
        title: Unit 1, Day 1
        publish: true
        created: 2026-09-08T07:00:00.000+0000
        tags:
          - unit-1
        ---
        ## Agenda

        1. Welcome to ICS3U
        """
        try siblingDay1.write(to: allClassesURL.appendingPathComponent("Unit 1, Day 1.md"), atomically: true, encoding: .utf8)

        let siblingDay2: String = """
        ---
        title: Unit 1, Day 2
        publish: true
        created: 2026-09-09T07:00:00.000+0000
        tags:
          - unit-1
        ---
        ## Agenda

        1. Variables and types
        """
        try siblingDay2.write(to: allClassesURL.appendingPathComponent("Unit 1, Day 2.md"), atomically: true, encoding: .utf8)

        let siblingKeyLinks: String = """
        ---
        title: Key Links
        publish: true
        created: 2026-08-10T14:30:00.000-0400
        ---
        - [[How This Class Works]]
        - [[Learning Goals]]
        """
        try siblingKeyLinks.write(to: sec1URL.appendingPathComponent("Key Links.md"), atomically: true, encoding: .utf8)

        let siblingPrivateNotes: String = """
        ---
        title: Private Notes
        publish: false
        created: 2026-08-10T14:30:00.000-0400
        ---
        %% Private teacher observations %%
        """
        try siblingPrivateNotes.write(to: sec1URL.appendingPathComponent("Private Notes.md"), atomically: true, encoding: .utf8)

        try SectionAdder.addSection(2, to: course)

        let sec2URL: URL = course.sectionDirectoryURL(forSection: 2)

        // Root index has new section title, freshened created date, and preserved body
        let index2: String = try String(contentsOf: sec2URL.appendingPathComponent("index.md"), encoding: .utf8)
        XCTAssertTrue(index2.contains("title: Grade 11 Introduction to Computer Science, Section 2"))
        XCTAssertTrue(index2.contains("# Most Recent Class"))
        XCTAssertTrue(index2.contains("![[Unit 1, Day 2]]"))
        XCTAssertTrue(index2.contains("![[Help Sessions]]"))

        // Class pages in All Classes/ are replicated with original dates and bodies
        let day1Path: URL = sec2URL.appendingPathComponent("All Classes/Unit 1, Day 1.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: day1Path.path))
        let day1Text: String = try String(contentsOf: day1Path, encoding: .utf8)
        XCTAssertTrue(day1Text.contains("created: 2026-09-08T07:00:00.000+0000"), "Class schedule date is preserved")
        XCTAssertTrue(day1Text.contains("Welcome to ICS3U"))
        XCTAssertTrue(day1Text.contains("tags:"))

        let day2Path: URL = sec2URL.appendingPathComponent("All Classes/Unit 1, Day 2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: day2Path.path))
        let day2Text: String = try String(contentsOf: day2Path, encoding: .utf8)
        XCTAssertTrue(day2Text.contains("Variables and types"))

        // Key Links and Private Notes bodies are preserved
        let keyLinksText: String = try String(contentsOf: sec2URL.appendingPathComponent("Key Links.md"), encoding: .utf8)
        XCTAssertTrue(keyLinksText.contains("- [[How This Class Works]]"))
        XCTAssertTrue(keyLinksText.contains("- [[Learning Goals]]"))

        let privateNotesText: String = try String(contentsOf: sec2URL.appendingPathComponent("Private Notes.md"), encoding: .utf8)
        XCTAssertTrue(privateNotesText.contains("publish: false"))
        XCTAssertTrue(privateNotesText.contains("%% Private teacher observations %%"))
    }
}
