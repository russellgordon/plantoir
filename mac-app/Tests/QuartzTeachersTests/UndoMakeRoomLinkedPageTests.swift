import XCTest
@testable import QuartzTeachers

/// Insert Class (Make Room, and Duplicate Class, which makes room through the
/// same code) renaming a later class page that is a symbolic link to a file
/// (#899 U4b3 part 2, `undo.rule.shadow`): the step MOVES THE LINK ITSELF to
/// the new name, its target as written, never followed; the file it leads to
/// is never moved, renamed or removed, and only the moved date is written
/// into it, never a title; a link leading nowhere is moved the same way with
/// nothing written for it or through it; the place the link leaves is handed
/// over, in the same step, to the class below it or the new class. Before
/// this piece the same Insert Class was refused "cannot tell now" before
/// anything changed.
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

    /// Replaces the class page `title` with a link holding `target`, the
    /// page's own text thrown away (the link leads to a page already there).
    func replaceWithALink(_ title: String, holding target: String, in made: (root: URL, course: Course, classes: URL)) throws {
        let pageURL: URL = made.classes.appendingPathComponent(title + ".md")
        if (try? FileManager.default.attributesOfItem(atPath: pageURL.path)) != nil {
            try FileManager.default.removeItem(at: pageURL)
        }
        try FileManager.default.createSymbolicLink(atPath: pageURL.path, withDestinationPath: target)
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
        XCTAssertTrue(linked.contains("title: Unit 1, Day 3"), "never a title written into the file it leads to (Russell, 2026-11-26)")
        XCTAssertTrue(linked.contains("createdSection1: 2026-09-16T07:00:00.000-0400"), "the moved date written into it")
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
        XCTAssertTrue(linked.contains("title: Unit 1, Day 3"), "its own title kept")
        XCTAssertTrue(linked.contains("createdSection1: 2026-09-16T07:00:00.000-0400"))
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
        XCTAssertTrue(linked.contains("title: Unit 1, Day 2"), "its own title kept")
        XCTAssertTrue(linked.contains("createdSection1: 2026-09-14T07:00:00.000-0400"))
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
        XCTAssertTrue(linked2.contains("Two.") && linked2.contains("title: Unit 1, Day 2"), linked2)
        XCTAssertTrue(linked3.contains("Three.") && linked3.contains("title: Unit 1, Day 3"), linked3)
        XCTAssertTrue(linked2.contains("createdSection1: 2026-09-14T07:00:00.000-0400"))
        XCTAssertTrue(linked3.contains("createdSection1: 2026-09-16T07:00:00.000-0400"))
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
        XCTAssertTrue(linked.contains("Three.") && linked.contains("title: Unit 1, Day 3"), linked)
        XCTAssertTrue(linked.contains("createdSection1: 2026-09-16T07:00:00.000-0400"))
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
        XCTAssertTrue(linked.contains("title: Unit 1, Day 3"), "its own title kept")
    }

    /// Russell, 2026-11-26: "Shared pages never have day “x” titles in
    /// them." A linked later class whose file has a title in its own words
    /// keeps it byte for byte; only the moved date is written into it; Undo
    /// and then Redo return the folder exactly. MUST FAIL with the title
    /// written through the link.
    func testALinkedClassKeepsItsOwnTitleAndTakesTheNewDate() throws {
        try checkTheTitleIsKept("Loops and lists")
    }

    /// The same for a linked file whose title reads like a class's
    /// ("Unit 1, Day 4"): never written through a link either.
    func testALinkedClassWithADayStyleTitleKeepsItToo() throws {
        try checkTheTitleIsKept("Unit 1, Day 4")
    }

    /// An ordinary (plain) class page is still retitled as it is renamed.
    func testAPlainLaterClassIsStillRetitled() throws {
        let made = try makeCourse()

        _ = try makeRoom(atDay: 2, in: made)

        XCTAssertTrue(try text("Unit 1, Day 4", in: made).contains("title: Unit 1, Day 4"))
        XCTAssertTrue(try text("Unit 1, Day 3", in: made).contains("title: Unit 1, Day 3"))
    }

    /// Russell, 2026-11-26: the date goes under the key the linked FILE's
    /// own place calls for. A course-level page shared by two sections:
    /// only `createdSection1:` moves; `createdSection2:` and the title are
    /// left byte for byte. MUST FAIL with a plain `created:` added.
    func testALinkToACourseLevelPageMovesOnlyThisSectionsDate() throws {
        let laid: String = "---\ntitle: Shared lesson\npublish: true\ncreatedSection1: 2026-09-14T07:00:00.000-0400\n"
            + "createdSection2: 2026-10-01T07:00:00.000-0400\n---\n\nShared.\n"
        let expected: String = laid.replacingOccurrences(of: "createdSection1: 2026-09-14", with: "createdSection1: 2026-09-16")
        try checkTheLinkedFile(target: "../../elsewhere/Shared.md", laid: laid, expected: expected)
    }

    /// A link to a page inside the section's own folder (not a class
    /// page): its plain `created:` moves, its title kept.
    func testALinkToAPageInTheSectionsFolderMovesItsCreatedLine() throws {
        let laid: String = page(title: "Section notes", date: "2026-09-14", body: "Notes.")
        let expected: String = laid.replacingOccurrences(of: "created: 2026-09-14", with: "created: 2026-09-16")
        try checkTheLinkedFile(target: "../Section notes.md", laid: laid, expected: expected)
    }

    func checkTheTitleIsKept(_ ownTitle: String) throws {
        // The file is a course-level page (`elsewhere/`): this section's
        // own key is added at the top of its settings, `created:` kept.
        let laid: String = page(title: ownTitle, date: "2026-09-14", body: "Three.")
        let expected: String = "---\ncreatedSection1: 2026-09-16T07:00:00.000-0400\n" + String(laid.dropFirst("---\n".count))
        try checkTheLinkedFile(target: "../../elsewhere/Unit 1, Day 3.md", laid: laid, expected: expected)
    }

    /// Day 3 a link holding `target` (from the class folder) to a file
    /// laid as `laid`; room at Day 2: the file reads `expected`, the link
    /// is at Day 4, and Undo then Redo return the folder exactly.
    func checkTheLinkedFile(target: String, laid: String, expected: String) throws {
        let made = try makeCourse()
        let file: URL = try makeALink("Unit 1, Day 3", holding: target, in: made)
        try laid.write(to: file, atomically: true, encoding: .utf8)
        let before: [String: String] = everything(under: made)

        _ = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expected, "its title byte for byte, the new date")
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target)
        let after: [String: String] = everything(under: made)
        let journal: UndoJournal = try UndoJournalLocation.standardJournal()
        let root: URL = made.root
        let undone: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
        guard case .undone = undone else {
            return XCTFail("Undo came to \(undone)")
        }
        XCTAssertEqual(everything(under: made), before, "Undo puts the link's name and the file's date back")
        let redone: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
        guard case .redone = redone else {
            return XCTFail("Redo came to \(redone)")
        }
        XCTAssertEqual(everything(under: made), after, "Redo makes them again")
    }

    // MARK: - Tests: what stays as it was

    /// A broken later-class link (it leads to nothing, here a place OUTSIDE
    /// the working folder): Insert Class never refuses because of where a
    /// link leads (Russell, 2026-11-26: "Never refuse"). The link is renamed,
    /// its text byte for byte; nothing else is written for it, and above
    /// all nothing THROUGH it, so no file appears where it points; every
    /// other class is handled as usual; Undo and Redo return the folder
    /// exactly. MUST FAIL with the link refused, or skipped in silence and
    /// Day 2's lesson written through it, making the file it names.
    func testABrokenLinkedLaterClassIsRenamedAndNothingIsWrittenThroughIt() throws {
        let made = try makeCourse()
        let outside: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("make-room-broken-\(UUID().uuidString)", isDirectory: true)
        folders.append(outside)
        let target: String = outside.appendingPathComponent("Unit 1, Day 3.md").path
        try replaceWithALink("Unit 1, Day 3", holding: target, in: made)
        let before: [String: String] = everything(under: made)

        let result = try makeRoom(atDay: 2, in: made)

        XCTAssertEqual(result.steps, 1, "one step")
        XCTAssertEqual(result.couldNotRecord, [], "nothing is written outside, so the step is recorded")
        XCTAssertEqual(linkTarget("Unit 1, Day 4", in: made), target, "the broken link renamed, its text byte for byte")
        XCTAssertNil(linkTarget("Unit 1, Day 3", in: made), "the old Day 2 at Day 3 is a plain page")
        let day3: String = try text("Unit 1, Day 3", in: made)
        XCTAssertTrue(day3.contains("Two.") && day3.contains("title: Unit 1, Day 3"), day3)
        XCTAssertTrue(day3.contains("created: 2026-09-14"), day3)
        XCTAssertTrue(try text("Unit 1, Day 2", in: made).contains("publish: false"), "the new blank class")
        XCTAssertTrue(try text("Unit 1, Day 1", in: made).contains("One."), "Day 1 as it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path), "nothing made where the link points, nothing outside changed")
        let after: [String: String] = everything(under: made)
        XCTAssertEqual(after.count, before.count + 1, "one new page, nothing else: \(after)")

        let journal: UndoJournal = try UndoJournalLocation.standardJournal()
        let root: URL = made.root
        let undone: UndoOutcome = journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
        guard case .undone = undone else {
            return XCTFail("Undo came to \(undone)")
        }
        XCTAssertEqual(everything(under: made), before, "Undo puts the broken link's name back")
        let redone: UndoOutcome = journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces())
        guard case .redone = redone else {
            return XCTFail("Redo came to \(redone)")
        }
        XCTAssertEqual(everything(under: made), after, "Redo makes it again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path), "still nothing made where the link points")
    }

    /// Day 4 a link to Day 3's page, in the same run; room at Day 2: refused
    /// before anything changes, naming Day 4 (review B of U4b3, MEDIUM 1).
    /// MUST FAIL with Day 3 given the old Day 2's lesson and Day 5's date.
    func testALaterClassLinkedToAnotherClassOfTheRunIsRefused() throws {
        let made = try makeCourse()
        try replaceWithALink("Unit 1, Day 4", holding: "Unit 1, Day 3.md", in: made)

        try checkRefused(atDay: 2, naming: "Unit 1, Day 4", in: made)
    }

    /// Day 3 a link to Day 1's page, an earlier class the plan leaves; room
    /// at Day 2: refused, naming Day 3. MUST FAIL with Day 1 retitled
    /// "Unit 1, Day 4" and re-dated.
    func testALaterClassLinkedToAnEarlierClassIsRefused() throws {
        let made = try makeCourse()
        try replaceWithALink("Unit 1, Day 3", holding: "Unit 1, Day 1.md", in: made)

        try checkRefused(atDay: 2, naming: "Unit 1, Day 3", in: made)
    }

    /// The same through a link to a link: Day 3 leads to a file elsewhere
    /// that is itself a link to Day 1's page. Judged by the file reached,
    /// never by the name or path written in the link: refused.
    func testALaterClassLinkedToAClassThroughAnotherLinkIsRefused() throws {
        let made = try makeCourse()
        let hop: URL = made.course.directoryURL.appendingPathComponent("elsewhere/hop.md")
        try FileManager.default.createSymbolicLink(atPath: hop.path, withDestinationPath: "../section1/All Classes/Unit 1, Day 1.md")
        try replaceWithALink("Unit 1, Day 3", holding: "../../elsewhere/hop.md", in: made)

        try checkRefused(atDay: 2, naming: "Unit 1, Day 3", in: made)
    }

    /// Review C of U4b3, MEDIUM 1: Day 3 is itself a link to a file
    /// elsewhere, and Day 4 is a link holding `Unit 1, Day 3.md`. Each hop
    /// is judged by its own identity, not only the file at the end: Day 4's
    /// first hop names Day 3's place, a class page of this section, so it is
    /// refused before anything changes, naming Day 4. MUST FAIL with only
    /// the end of the chain compared (Insert Class goes ahead, Day 5 then
    /// leads to the old Day 2's lesson and the file elsewhere is dated
    /// twice).
    func testALaterClassLinkedToAClassPageThatIsItselfALinkIsRefused() throws {
        let made = try makeCourse()
        try makeALink("Unit 1, Day 3", holding: "../../elsewhere/L.md", in: made)
        try replaceWithALink("Unit 1, Day 4", holding: "Unit 1, Day 3.md", in: made)

        try checkRefused(atDay: 2, naming: "Unit 1, Day 4", in: made)
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
        XCTAssertTrue(linked.contains("the linked words") && linked.contains("title: Unit 1, Day 2"), linked)
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
