import XCTest
@testable import QuartzTeachers

/// Insert Class (Make Room, and Duplicate Class, which makes room through the
/// same code) renaming a later class page that is a symbolic link to a file
/// (#899 U4b3 part 2, `undo.rule.shadow`): the step MOVES THE LINK ITSELF to
/// the new name, its target as written, never followed; the file it leads to
/// is never moved, renamed or removed, and the new title and the moved date
/// are written into it; the place the link leaves is handed over, in the same
/// step, to the class below it or the new class. Before this piece the same
/// Insert Class was refused "cannot tell now" before anything changed.
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

    func linkTarget(_ title: String, in made: (root: URL, course: Course, classes: URL)) -> String? {
        let path: String = made.classes.appendingPathComponent(title + ".md").path
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    func text(_ title: String, in made: (root: URL, course: Course, classes: URL)) throws -> String {
        return try String(contentsOf: made.classes.appendingPathComponent(title + ".md"), encoding: .utf8)
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

    /// Every file and link under the course folder and the folder outside
    /// it, by path from the working folder: a link as "-> target", a file
    /// as its text.
    func everything(under made: (root: URL, course: Course, classes: URL)) -> [String: String] {
        var result: [String: String] = [:]
        let prefix: String = UndoFolderPlaces.canonicalPath(of: made.root) + "/"
        guard let walker = FileManager.default.enumerator(at: made.root, includingPropertiesForKeys: nil) else {
            return result
        }
        for case let url as URL in walker {
            let path: String = UndoFolderPlaces.canonicalPath(of: url)
            if !path.hasPrefix(prefix) {
                continue
            }
            let relative: String = String(path.dropFirst(prefix.count))
            if relative.hasPrefix("list") || relative.hasPrefix("courses/.internal") || relative.hasSuffix("course_config.json") {
                continue
            }
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

    // MARK: - Tests: Insert Class moves a linked later class

    /// Day 3 a link; room for one class at Day 2. MUST FAIL with the rename
    /// planned as write and remove (refused "cannot tell now"), with the
    /// target's path moved instead of the link, or with the retitle planned
    /// at the link's old place.
    func testALinkedDay3MovesAsALinkWhenRoomIsMadeAtDay2() throws {
        let made = try makeCourse()
        let target: String = "../../elsewhere/Unit 1, Day 3.md"
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1, "one step")
        XCTAssertEqual(result.couldNotRecord, [], "inside the working folder the step is recorded")
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target, "the link moved as itself, its target as written")
        XCTAssertNil(linkTarget("Unit 1, Day 3", in: made), "the old Day 2 at Day 3 is a plain page")
        let day3: String = try text("Unit 1, Day 3", in: made)
        XCTAssertTrue(day3.contains("Two."), day3)
        XCTAssertFalse(day3.contains("Three."), "never a copy of the linked file")
        XCTAssertTrue(day3.contains("title: Unit 1, Day 3"))
        XCTAssertNil(linkTarget("Unit 1, Day 2", in: made))
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("publish: false"), "the new blank class")
        let linked: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(linked.contains("Three."))
        XCTAssertTrue(linked.contains("title: Unit 1, Day 4"), "the new title written into the file it leads to")
        XCTAssertTrue(linked.contains("created: 2026-09-16T07:00:00.000-0400"), "the moved date written into it")
        var copies: Int = 0
        for (_, content) in everything(under: made) where content.contains("Three.") {
            copies += 1
        }
        XCTAssertEqual(copies, 1, "the file the link leads to is the only copy")
    }

    /// Day 3 a link; room at Day 3: the new class takes the link's old place.
    func testALinkedDay3MovesAsALinkWhenRoomIsMadeAtDay3() throws {
        let made = try makeCourse()
        let target: String = "../../elsewhere/Unit 1, Day 3.md"
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)

        let result = try makeRoom(atDay: 3, in: made)

        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(result.couldNotRecord, [])
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target)
        XCTAssertNil(linkTarget("Unit 1, Day 3", in: made))
        XCTAssertTrue(try text("Unit 1, Day 3", in: made).contains("publish: false"), "the new class at the link's old place")
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("Two."), "Day 2 untouched")
        let linked: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(linked.contains("title: Unit 1, Day 4"))
        XCTAssertTrue(linked.contains("created: 2026-09-16T07:00:00.000-0400"))
    }

    /// Day 2 a link and Day 3 plain; room at Day 2: the link moves into the
    /// place a page's rename leaves.
    func testALinkedDay2MovesIntoThePlaceAPlainDay3Leaves() throws {
        let made = try makeCourse()
        let target: String = "../../elsewhere/Unit 1, Day 2.md"
        let file: URL = try makeALink("Unit 1, Day 2", holding: target, in: made)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(result.couldNotRecord, [])
        XCTAssertNil(linkTarget("Unit 1, Day 4", in: made))
        XCTAssertTrue(try text("Unit 1, Day 4", in: made).contains("Three."))
        XCTAssertTrue(try text("Unit 1, Day 4", in: made).contains("title: Unit 1, Day 4"))
        XCTAssertEqual(linkTarget("Unit 1, Day 3", in: made), target)
        XCTAssertNil(linkTarget("Unit 1, Day 2", in: made))
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("publish: false"))
        let linked: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(linked.contains("Two."))
        XCTAssertTrue(linked.contains("title: Unit 1, Day 3"))
        XCTAssertTrue(linked.contains("created: 2026-09-14T07:00:00.000-0400"))
    }

    /// Day 2 and Day 3 both links, to two files; room at Day 2: two links
    /// in a row, the second moving into the place the first leaves.
    func testTwoLinkedLaterClassesInARowEachMoveAsALink() throws {
        let made = try makeCourse()
        let target2: String = "../../elsewhere/Unit 1, Day 2.md"
        let target3: String = "../../elsewhere/Unit 1, Day 3.md"
        let file2: URL = try makeALink("Unit 1, Day 2", holding: target2, in: made)
        let file3: URL = try makeALink("Unit 1, Day 3", holding: target3, in: made)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(result.couldNotRecord, [])
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target3)
        XCTAssertEqual(linkTarget("Unit 1, Day 3", in: made), target2)
        XCTAssertNil(linkTarget("Unit 1, Day 2", in: made))
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("publish: false"))
        let linked2: String = try String(contentsOf: file2, encoding: .utf8)
        let linked3: String = try String(contentsOf: file3, encoding: .utf8)
        XCTAssertTrue(linked2.contains("Two.") && linked2.contains("title: Unit 1, Day 3"), linked2)
        XCTAssertTrue(linked3.contains("Three.") && linked3.contains("title: Unit 1, Day 4"), linked3)
        XCTAssertTrue(linked2.contains("created: 2026-09-14T07:00:00.000-0400"))
        XCTAssertTrue(linked3.contains("created: 2026-09-16T07:00:00.000-0400"))
    }

    /// The first arrangement with the link leading OUTSIDE the working
    /// folder: one "could not record" line saying the step went ahead, as
    /// `undo.rule.shadow` says for every write outside; the disk as above.
    func testALinkedDay3LeadingOutsideTheWorkingFolderGoesAheadWithOneLine() throws {
        let made = try makeCourse()
        let outside: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("make-room-outside-\(UUID().uuidString)", isDirectory: true)
        folders.append(outside)
        let target: String = outside.appendingPathComponent("Unit 1, Day 3.md").path
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.couldNotRecord, [.wentAhead], "one line, saying it went ahead")
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target)
        XCTAssertNil(linkTarget("Unit 1, Day 3", in: made))
        XCTAssertTrue(try text("Unit 1, Day 3", in: made).contains("Two."))
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("publish: false"))
        let linked: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(linked.contains("Three.") && linked.contains("title: Unit 1, Day 4"), linked)
        XCTAssertTrue(linked.contains("created: 2026-09-16T07:00:00.000-0400"))
    }

    /// A linked file that names itself (`[[Unit 1, Day 3]]`) is rewritten
    /// once, through the link: the file holds the new name once, no plain
    /// copy is written beside it.
    func testALinkedPageThatNamesItselfIsRewrittenOnceThroughTheLink() throws {
        let made = try makeCourse()
        let target: String = "../../elsewhere/Unit 1, Day 3.md"
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)
        let named: String = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "Three.", with: "Three. See [[Unit 1, Day 3]].")
        try named.write(to: file, atomically: true, encoding: .utf8)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target)
        let linked: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(linked.components(separatedBy: "[[Unit 1, Day 4]]").count, 2, linked)
        XCTAssertFalse(linked.contains("[[Unit 1, Day 3]]"), linked)
        XCTAssertTrue(linked.contains("title: Unit 1, Day 4"))
    }

    // MARK: - Tests: what stays as it was

    /// A dangling later-class link (its target is gone): `fileExists`
    /// follows it and answers false, so its rename is skipped, as before
    /// this piece; the link is left where it was, holding its target, and
    /// (also as before) Day 2's rename then finds Day 3 free and writes its
    /// lesson through the dangling link, which makes the file it names.
    /// Pinned here; changing it is the next piece's.
    func testADanglingLinkedLaterClassIsSkippedAsBefore() throws {
        let made = try makeCourse()
        let target: String = "../../elsewhere/Unit 1, Day 3.md"
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)
        try FileManager.default.removeItem(at: file)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: made.course
        )
        _ = try? ClassInsertionPlanner.apply(plan, in: made.course)

        XCTAssertFalse(FileManager.default.fileExists(atPath: made.classes.appendingPathComponent("Unit 1, Day 4.md").path),
                       "the dangling link is not moved")
        XCTAssertEqual(linkTarget("Unit 1, Day 3", in: made), target, "the link is left where it was")
        let written: String = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.contains("Two.") && written.contains("title: Unit 1, Day 3"), written)
    }

    /// A later class that is a link to a FOLDER: not a link to a file, so
    /// it is read as before, through `readText`, which cannot read it: its
    /// rename is not done and the link is left as it was.
    func testALaterClassThatIsALinkToAFolderIsNotRenamed() throws {
        let made = try makeCourse()
        let pageURL: URL = made.classes.appendingPathComponent("Unit 1, Day 3.md")
        try FileManager.default.removeItem(at: pageURL)
        let folder: URL = made.course.directoryURL.appendingPathComponent("elsewhere/a folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: pageURL.path, withDestinationPath: "../../elsewhere/a folder")

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: made.course
        )
        _ = try? ClassInsertionPlanner.apply(plan, in: made.course)

        XCTAssertEqual(linkTarget("Unit 1, Day 3", in: made), "../../elsewhere/a folder", "the link is left as it was")
        XCTAssertNil(linkTarget("Unit 1, Day 4", in: made))
        XCTAssertFalse(ClassInsertionPlanner.isALinkToAFile(pageURL))
    }

    // MARK: - Tests: Duplicate Class

    /// Duplicate Class makes room through the same code: duplicating Day 1
    /// by its title puts the copy at Day 2 and moves the linked Day 2 to
    /// Day 3 as a link, one step.
    func testDuplicateClassMovesALinkedLaterClassAsALink() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-14"], in: made.course)
        try DuplicateAsNextClassTests.writeClass("Unit 1, Day 1", on: "2026-09-08", in: made.course)
        let elsewhere: URL = made.course.directoryURL.appendingPathComponent("Concepts/Unit 1, Day 2.md")
        try "---\ntitle: Unit 1, Day 2\npublish: true\ncreated: 2026-09-10T07:00:00.000-0400\n---\n\nthe linked words\n"
            .write(to: elsewhere, atomically: true, encoding: .utf8)
        let day2: URL = AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course)
        try FileManager.default.createSymbolicLink(atPath: day2.path, withDestinationPath: "../../Concepts/Unit 1, Day 2.md")
        let day3: URL = AssistFixture.pageURL(of: "Unit 1, Day 3", in: made.course)

        let stepsBefore: Int = try stepCount()
        _ = await AssistFixture.run("add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: made.runner)
        XCTAssertEqual(try stepCount() - stepsBefore, 1, "one step")

        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: day3.path), "../../Concepts/Unit 1, Day 2.md",
                       "the linked class moved to Day 3 as a link")
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: day2.path), "the copy is a plain page")
        let copy: String = try String(contentsOf: day2, encoding: .utf8)
        XCTAssertTrue(copy.contains("the words of Unit 1, Day 1"), copy)
        let linked: String = try String(contentsOf: elsewhere, encoding: .utf8)
        XCTAssertTrue(linked.contains("the linked words") && linked.contains("title: Unit 1, Day 3"), linked)
    }

    // MARK: - Tests: recovery

    /// The first arrangement killed before each swap in turn, until a kill
    /// point is no longer reached: once recovery has run, every place is
    /// whole before or whole after: the link at exactly one of its two
    /// names with its target as written, the file it leads to holding
    /// either all of the step's changes or none.
    func testAMakeRoomWithALinkedLaterClassKilledBeforeAnySwapIsWholeAfterRecovery() async throws {
        let target: String = "../../elsewhere/Unit 1, Day 3.md"
        let finished = try makeCourse()
        try makeALink("Unit 1, Day 3", holding: target, in: finished)
        let untouched: [String: String] = everything(under: finished)
        _ = try makeRoom(atDay: 2, in: finished)
        let whole: [String: String] = everything(under: finished)
        XCTAssertNotEqual(untouched, whole)

        var index: Int = 0
        while true {
            let made = try makeCourse()
            try makeALink("Unit 1, Day 3", holding: target, in: made)
            let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
                unit: 1, atDay: 2, count: 1, forSection: 1, in: made.course
            )
            var reachedIt: Bool = false
            let point: UndoKillPoint = .beforeSwap(index)
            UndoKillPoints.hook = { reached in
                if reached == point {
                    reachedIt = true
                    return true
                }
                return false
            }
            _ = try? ClassInsertionPlanner.apply(plan, in: made.course)
            UndoKillPoints.hook = nil
            if !reachedIt {
                break
            }
            let list: URL = made.root.appendingPathComponent("list", isDirectory: true)
            let workingRoot: URL = made.root
            await UndoRecovery.recoverAndRederive(
                UndoJournal(folderURL: list, processIsAlive: { _ in false }), resolveRoot: { _ in workingRoot }
            )
            let now: [String: String] = everything(under: made)
            XCTAssertTrue(now == untouched || now == whole, "not whole before or whole after at \(point): \(now)")
            index += 1
        }
        XCTAssertGreaterThanOrEqual(index, 3, "the link's move, the page renamed and the new class: at least three swaps")
    }
}
