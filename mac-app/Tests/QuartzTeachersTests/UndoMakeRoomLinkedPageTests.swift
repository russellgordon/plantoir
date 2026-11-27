import XCTest
@testable import QuartzTeachers

/// Insert Class (Make Room, and Duplicate Class, which makes room through the
/// same code) when a later class page it would rename is a symbolic link
/// (#1055: symbolic links in a course's working folder are not supported):
/// the whole action is refused before anything changes, "cannot tell now",
/// said as the file named that could not be saved, as before U4b3. A
/// section with no link plans the same step as before.
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

    /// Replaces the class page `title` with a symbolic link holding
    /// `target`, and writes the page's text at the file it leads to.
    /// Returns the file the link leads to.
    @discardableResult
    func makeALink(_ title: String, holding target: String, in made: (root: URL, course: Course, classes: URL)) throws -> URL {
        let pageURL: URL = made.classes.appendingPathComponent(title + ".md")
        let text: String = try String(contentsOf: pageURL, encoding: .utf8)
        try FileManager.default.removeItem(at: pageURL)
        try FileManager.default.createSymbolicLink(atPath: pageURL.path, withDestinationPath: target)
        let file: URL = URL(fileURLWithPath: target, relativeTo: made.classes).standardizedFileURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
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

    /// Every file and link under the working folder, by path from it, never
    /// followed through a link: a link as "-> target", a file as its text.
    /// (Each name is the walk's own, so a link is recorded as itself and
    /// never filed under the file it leads to: review B of U4b3, LOW 2.)
    func everything(under made: (root: URL, course: Course, classes: URL)) -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(atPath: made.root.path) else {
            return result
        }
        while let relative = walker.nextObject() as? String {
            if relative.hasPrefix("list") || relative.hasPrefix("courses/.internal") || relative.hasSuffix("course_config.json") {
                continue
            }
            let url: URL = made.root.appendingPathComponent(relative)
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                result[relative] = "-> " + target
                continue
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                continue
            }
            result[relative] = (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)"
        }
        return result
    }

    /// Insert Class at `day` must refuse with the refusal it gave before
    /// U4b3 part 2 ("cannot tell now", said as the file named that could
    /// not be saved), naming `named`, and leave the whole working folder,
    /// links included, byte for byte as it was, with no step recorded.
    func checkRefused(atDay day: Int, naming named: String, in made: (root: URL, course: Course, classes: URL)) throws {
        let before: [String: String] = everything(under: made)
        let stepsBefore: Int = try stepCount()
        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: day, count: 1, forSection: 1, in: made.course
        )
        do {
            _ = try ClassInsertionPlanner.apply(plan, in: made.course)
            XCTFail("Insert Class went ahead")
        } catch let error as JournaledStepError {
            guard case .refused(.cannotTellNow, let fileName) = error else {
                return XCTFail("refused as \(error), not cannot tell now")
            }
            XCTAssertEqual(fileName, named + ".md")
            XCTAssertEqual(
                error.localizedDescription,
                CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: named + ".md"]).localizedDescription,
                "the words a teacher read before part 2"
            )
        }
        XCTAssertEqual(everything(under: made), before, "nothing changed")
        XCTAssertEqual(try stepCount(), stepsBefore, "no step recorded")
    }

    // MARK: - Tests: a linked later class is refused (#1055)

    /// Day 3 a link to a file inside the working folder; room at Day 2.
    func testALinkedLaterClassInsideTheWorkingFolderIsRefusedBeforeAnythingChanges() throws {
        let made = try makeCourse()
        try makeALink("Unit 1, Day 3", holding: "../../elsewhere/Unit 1, Day 3.md", in: made)

        try checkRefused(atDay: 2, naming: "Unit 1, Day 3", in: made)
    }

    /// Day 3 a link to a file outside the working folder; room at Day 2. No
    /// "could not record" line either: nothing went ahead.
    func testALinkedLaterClassOutsideTheWorkingFolderIsRefusedBeforeAnythingChanges() throws {
        let made = try makeCourse()
        let outside: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("make-room-outside-\(UUID().uuidString)", isDirectory: true)
        folders.append(outside)
        let target: String = outside.appendingPathComponent("Unit 1, Day 3.md").path
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)
        let fileBefore: String = try String(contentsOf: file, encoding: .utf8)
        var lines: [UndoUnrecordedChange] = []
        let before = UndoTrailHook.couldNotRecordLine
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            lines.append(change)
        }
        defer {
            UndoTrailHook.couldNotRecordLine = before
        }

        try checkRefused(atDay: 2, naming: "Unit 1, Day 3", in: made)

        XCTAssertFalse(lines.contains(.wentAhead), "no line saying it went ahead")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), fileBefore, "the file outside as it was")
    }

    /// Duplicate Class makes room through the same code: duplicating Day 1
    /// with Day 3 a link is refused with the same words, no copy made,
    /// nothing changed, no step.
    func testDuplicateClassWithALinkedLaterClassIsRefusedBeforeAnythingChanges() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16"], in: made.course)
        try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
        try DuplicateAsNextClassTests.writeClass("Unit 1, Day 2", on: "2026-09-10", in: made.course)
        let elsewhere: URL = made.course.directoryURL.appendingPathComponent("Concepts/Unit 1, Day 3.md")
        try "---\ntitle: Unit 1, Day 3\npublish: true\ncreated: 2026-09-14T07:00:00.000-0400\n---\n\nthe linked words\n"
            .write(to: elsewhere, atomically: true, encoding: .utf8)
        let day3: URL = AssistFixture.pageURL(of: "Unit 1, Day 3", in: made.course)
        try FileManager.default.createSymbolicLink(atPath: day3.path, withDestinationPath: "../../Concepts/Unit 1, Day 3.md")
        let classes: URL = ClassPages.folderURL(forSection: 1, in: made.course)
        let before: [String: String] = everything(under: (root: made.root, course: made.course, classes: classes))
        let stepsBefore: Int = try stepCount()

        let outcome: AssistToolOutcome = await AssistFixture.run(
            "add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: made.runner
        )

        let words: String = CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: "Unit 1, Day 3.md"]).localizedDescription
        XCTAssertTrue(outcome.summary.contains(words), outcome.summary)
        XCTAssertFalse(outcome.shouldContinue)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: AssistFixture.pageURL(of: "Unit 1, Day 4", in: made.course).path),
            "no class moved to Day 4"
        )
        XCTAssertEqual(everything(under: (root: made.root, course: made.course, classes: classes)), before, "nothing changed, no copy made")
        XCTAssertEqual(try stepCount(), stepsBefore, "no step recorded")
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
