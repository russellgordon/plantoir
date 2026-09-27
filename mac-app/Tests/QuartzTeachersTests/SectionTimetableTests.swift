import XCTest
@testable import QuartzTeachers

/// Remembering when a section's classes actually meet.
///
/// The rule these tests exist to hold: a partial list is REFUSED, never
/// half-stored. A half-remembered timetable does not announce itself — it gets
/// trusted, and then dates the wrong classes.
final class SectionTimetableTests: XCTestCase {

    // MARK: - Functions

    /// A working folder holding one course with sections 1 and 2.
    @MainActor
    func makeWorkspace() throws -> (root: URL, coursesURL: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("timetable-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section2/All Classes"), withIntermediateDirectories: true
        )

        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "per_section_files": ["Snippets.md"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        return (root, coursesURL, course)
    }

    // MARK: - A partial list is refused

    /// The headline rule. One unreadable entry turns away the WHOLE list —
    /// storing the eleven dates that did read would leave a timetable that
    /// looks complete and is not.
    @MainActor
    func testAPartialTimetableIsRefusedRatherThanHalfStored() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let given: [String] = ["2026-09-08", "Sept 10", "2026-09-14"]
        XCTAssertThrowsError(
            try SectionTimetableStore.planRememberTimetable(
                dates: given, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Sept 10"),
                          "The refusal should name the entry that could not be read")
            XCTAssertTrue(error.localizedDescription.contains("nothing was remembered"),
                          "And say plainly that nothing at all was stored")
        }

