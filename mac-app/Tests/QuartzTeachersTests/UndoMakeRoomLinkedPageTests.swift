import XCTest
@testable import QuartzTeachers

/// Pins the plain Make Room step: Insert Class in a section with no link
/// plans exactly the ops it planned before #1055 (#1055 M7: no link code in
/// Insert Class, so the link tests M1 added are gone).
@MainActor
final class UndoMakeRoomLinkedPageTests: XCTestCase {

    // MARK: - Stored properties

    var folders: [URL] = []

    // MARK: - Setting up

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        UndoKillPoints.hook = nil
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A working folder holding one course with one section, a remembered
    /// timetable of six meeting days, and Unit 1, Day 1 to Day 3 on the
    /// first three. The list of steps is in a folder of the test's own.
    func makeCourse() throws -> (root: URL, course: Course, classes: URL) {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("make-room-linked-\(UUID().uuidString)", isDirectory: true)
        folders.append(root)
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        let classes: URL = courseURL.appendingPathComponent("section1/All Classes", isDirectory: true)
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("elsewhere", isDirectory: true), withIntermediateDirectories: true
        )
        UndoJournalLocation.folderOverride = root.appendingPathComponent("list", isDirectory: true)
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        let dates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-22"]
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        )
        try page(title: "Unit 1, Day 1", date: "2026-09-08", body: "One.").write(
            to: classes.appendingPathComponent("Unit 1, Day 1.md"), atomically: true, encoding: .utf8
        )
        try page(title: "Unit 1, Day 2", date: "2026-09-10", body: "Two.").write(
            to: classes.appendingPathComponent("Unit 1, Day 2.md"), atomically: true, encoding: .utf8
        )
        try page(title: "Unit 1, Day 3", date: "2026-09-14", body: "Three.").write(
            to: classes.appendingPathComponent("Unit 1, Day 3.md"), atomically: true, encoding: .utf8
        )
        return (root: root, course: course, classes: classes)
    }

    func page(title: String, date: String, body: String) -> String {
        return "---\ntitle: \(title)\npublish: true\ncreated: \(date)T07:00:00.000-0400\n---\n\n\(body)\n"
    }

    func stepCount() throws -> Int {
        let fold: UndoFold = try UndoJournalLocation.standardJournal().read()
        return fold.records.count
    }

    /// Plans and applies room for one class at `day`, counting the steps it
    /// makes and every "could not record" trail line.
    func makeRoom(atDay day: Int, in made: (root: URL, course: Course, classes: URL)) throws
        -> (outcome: ClassChangeOutcome, steps: Int, couldNotRecord: [UndoUnrecordedChange]) {
        let stepsBefore: Int = try stepCount()
        var lines: [UndoUnrecordedChange] = []
        let before = UndoTrailHook.couldNotRecordLine
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            lines.append(change)
        }
        defer {
            UndoTrailHook.couldNotRecordLine = before
        }
        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: day, count: 1, forSection: 1, in: made.course
        )
        let outcome: ClassChangeOutcome = try ClassInsertionPlanner.apply(plan, in: made.course)
        return (outcome: outcome, steps: try stepCount() - stepsBefore, couldNotRecord: lines)
    }

    // MARK: - Tests: a section with no link

    /// No link; room at Day 2: the step plans exactly the ops it planned
    /// before #1055 (each op as its JSON, keys sorted).
    func testAPlainSectionStillPlansTheSameStep() throws {
        let made = try makeCourse()

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1, "one step")
        let fold: UndoFold = try UndoJournalLocation.standardJournal().read()
        guard let lastSeq = fold.orderedSeqs.last, let record = fold.records[lastSeq] else {
            return XCTFail("no step")
        }
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var opsPlanned: [String] = []
        for op in record.step.ops {
            opsPlanned.append(String(decoding: try encoder.encode(op), as: UTF8.self))
        }
        // Recorded from a run on the base, 99499d6b7, before #1055 M1.
        let opsOfTheBase: [String] = [
            #"{"afterSha":"66d54ec13166a9502d70887b73974626f348418fad3f189e9d7317b63cc88e48","blobs":["66d54ec13166a9502d70887b73974626f348418fad3f189e9d7317b63cc88e48"],"kind":"writeFile","path":"courses/ICS3U/section1/All Classes/Unit 1, Day 4.md"}"#,
            #"{"afterSha":"3ec46cb7c9c5c6c5fd277ce9500f0ec009c806252a7c885fd517d2620a45d5ed","beforeSha":"974948dd6817bfe1e04a29c938357c14ddb3f9f7b56f9852ceb96af9de8fde33","blobs":["974948dd6817bfe1e04a29c938357c14ddb3f9f7b56f9852ceb96af9de8fde33","3ec46cb7c9c5c6c5fd277ce9500f0ec009c806252a7c885fd517d2620a45d5ed"],"kind":"writeFile","path":"courses/ICS3U/section1/All Classes/Unit 1, Day 3.md"}"#,
            #"{"afterSha":"49b98c16209ffd0ac63cfc14227e8feb6a10d4c9eecf7b2652538f95be462556","beforeSha":"766e3d2b3e7b13e9ba2f1d29df6ef2daf8f352f79a6163aa35bef8e46c23634c","blobs":["766e3d2b3e7b13e9ba2f1d29df6ef2daf8f352f79a6163aa35bef8e46c23634c","49b98c16209ffd0ac63cfc14227e8feb6a10d4c9eecf7b2652538f95be462556"],"kind":"writeFile","path":"courses/ICS3U/section1/All Classes/Unit 1, Day 2.md"}"#,
        ]
        XCTAssertEqual(opsPlanned, opsOfTheBase)
    }
}
