import XCTest
@testable import QuartzTeachers

/// U4a of #899: Course Settings' Save, Add folder and Set School Year, each
/// ONE step through the door.
///
/// - A Save is one step whatever it changes, one `editJSON` per top-level
///   setting it changes, each `before` read when the step is planned; a
///   setting that was absent has no `before`, so Undo makes it absent again
///   (#986 section 4.5, the Marks case). Undo takes back only what the step
///   changed (ruling 4): a setting a build or another copy changed since is
///   left as it is.
/// - Add folder is one `createTree` per folder made, the folder and
///   Plantoir's two pages; Undo takes a folder out only while it still holds
///   just those, and otherwise refuses and names it (#986 ruling 7).
/// - Set School Year is one step with one `editJSON`.
/// - A step killed part way is whole before or whole after once recovery
///   has run.
///
/// Every test runs the door LIVE (`JournaledStep.modeOverride`), as U7 will.
@MainActor
final class UndoCourseSettingsStepTests: XCTestCase {

    // MARK: - Stored properties

    var listFolder: URL = FileManager.default.temporaryDirectory

    var root: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    static let configPath: String = "courses/ICS3U/course_config.json"

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        let unique: String = UUID().uuidString
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-settings-list-\(unique)", isDirectory: true)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-settings-\(unique)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
        JournaledStep.modeOverride = .live
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent(".trail"))
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: listFolder)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    func journal(processIsAlive: Bool = true) -> UndoJournal {
        if processIsAlive {
            return UndoJournal(folderURL: listFolder)
        }
        return UndoJournal(folderURL: listFolder, processIsAlive: { _ in false })
    }

    /// The gesture script's course: `graded_folders` absent, so the first
    /// Marks tick makes the key (#986 section 4.5).
    func course() throws -> Course {
        return try CourseSettingsGestureScript.makeCourse(in: root)
    }

    /// A two-section course, for a per-section folder made in each section.
    func twoSectionCourse() throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        for folder in ["section1", "section2", "Concepts"] {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "shared_folders": ["Concepts"],
            "per_section_folders": ["All Classes"],
            "per_section_files": ["index.md"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    /// The settings file as JSON now.
    func settings(of course: Course) throws -> [String: Any] {
        let data: Data = try Data(contentsOf: course.configFileURL)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The newest step's ops.
    func newestOps() throws -> [UndoOp] {
        let fold: UndoFold = try journal().read()
        var newest: UndoStepRecord? = nil
        for (_, record) in fold.records {
            if newest == nil || record.step.seq > (newest?.step.seq ?? 0) {
                newest = record
            }
        }
        return try XCTUnwrap(newest).step.ops
    }

    func stepCount() throws -> Int {
        return try journal().read().records.count
    }

    /// Writes the settings file with one top-level key changed, the way a
    /// build's preflight does: read, change, pretty JSON.
    nonisolated static func changeOnDisk(_ key: String, to value: Any, at url: URL) throws {
        let read: Data = try Data(contentsOf: url)
        guard var onDisk = try JSONSerialization.jsonObject(with: read) as? [String: Any] else {
            return
        }
        onDisk[key] = value
        var data: Data = try JSONSerialization.data(withJSONObject: onDisk, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: url)
    }

    // MARK: - Save

    /// One Save is ONE step of one `editJSON` per changed setting, keyed by
    /// the setting, named `saveCourseSettings`; the first Marks tick makes
    /// `graded_folders`, which was absent, so its op has no `before`. Undo
    /// puts every setting back and takes `graded_folders` back to ABSENT,
    /// never an empty list; Redo makes it again. MUST FAIL before U4a, when
    /// Save wrote the file outside the door (no step on the list).
    func testASaveIsOneStepAndUndoTakesTheMarksKeyBackToAbsent() async throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: Data = try Data(contentsOf: course.configFileURL)
        course.configuration.gradedFolders = ["Tests"]
        course.configuration.hiddenItems = ["Media"]

        view.save()

        XCTAssertEqual(try stepCount(), 1)
        let ops: [UndoOp] = try newestOps()
        var keyPaths: [[String]] = []
        for op in ops {
            XCTAssertEqual(op.knownKind, .editJSON)
            XCTAssertEqual(op.path, UndoCourseSettingsStepTests.configPath)
            keyPaths.append(op.keyPath ?? [])
        }
        XCTAssertEqual(keyPaths, [["graded_folders"], ["hidden"]])
        XCTAssertNil(ops[0].valueBefore, "graded_folders was absent before the Save")
        XCTAssertEqual(try journal().read().records[1]?.step.action?.key, "saveCourseSettings")
        XCTAssertEqual(try settings(of: course)["graded_folders"] as? [String], ["Tests"])
        XCTAssertFalse(course.configuration.hasUnsavedChanges)

        let undone: UndoOutcome = journal().undoNewest(resolveRoot: { _ in self.root })
        XCTAssertEqual(undone, .undone(seq: 1))
        let afterUndo: [String: Any] = try settings(of: course)
        XCTAssertNil(afterUndo["graded_folders"], "the Marks key must be absent again, not an empty list")
        XCTAssertEqual(afterUndo["hidden"] as? [String], ["Media", "Tasks"])
        // Undo spells the members it puts back compactly (the member rule,
        // `undo.editJSONCases`), so the values are back, not the spacing.
        XCTAssertEqual(try CourseConfiguration(contentsOf: course.configFileURL).hiddenItems, ["Media", "Tasks"])
        _ = before

        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(try settings(of: course)["graded_folders"] as? [String], ["Tests"])
    }

    /// Only the members a Save changes change: every other byte of the file
    /// stays as it was. MUST FAIL with the Save written whole (the
    /// pretty-printed rewrite re-spells every member).
    func testASaveChangesOnlyTheBytesOfWhatItChanges() throws {
        let course: Course = try course()
        let text: String = try String(contentsOf: course.configFileURL, encoding: .utf8)
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.hiddenItems = ["Media"]

        view.save()

        let after: String = try String(contentsOf: course.configFileURL, encoding: .utf8)
        let hiddenBefore: String = "\"hidden\" : [\n    \"Media\",\n    \"Tasks\"\n  ]"
        XCTAssertTrue(text.contains(hiddenBefore), text)
        XCTAssertEqual(after, text.replacingOccurrences(of: hiddenBefore, with: "\"hidden\" : [\"Media\"]"))
    }

    /// Another copy of the course (a window, or Add Section's write, which
    /// is not on the list until U4c) saves a setting between this Save and
    /// its Undo: the Undo takes back this Save's setting and leaves the
    /// other one. MUST FAIL with Save as one `writeFile`: the whole file is
    /// then changed since, and the Undo is refused.
    func testAnotherCopysSaveBetweenASaveAndItsUndoIsLeft() throws {
        let course: Course = try course()
        let other: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.hiddenItems = ["Media"]
        view.save()

        other.expandableItems = ["Concepts", "Tests"]
        try other.write(to: course.configFileURL)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        let afterUndo: [String: Any] = try settings(of: course)
        XCTAssertEqual(afterUndo["hidden"] as? [String], ["Media", "Tasks"], "this Save's setting is taken back")
        XCTAssertEqual(afterUndo["expandable"] as? [String], ["Concepts", "Tests"], "the other copy's is left")
    }

    /// A build adds a folder it found to a list this Save did not change:
    /// the Undo takes back the Save and leaves the build's folder. MUST
    /// FAIL with Save as one `writeFile`.
    func testABuildAddingAFolderToAListTheSaveDidNotChangeIsLeft() throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.showReadingTime = true
        view.save()

        try UndoCourseSettingsStepTests.changeOnDisk("shared_folders", to: ["Concepts", "Curriculum", "Tasks", "Tests", "Portfolios"], at: course.configFileURL)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        let afterUndo: [String: Any] = try settings(of: course)
        XCTAssertEqual(afterUndo["shared_folders"] as? [String], ["Concepts", "Curriculum", "Tasks", "Tests", "Portfolios"])
        XCTAssertNil(afterUndo["show_reading_time"], "the Save's setting was absent before it")
    }

    /// A setting this Save changed, changed again by something else: the
    /// Undo is refused, names the settings file, and writes nothing (ruling
    /// 4; a refused Undo clears the list, ruling 13).
    func testASettingTheSaveChangedThatWasChangedAgainRefusesTheUndo() throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.hiddenItems = ["Media"]
        view.save()
        try UndoCourseSettingsStepTests.changeOnDisk("hidden", to: ["Concepts"], at: course.configFileURL)
        let changed: Data = try Data(contentsOf: course.configFileURL)

        let undone: UndoOutcome = journal().undoNewest(resolveRoot: { _ in self.root })

        XCTAssertEqual(
            undone, .refused(.changedSince(firstPath: UndoCourseSettingsStepTests.configPath, others: 0), clearedTheList: true)
        )
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), changed)
    }

    /// A setting another program changes between the plan and the make is
    /// planned again from the file, as the read-again loop always did: the
    /// Save goes ahead, keeps the other program's value of a setting it did
    /// not change, and is one step.
    func testASaveWhoseFileChangedBetweenThePlanAndTheMakeIsPlannedAgain() throws {
        let course: Course = try course()
        course.configuration.hiddenItems = ["Media"]
        let configURL: URL = course.configFileURL
        nonisolated(unsafe) var raced: Bool = false
        UndoKillPoints.hook = { point in
            if point == .afterBegin && !raced {
                raced = true
                try? UndoCourseSettingsStepTests.changeOnDisk("hidden", to: ["Concepts"], at: configURL)
            }
            return false
        }

        let result: CourseConfiguration.WriteResult = try course.configuration.writeAsOneStep(
            to: course.configFileURL, madeBy: UndoStepMaker.sheet("saveCourseSettings")
        )

        UndoKillPoints.hook = nil
        XCTAssertTrue(raced)
        XCTAssertEqual(try settings(of: course)["hidden"] as? [String], ["Media"])
        XCTAssertEqual(result.replacedChangesFromElsewhere, ["hidden"])
        var applied: Int = 0
        for (_, record) in try journal().read().records where record.phase == .done {
            applied += 1
        }
        XCTAssertEqual(applied, 1)
    }

    /// Revert writes nothing and makes no step.
    func testRevertWritesNothingAndMakesNoStep() throws {
        let course: Course = try course()
        let before: Data = try Data(contentsOf: course.configFileURL)
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.hiddenItems = ["Media"]

        view.revertToFile()

        XCTAssertEqual(try Data(contentsOf: course.configFileURL), before)
        XCTAssertEqual(try stepCount(), 0)
        XCTAssertEqual(course.configuration.hiddenItems, ["Media", "Tasks"])
    }

    /// A Save that changes nothing on disk writes nothing and makes no step.
    func testASaveThatChangesNothingMakesNoStep() throws {
        let course: Course = try course()
        let before: Data = try Data(contentsOf: course.configFileURL)
        CourseSettingsView(course: course).save()
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), before)
        XCTAssertEqual(try stepCount(), 0)
    }

    /// Killed after its begin and before its swap: recovery finds nothing
    /// took effect, and the file is whole as it was before.
    func testASaveKilledBeforeItsSwapIsWholeBeforeAfterRecovery() async throws {
        try await killASave(at: .beforeSwap(0))
    }

    /// Killed after its swap and before `applied`: recovery completes it,
    /// whole as the Save left it.
    func testASaveKilledAfterItsSwapIsWholeAfterAfterRecovery() async throws {
        try await killASave(at: .beforeApplied)
    }

    func killASave(at point: UndoKillPoint) async throws {
        let course: Course = try course()
        let before: Data = try Data(contentsOf: course.configFileURL)
        course.configuration.gradedFolders = ["Tests"]
        course.configuration.hiddenItems = ["Media"]
        UndoKillPoints.hook = { reached in reached == point }
        XCTAssertThrowsError(try course.configuration.writeAsOneStep(
            to: course.configFileURL, madeBy: UndoStepMaker.sheet("saveCourseSettings")
        ))
        UndoKillPoints.hook = nil

        let workingRoot: URL = root
        await UndoRecovery.recoverAndRederive(journal(processIsAlive: false), resolveRoot: { _ in workingRoot })

        let now: [String: Any] = try settings(of: course)
        if point == .beforeApplied {
            XCTAssertEqual(now["graded_folders"] as? [String], ["Tests"], "not whole after")
            XCTAssertEqual(now["hidden"] as? [String], ["Media"], "not whole after")
            XCTAssertEqual(try journal().read().records[1]?.phase, .done)
        } else {
            XCTAssertEqual(try Data(contentsOf: course.configFileURL), before, "not whole before")
            XCTAssertEqual(try journal().read().records[1]?.phase, .failed)
        }
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged file was left")
    }

    // MARK: - Add folder

    /// Add folder is ONE step of one `createTree` per folder made, holding
    /// exactly the folder and Plantoir's two pages; Undo takes both folders
    /// out and Redo makes them again. MUST FAIL before U4a (no step).
    func testAddFolderIsOneStepOfOneTreePerFolder() throws {
        let course: Course = try twoSectionCourse()
        let view: CourseSettingsView = CourseSettingsView(course: course)

        let notice: String? = view.noticeAfterFolderChange("Labs", change: .added, scope: .perSection)

        XCTAssertEqual(notice, SpecialNames.addCreatesTheFolderMessage(name: "Labs"))
        XCTAssertEqual(try stepCount(), 1)
        let ops: [UndoOp] = try newestOps()
        var paths: [String] = []
        for op in ops {
            XCTAssertEqual(op.knownKind, .createTree)
            paths.append(op.path ?? "")
        }
        XCTAssertEqual(paths, ["courses/ICS3U/section1/Labs", "courses/ICS3U/section2/Labs"])
        let made: URL = course.directoryURL.appendingPathComponent("section2/Labs")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: made.path).sorted()
        XCTAssertEqual(names, ["_DUPLICATE ME.md", "index.md"])
        XCTAssertEqual(try journal().read().records[1]?.step.action?.key, "addFolder")

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: made.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("section1/Labs").path))
        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: made.path).sorted(), names)
    }

    /// The teacher put a page of their own in the folder Add folder made:
    /// Undo is refused, names the folder, and leaves the folder and the page
    /// (#986 ruling 7). MUST FAIL if a folder is taken out whatever it holds.
    func testAddFolderUndoneWithATeachersFileInsideIsRefusedAndNamesTheFolder() throws {
        let course: Course = try twoSectionCourse()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        _ = view.noticeAfterFolderChange("Labs", change: .added, scope: .shared)
        let page: URL = course.directoryURL.appendingPathComponent("Labs/Lab 1.md")
        try Data("mine\n".utf8).write(to: page)

        let undone: UndoOutcome = journal().undoNewest(resolveRoot: { _ in self.root })

        XCTAssertEqual(undone, .refused(.changedSince(firstPath: "courses/ICS3U/Labs", others: 0), clearedTheList: true))
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "mine\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("Labs/index.md").path))
    }

    /// A folder whose place is taken by the time the step is made (a
    /// folder of the teacher's that appeared after the plan) is never
    /// written over: the step is refused, nothing is made, and nothing is
    /// said, as a folder that could not be made said nothing before U4a.
    func testAddFolderWhosePlaceIsTakenMakesNothingAndSaysNothing() throws {
        let course: Course = try twoSectionCourse()
        let step: JournaledStep = JournaledStep(
            course: course, section: nil, maker: UndoStepMaker.sheet("addFolder"), holds: "course"
        )
        let place: URL = course.directoryURL.appendingPathComponent("Labs")
        _ = FolderScaffold.planPages(
            [FolderScaffold.Page(relativePath: "Labs/index.md", text: "Plantoir's\n")],
            intoNewFolders: [place], courseDirectory: course.directoryURL, into: step
        )
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: false)
        try Data("mine\n".utf8).write(to: place.appendingPathComponent("index.md"))

        XCTAssertThrowsError(try step.make())

        XCTAssertEqual(try String(contentsOf: place.appendingPathComponent("index.md"), encoding: .utf8), "mine\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: place.path), ["index.md"])
    }

    /// Killed after the first folder went in and before the second:
    /// recovery takes the first out again (whole before).
    func testAddFolderKilledBetweenItsFoldersIsWholeBeforeAfterRecovery() async throws {
        try await killAddFolder(at: .beforeSwap(1))
    }

    /// Killed before `applied`: recovery completes the step (whole after).
    func testAddFolderKilledAfterItsFoldersIsWholeAfterAfterRecovery() async throws {
        try await killAddFolder(at: .beforeApplied)
    }

    func killAddFolder(at point: UndoKillPoint) async throws {
        let course: Course = try twoSectionCourse()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        UndoKillPoints.hook = { reached in reached == point }
        let notice: String? = view.noticeAfterFolderChange("Labs", change: .added, scope: .perSection)
        UndoKillPoints.hook = nil
        XCTAssertNil(notice, "a step that did not finish says nothing")

        let workingRoot: URL = root
        await UndoRecovery.recoverAndRederive(journal(processIsAlive: false), resolveRoot: { _ in workingRoot })

        let first: String = course.directoryURL.appendingPathComponent("section1/Labs/index.md").path
        let second: String = course.directoryURL.appendingPathComponent("section2/Labs/_DUPLICATE ME.md").path
        if point == .beforeApplied {
            XCTAssertTrue(FileManager.default.fileExists(atPath: first), "not whole after")
            XCTAssertTrue(FileManager.default.fileExists(atPath: second), "not whole after")
            XCTAssertEqual(try journal().read().records[1]?.phase, .done)
        } else {
            XCTAssertFalse(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("section1/Labs").path), "not whole before")
            XCTAssertFalse(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("section2/Labs").path), "not whole before")
            XCTAssertEqual(try journal().read().records[1]?.phase, .rolledBack)
        }
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged folder was left")
    }

    // MARK: - Set School Year

    /// Set School Year is ONE step with ONE `editJSON`, the year; Undo puts
    /// the year back. MUST FAIL before U4a (no step).
    func testSetSchoolYearIsOneStepWithOneEditJSON() throws {
        let course: Course = try course()
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-11-20"))

        XCTAssertNil(SetSchoolYearSheet.write(2025, to: course, on: day))

        XCTAssertEqual(try stepCount(), 1)
        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.knownKind, .editJSON)
        XCTAssertEqual(ops.first?.keyPath, ["reference_school_year"])
        XCTAssertNil(ops.first?.valueBefore)
        XCTAssertEqual(ops.first?.valueAfter, .number(2025))
        XCTAssertEqual(try journal().read().records[1]?.step.action?.key, "setSchoolYear")
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertNil(try settings(of: course)["reference_school_year"])
    }

    /// With the switch off, a list that cannot take the step changes
    /// nothing about a Save: the same file and the same answer as with one
    /// that can (`rule.shadow`).
    func testInShadowAListThatCannotBeWrittenChangesNothingAboutASave() throws {
        JournaledStep.modeOverride = .shadow
        let working: Course = try course()
        working.configuration.hiddenItems = ["Media"]
        CourseSettingsView(course: working).save()
        let expected: Data = try Data(contentsOf: working.configFileURL)
        try FileManager.default.removeItem(at: root)

        let broken: URL = listFolder.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: broken.appendingPathComponent("undo"))
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.hiddenItems = ["Media"]

        view.save()

        XCTAssertEqual(try Data(contentsOf: course.configFileURL), expected)
    }
}