        let fileURL: URL = SectionTimetableStore.fileURL(forSection: 1, in: course)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "A refused list must leave no file behind — not even the dates that did read")
    }

    /// A day that does not exist is just as partial as a day that does not
    /// parse: 2026-02-30 must not quietly become the 1st of March.
    @MainActor
    func testADateThatIsNotARealDayIsRefused() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(CalendarDay(text: "2026-02-30"))
        XCTAssertNil(CalendarDay(text: "2026-9-8"), "One written form, strictly")
        XCTAssertNotNil(CalendarDay(text: "2026-02-28"))

        XCTAssertThrowsError(
            try SectionTimetableStore.planRememberTimetable(
                dates: ["2026-09-08", "2026-02-30"], source: "by hand", forSection: 1, in: course
            )
        )
    }

    @MainActor
    func testAnEmptyListIsRefused() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try SectionTimetableStore.planRememberTimetable(
                dates: ["", "   "], source: "by hand", forSection: 1, in: course
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("nothing to remember"))
        }
    }

    /// The same rule at the other end: a file on disk that cannot be read
    /// WHOLE is ignored rather than half-trusted.
    @MainActor
    func testAHalfRememberedFileIsIgnoredRatherThanHalfTrusted() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL: URL = SectionTimetableStore.fileURL(forSection: 1, in: course)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let handWritten: String = """
        { "section": 1,
          "dates": ["2026-09-08", "Thursday", "2026-09-14"],
          "source": "typed in by hand",
          "recorded": "2026-08-14" }
        """
        try handWritten.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SectionTimetableStore.read(forSection: 1, in: course)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Thursday"))
            XCTAssertTrue(error.localizedDescription.contains("half-trusted"))
        }
    }

    // MARK: - Remembering, and reading back

    @MainActor
    func testRememberingWritesTheSharedFileFormat() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        // Out of order and with a repeat, as a teacher reading a spreadsheet
        // aloud might well give them.
        let given: [String] = ["2026-09-10", "2026-09-08", "2026-09-10", "2026-09-14"]
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: given,
            source: "timetable.xlsx, block H",
            forSection: 1,
            in: course,
            today: CalendarDay(year: 2026, month: 8, day: 14)!
        )

        XCTAssertEqual(plan.dates.count, 3, "Repeats collapse; nothing else is dropped")
        XCTAssertEqual(plan.dates[0].text, "2026-09-08", "And they come back in order")
        XCTAssertTrue(plan.description.contains("Remember 3 class dates"))
        XCTAssertTrue(plan.description.contains("timetable.xlsx, block H"),
                      "The plan reads back where the dates came from, so a stale answer is recognisable")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: plan.fileURL.path),
            "Planning changes nothing on disk"
        )

        try SectionTimetableStore.applyRememberTimetable(plan)

        // Where the Windows app looks for it, character for character.
        XCTAssertEqual(
            plan.fileURL.path,
            course.directoryURL.appendingPathComponent(".internal/timetable/section1.json").path
        )

        let written: Data = try Data(contentsOf: plan.fileURL)
        let decoded: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: written) as? [String: Any]
        )
        XCTAssertEqual(decoded["section"] as? Int, 1)
        XCTAssertEqual(decoded["dates"] as? [String], ["2026-09-08", "2026-09-10", "2026-09-14"])
        XCTAssertEqual(decoded["source"] as? String, "timetable.xlsx, block H")
        XCTAssertEqual(decoded["recorded"] as? String, "2026-08-14")

        let readBack: SectionTimetable = try XCTUnwrap(
            try SectionTimetableStore.read(forSection: 1, in: course)
        )
        XCTAssertEqual(readBack.datesText, ["2026-09-08", "2026-09-10", "2026-09-14"])
        XCTAssertEqual(readBack.source, "timetable.xlsx, block H")
        XCTAssertEqual(readBack.dates(onOrAfter: CalendarDay(year: 2026, month: 9, day: 10)!).count, 2)
        XCTAssertEqual(readBack.spareDates(after: 2), 1)

        // Each section remembers its own days.
        XCTAssertNil(try SectionTimetableStore.read(forSection: 2, in: course))
    }

    @MainActor
    func testRememberingTheSameDatesTwiceChangesNothing() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let dates: [String] = ["2026-09-08", "2026-09-10"]
        let first: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: dates, source: "block H", forSection: 1, in: course
        )
        XCTAssertFalse(first.changesNothing)
        try SectionTimetableStore.applyRememberTimetable(first)

        let second: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: dates, source: "block H", forSection: 1, in: course
        )
        XCTAssertTrue(second.changesNothing)
        XCTAssertTrue(second.description.contains("nothing would change"))

        // A different list says what it is replacing, so the teacher can spot
        // a mistake before it is made.
        let third: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2027-01-05"], source: "block D, semester 2", forSection: 1, in: course
        )
        XCTAssertTrue(third.description.contains("This replaces the 2 dates"))
    }

    // MARK: - It travels with the course

    /// The whole reason the file lives inside the course rather than beside
    /// the app: back the course up, lose the folder, restore, and the class
    /// dates are still there.
    @MainActor
    func testTheTimetableTravelsThroughBackupAndRestore() async throws {
        let (root, coursesURL, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10"], source: "timetable.xlsx, block H", forSection: 1, in: course
        )
        try SectionTimetableStore.applyRememberTimetable(plan)

        let backupURL: URL = try await CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesURL)

        // The teacher wipes the remembered dates — or moves machines, or an
        // Obsidian sync eats the hidden folder.
        try FileManager.default.removeItem(at: course.directoryURL.appendingPathComponent(".internal"))
        XCTAssertNil(try SectionTimetableStore.read(forSection: 1, in: course))

        let item: BackupItem = try XCTUnwrap(BackupItem.from(fileURL: backupURL, courseCode: "ICS3U"))
        try CourseRestorer.restoreBackup(item, coursesDirectoryURL: coursesURL)

        let restored: SectionTimetable = try XCTUnwrap(
            try SectionTimetableStore.read(forSection: 1, in: course)
        )
        XCTAssertEqual(restored.datesText, ["2026-09-08", "2026-09-10"],
                       "The dates must survive the round trip, or the course comes back subtly wrong")
        XCTAssertEqual(restored.source, "timetable.xlsx, block H")
    }

    // MARK: - Calendar days

    @MainActor
    func testACalendarDayIsAPlainDayWithNoTimeZoneInIt() {
        let day: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        XCTAssertEqual(day.text, "2026-09-08")
        XCTAssertEqual(day.weekdayName, "Tuesday")
        XCTAssertTrue(CalendarDay(text: "2026-09-08")! < CalendarDay(text: "2026-09-10")!)
        XCTAssertTrue(CalendarDay(text: "2026-12-31")! < CalendarDay(text: "2027-01-05")!)
        XCTAssertEqual(CalendarDay(text: " 2026-09-08 "), day, "Surrounding space is forgiven")
    }
}
