import XCTest
@testable import QuartzTeachers

/// U4b of #899: Rename folder (Course Settings) is ONE step through the
/// door, key `renameFolder`: every folder's move (one per section for a
/// per-section folder), every page relinked, inside the moved folder and
/// outside it, and one `editJSON` per settings member the rename changes,
/// all of them or none.
///
/// - Undo takes back only what the step changed (ruling 4): another
///   window's Save of another member is left; a teacher's file put inside the
///   renamed folder refuses the Undo and names the folder.
/// - Save, then rename, then Undo and Undo: both go back (U4a review 1, L1).
/// - A refused rename writes nothing and says so; a step killed part way is
///   whole before or whole after once recovery has run.
/// - The rename record (`courses/.internal/renames/`) is still written
///   before the step and cleared after it: with the switch off recovery
///   repairs nothing, so a rename killed part way is finished from it.
///
/// Every test runs the door LIVE (`JournaledStep.modeOverride`), as U7 will,
/// except the one that proves the switch-off rule.
@MainActor
final class UndoRenameFolderStepTests: XCTestCase {

    // MARK: - Stored properties

    var listFolder: URL = FileManager.default.temporaryDirectory

    var root: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        let unique: String = UUID().uuidString
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-rename-list-\(unique)", isDirectory: true)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-rename-\(unique)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
        JournaledStep.modeOverride = .live
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent(".trail"))
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
        UndoKillPoints.beforeTheRename = nil
        SpecialFolderRenamer.planReadsAPage = nil
        SpecialFolderRenamer.planHasEnded = nil
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

    /// Two sections, each with a per-section `Tasks`; a page inside section
    /// 1's `Tasks` that links into it, a page outside it that links into it,
    /// a page in section 2's `Tasks` that names nothing, and `Tasks` hidden.
    func course() throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        for folder in ["section1/Tasks", "section2/Tasks", "Concepts"] {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        try "See [[Tasks/Quiz 2]].\n".write(
            to: courseURL.appendingPathComponent("section1/Tasks/Quiz 1.md"), atomically: true, encoding: .utf8
        )
        try "Start with [[Tasks/Quiz 1]].\n".write(
            to: courseURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8
        )
        try "Quiz two.\n".write(
            to: courseURL.appendingPathComponent("section2/Tasks/Quiz 2.md"), atomically: true, encoding: .utf8
        )
        try "See [[Concepts/Loops]].\n".write(
            to: courseURL.appendingPathComponent("Concepts/Arrays.md"), atomically: true, encoding: .utf8
        )
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "shared_folders": ["Concepts"],
            "per_section_folders": ["All Classes", "Tasks"],
            "per_section_files": ["index.md"],
            "hidden": ["Tasks"],
            "expandable": ["Concepts", "Tasks"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try data.write(to: configURL)
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    /// Every file under the course but its settings, by path inside it.
    func pages(of course: Course) -> [String: Data] {
        var result: [String: Data] = [:]
        let prefix: String = UndoFolderPlaces.canonicalPath(of: course.directoryURL) + "/"
        guard let walker = FileManager.default.enumerator(at: course.directoryURL, includingPropertiesForKeys: nil) else {
            return result
        }
        for case let url as URL in walker {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) || isDirectory.boolValue {
                continue
            }
            if url.lastPathComponent == "course_config.json" {
                continue
            }
            let path: String = UndoFolderPlaces.canonicalPath(of: url)
            if let data = try? Data(contentsOf: url), path.hasPrefix(prefix) {
                result[String(path.dropFirst(prefix.count))] = data
            }
        }
        return result
    }

    /// The settings file as JSON now.
    func settings(of course: Course) throws -> NSDictionary {
        let data: Data = try Data(contentsOf: course.configFileURL)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// The names a folder lists, as the disk spells them.
    func listed(_ url: URL) -> [String] {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.sorted()
    }

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

    func renamed(_ result: RenameResult) -> String? {
        if case .renamed(let said) = result {
            return said
        }
        return nil
    }

    func failed(_ result: RenameResult) -> String? {
        if case .failed(let said) = result {
            return said
        }
        return nil
    }

    // MARK: - One step

    /// A per-section rename in two sections is ONE step, `renameFolder`:
    /// both folders' moves first, then the page relinked inside the moved
    /// folder (named at its new place) and the page outside it, then one
    /// `editJSON` per settings member it changes; `hidden` is carried
    /// across. Undo puts every folder, page and setting back; Redo makes it
    /// again. The rename record is cleared once the step is made. MUST FAIL before U4b, when the
    /// folders moved and the pages were written outside the door (no step).
    func testARenameIsOneStepAndUndoAndRedoTakeAllOfItBackAndForth() async throws {
        let course: Course = try course()
        let pagesBefore: [String: Data] = pages(of: course)
        let settingsBefore: NSDictionary = try settings(of: course)

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(try journal().read().records.count, 1)
        XCTAssertEqual(try journal().read().records[1]?.step.action?.key, "renameFolder")
        let ops: [UndoOp] = try newestOps()
        var kinds: [String] = []
        var editedPaths: [String] = []
        var members: [String] = []
        for op in ops {
            kinds.append(op.kind)
            if op.knownKind == .editJSON {
                members.append(op.keyPath?.first ?? "")
            } else if let path = op.path {
                editedPaths.append(path)
            }
        }
        XCTAssertEqual(Array(kinds.prefix(2)), ["move", "move"])
        XCTAssertEqual(ops[0].from, "courses/ICS3U/section1/Tasks")
        XCTAssertEqual(ops[0].to, "courses/ICS3U/section1/Assessments")
        XCTAssertNotNil(ops[0].listingSha)
        XCTAssertEqual(editedPaths.sorted(), [
            "courses/ICS3U/section1/Assessments/Quiz 1.md", "courses/ICS3U/section1/index.md",
        ])
        XCTAssertEqual(members, ["expandable", "hidden", "per_section_folders"])
        XCTAssertEqual(try settings(of: course)["hidden"] as? [String], ["Assessments"])
        XCTAssertEqual(course.configuration.perSectionFolders, ["All Classes", "Assessments"])
        XCTAssertEqual(
            pages(of: course)["section1/Assessments/Quiz 1.md"], Data("See [[Assessments/Quiz 2]].\n".utf8)
        )
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "the record is cleared once the step is made")
        let pagesAfter: [String: Data] = pages(of: course)
        let settingsAfter: NSDictionary = try settings(of: course)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertEqual(pages(of: course), pagesBefore)
        XCTAssertEqual(try settings(of: course), settingsBefore)

        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(pages(of: course), pagesAfter)
        XCTAssertEqual(try settings(of: course), settingsAfter)
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged file was left")
    }

    /// A teacher's file put inside the renamed folder after the rename: the
    /// Undo is refused, names that folder, and moves nothing (ruling 4).
    func testUndoWithATeachersFileInsideTheRenamedFolderIsRefusedAndNamesIt() async throws {
        let course: Course = try course()
        _ = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        let mine: URL = course.directoryURL.appendingPathComponent("section1/Assessments/Mine.md")
        try "Mine.\n".write(to: mine, atomically: true, encoding: .utf8)
        let pagesThen: [String: Data] = pages(of: course)

        let undone: UndoOutcome = journal().undoNewest(resolveRoot: { _ in self.root })

        guard case .refused(.changedSince(let first, _), _) = undone else {
            return XCTFail("\(undone)")
        }
        // Named as the teacher finds the folder now, the renamed one
        // (`UndoOp.placeAsFound`). MUST FAIL with the move named by its
        // place before the step (`placeName`: `section1/Tasks`).
        XCTAssertEqual(first, "courses/ICS3U/section1/Assessments")
        XCTAssertEqual(pages(of: course), pagesThen, "a refused Undo moves nothing")
    }

    /// Another window saves another setting between the rename and its
    /// Undo: the Undo takes the rename's settings back and leaves the other
    /// window's.
    func testAnotherWindowsSaveOfAnotherSettingBetweenTheRenameAndItsUndoIsLeft() async throws {
        let course: Course = try course()
        _ = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        let other: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        other.showReadingTime = true
        try other.write(to: course.configFileURL)

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))

        let now: NSDictionary = try settings(of: course)
        XCTAssertEqual(now["hidden"] as? [String], ["Tasks"])
        XCTAssertEqual(now["per_section_folders"] as? [String], ["All Classes", "Tasks"])
        XCTAssertEqual(now["show_reading_time"] as? Bool, true, "the other window's setting is left")
    }

    /// A capitalisation-only rename of a shared folder (`Concepts` to
    /// `concepts`) is one step that undoes and redoes, the folder listed
    /// under each spelling in turn.
    func testACapitalisationOnlyRenameUndoesAndRedoes() async throws {
        let course: Course = try course()
        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "concepts", scope: .shared)
        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertTrue(listed(course.directoryURL).contains("concepts"))
        XCTAssertEqual(try newestOps()[0].to, "courses/ICS3U/concepts")
        XCTAssertEqual(pages(of: course)["concepts/Arrays.md"], Data("See [[concepts/Loops]].\n".utf8))

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertTrue(listed(course.directoryURL).contains("Concepts"))
        XCTAssertEqual(pages(of: course)["Concepts/Arrays.md"], Data("See [[Concepts/Loops]].\n".utf8))

        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertTrue(listed(course.directoryURL).contains("concepts"))
    }

    /// After an Undo the folder is back at its old place, so a kept copy of
    /// a page inside it is under the move's `from`: the step's kept
    /// original is looked for where the page is now, or a Redo resting on
    /// it would come to content missing (the part-two review's M1, second
    /// layer). MUST FAIL with `keptOriginal` looking beside the op's path.
    func testAKeptOriginalOfAPageInsideAMovedFolderIsFoundWhereThePageIsNow() async throws {
        let course: Course = try course()
        _ = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        let kept: Data = Data("See [[Assessments/Quiz 2]].\n".utf8)
        let keptURL: URL = course.directoryURL.appendingPathComponent("section1/Tasks/.Quiz 1.md\(UndoSwap.stagedMarker)1-undo-orig")
        try kept.write(to: keptURL)
        let step: UndoStep = try XCTUnwrap(try journal().read().records[1]).step

        let found: Data? = UndoRecovery.keptOriginal(of: step, root: root)(
            "courses/ICS3U/section1/Assessments/Quiz 1.md", UndoHash.sha256(of: kept)
        )

        XCTAssertEqual(found, kept)
    }

    // MARK: - Save, then rename (U4a review 1, LOW 1)

    /// Save Course Settings, then rename a folder, then Undo and Undo: both
    /// steps go back, the rename first, and nothing is refused. Both touch
    /// `expandable`. MUST FAIL with the rename's settings written as one
    /// `writeFile`: the Save's Undo then finds the file changed since.
    func testSaveThenRenameThenUndoAndUndoTakesBothBack() async throws {
        let course: Course = try course()
        let settingsBefore: NSDictionary = try settings(of: course)
        let pagesBefore: [String: Data] = pages(of: course)
        let view: CourseSettingsView = CourseSettingsView(course: course)
        course.configuration.expandableItems = ["Tasks"]
        view.save()
        _ = await view.renameFolder("Tasks", to: "Assessments", scope: .perSection)
        XCTAssertEqual(try settings(of: course)["expandable"] as? [String], ["Assessments"])

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 2))
        XCTAssertEqual(try settings(of: course)["expandable"] as? [String], ["Tasks"])
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))

        XCTAssertEqual(try settings(of: course), settingsBefore)
        XCTAssertEqual(pages(of: course), pagesBefore)
    }

    // MARK: - Refused, killed, and the switch off

    /// A rename refused part way (the second folder in use at its swap)
    /// writes nothing, says so in the contract's sentence, and leaves no
    /// step to undo. MUST FAIL before U4b, when the first section's folder
    /// had moved and the sheet said "renamed 1 of 2 copies".
    func testARefusedRenameWritesNothingAndSaysSo() async throws {
        let course: Course = try course()
        let pagesBefore: [String: Data] = pages(of: course)
        let settingsBytes: Data = try Data(contentsOf: course.configFileURL)
        UndoKillPoints.fileInUseAtSwap = { index in index == 1 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.nothingWasChanged(renaming: "Tasks", said: "")), said)
        XCTAssertEqual(pages(of: course), pagesBefore)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBytes)
        XCTAssertEqual(course.configuration.perSectionFolders, ["All Classes", "Tasks"])
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged file was left")
    }

    /// Killed between the two folders' moves, between the moves and the
    /// pages, and before `applied`: recovery leaves every place whole before
    /// or whole after, never one section renamed and not the other.
    func testARenameKilledBetweenItsMovesIsWholeAfterRecovery() async throws {
        try await killARename(at: .beforeSwap(1))
    }

    /// The first section's folder moved and the page it carries edited in
    /// (the swap's order: each move, then the edits it carries), the second
    /// section's folder not: the page's kept original is inside the moved
    /// folder, and the put-back must not count it as the folder's content.
    /// MUST FAIL with the plan or the swap judging the move with the
    /// step's own kept files inside (the part-two review's M1).
    func testARenameKilledBetweenItsMovesAndItsPagesIsWholeAfterRecovery() async throws {
        try await killARename(at: .beforeSwap(2))
    }

    func testARenameKilledBeforeAppliedIsWholeAfterAfterRecovery() async throws {
        try await killARename(at: .beforeApplied)
    }

    /// Killed before EVERY swap of the step in turn, until a kill point is
    /// no longer reached (the step has no more swaps): each is whole before
    /// or whole after once recovery has run, and none leaves a staged file.
    func testARenameKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery() async throws {
        var index: Int = 0
        while try await killARename(at: .beforeSwap(index)) {
            try? FileManager.default.removeItem(at: listFolder)
            try? FileManager.default.removeItem(at: root)
            try await setUp()
            index += 1
        }
        XCTAssertGreaterThanOrEqual(index, 4, "two moves, two pages and the settings: at least four swaps")
    }

    /// Returns whether the kill point was reached (and so tested).
    @discardableResult
    func killARename(at point: UndoKillPoint) async throws -> Bool {
        let course: Course = try course()
        let pagesBefore: [String: Data] = pages(of: course)
        let settingsBefore: NSDictionary = try settings(of: course)
        let settingsBytesBefore: Data = try Data(contentsOf: course.configFileURL)
        var reachedIt: Bool = false
        UndoKillPoints.hook = { reached in
            if reached == point {
                reachedIt = true
                return true
            }
            return false
        }
        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        UndoKillPoints.hook = nil
        if !reachedIt {
            return false
        }
        XCTAssertNotNil(failed(result), "\(point)")

        let workingRoot: URL = root
        await UndoRecovery.recoverAndRederive(journal(processIsAlive: false), resolveRoot: { _ in workingRoot })

        var now: [String: Data] = pages(of: course)
        // The settings are put back by member (`editJSON`): the values
        // come back, the teacher's spacing does not, so the apply's kept
        // original of the settings file is the only copy of those bytes and
        // stays beside it ("an only copy is never deleted"). It must be
        // exactly the file as it was before the step; it is no staged file.
        let keptSettings: URL = course.directoryURL.appendingPathComponent(".course_config.json.plantoir-undo-1-apply-orig")
        if let kept = now.removeValue(forKey: ".course_config.json.plantoir-undo-1-apply-orig") {
            XCTAssertEqual(kept, settingsBytesBefore, "the kept settings are not the file as it was, at \(point)")
            try FileManager.default.removeItem(at: keptSettings)
        }
        if now == pagesBefore {
            XCTAssertEqual(try settings(of: course), settingsBefore, "pages whole before, settings not")
        } else {
            XCTAssertEqual(now["section1/Assessments/Quiz 1.md"], Data("See [[Assessments/Quiz 2]].\n".utf8), "not whole after at \(point)")
            XCTAssertEqual(now["section2/Assessments/Quiz 2.md"], Data("Quiz two.\n".utf8), "not whole after at \(point)")
            XCTAssertEqual(now["section1/index.md"], Data("Start with [[Assessments/Quiz 1]].\n".utf8), "not whole after at \(point)")
            XCTAssertEqual(now.count, pagesBefore.count, "not whole after at \(point)")
            XCTAssertEqual(try settings(of: course)["hidden"] as? [String], ["Assessments"], "pages whole after, settings not")
        }
        if point == .beforeApplied {
            XCTAssertNotEqual(now, pagesBefore, "a step whose swap went in is completed")
        }
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged file was left at \(point)")
        return true
    }

    /// With the switch off, a list that cannot take the step changes
    /// nothing about a rename: the same folders, pages and settings as with
    /// one that can (`rule.shadow`).
    func testInShadowAListThatCannotBeWrittenChangesNothingAboutARename() async throws {
        JournaledStep.modeOverride = .shadow
        let first: Course = try course()
        _ = await CourseSettingsView(course: first).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        let expectedPages: [String: Data] = pages(of: first)
        let expectedSettings: Data = try Data(contentsOf: first.configFileURL)
        try FileManager.default.removeItem(at: root)

        let broken: URL = listFolder.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: broken.appendingPathComponent("undo"))
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)
        let course: Course = try course()

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(pages(of: course), expectedPages)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), expectedSettings)
    }
    /// The recovery the app runs with the switch off: inside the next
    /// step's begin, in shadow (`JournaledWrite.begin`), here with the
    /// killed process gone. Shadow recovery records and never repairs.
    func recoverInShadow() throws {
        let workingRoot: URL = root
        _ = try journal(processIsAlive: false).withLock { writer -> [UndoRecoveryResult] in
            return UndoRecovery.run(writer, mode: .shadow, trySwapsNow: false, resolveRoot: { _ in workingRoot })
        }
    }

    /// With the switch off, a rename of a shared folder killed after its
    /// move and before its page (`beforeSwap(1)`: the swap's order is each
    /// move, then the edits it carries, so target 0 is the move and target
    /// 1 the page inside it) leaves its record, and the rename sheet
    /// finishes it from there, as before U4b: the record names the target,
    /// and renaming again relinks the page and writes the settings. MUST
    /// FAIL with the record not written before the step (the director's
    /// ruling of 2026-11-21: kept while the switch is off).
    func testWithTheSwitchOffARenameKilledPartWayIsFinishedFromItsRecord() async throws {
        JournaledStep.modeOverride = .shadow
        let course: Course = try course()
        UndoKillPoints.hook = { reached in reached == .beforeSwap(1) }
        _ = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)
        UndoKillPoints.hook = nil
        try recoverInShadow()
        // Nothing left behind (part four's review, L3): the step's own
        // staged files are tidied by shadow recovery, as before U4b a killed
        // rename left no dot-files. MUST FAIL with shadow tidying only steps
        // of files.
        XCTAssertFalse(UndoContractReplay.staysBeside(root), "a staged file was left beside a page or the settings")
        XCTAssertEqual(pages(of: course)["Ideas/Arrays.md"], Data("See [[Concepts/Loops]].\n".utf8), "the kill left the move in, not the page")
        XCTAssertEqual(try settings(of: course)["shared_folders"] as? [String], ["Concepts"], "the kill left the settings as they were")

        let target: String? = SpecialFolderRenamer.interruptedRenameTarget(
            from: "Concepts", scope: .shared, courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertEqual(target, "Ideas")
        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(pages(of: course)["Ideas/Arrays.md"], Data("See [[Ideas/Loops]].\n".utf8))
        XCTAssertEqual(try settings(of: course)["shared_folders"] as? [String], ["Ideas"])
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    /// With the switch off, a per-section rename killed BETWEEN its
    /// sections (`beforeSwap(1)`: the first section's folder moved, the
    /// second's not) is a mixture, which the record's rule has never
    /// finished (`SpecialFolderRenamerTests.testAMixtureIsNotTreatedAsAnInterruptedRename`):
    /// pinned as it is today, and owed to U7, whose live recovery settles
    /// it whole (`testARenameKilledBeforeAnyOfItsSwapsIsWholeAfterRecovery`).
    func testWithTheSwitchOffARenameKilledBetweenItsSectionsIsLeftAsTodaysRecordLeavesIt() async throws {
        JournaledStep.modeOverride = .shadow
        let course: Course = try course()
        UndoKillPoints.hook = { reached in reached == .beforeSwap(1) }
        _ = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        UndoKillPoints.hook = nil
        try recoverInShadow()
        let now: [String: Data] = pages(of: course)
        XCTAssertNotNil(now["section1/Assessments/Quiz 1.md"], "the first section's folder moved")
        XCTAssertNotNil(now["section2/Tasks/Quiz 2.md"], "the second section's folder did not")

        let target: String? = SpecialFolderRenamer.interruptedRenameTarget(
            from: "Tasks", scope: .perSection, courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertNil(target, "a mixture is not an interrupted rename (today's rule, owed to U7)")
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path), "the record is kept")
    }

    // MARK: - Off the main actor, links, part-way sentences (part four's review)

    /// The rename's check and swap, which read and hash every file in each
    /// moved folder, run OFF the main actor (part four's review, M1): the
    /// swap is held at its first page while the main actor runs, sees the
    /// rename under way with Save disabled, and a second rename is refused
    /// with nothing changed. An event, not a time: the hold opens only when
    /// the main actor opens it, and a swap on the main thread is recorded
    /// and not held. MUST FAIL with `step.make()` called on the main actor
    /// (the swap is reached on the main thread).
    func testTheRenameIsMadeOffTheMainActorAndNothingElseStartsMeanwhile() async throws {
        let course: Course = try course()
        course.configuration.courseName = "Computer Science"
        let view: CourseSettingsView = CourseSettingsView(course: course)
        XCTAssertTrue(view.saveIsEnabled, "an unsaved edit makes Save enabled before the rename")
        let reached: XCTestExpectation = XCTestExpectation(description: "the swap reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        UndoKillPoints.beforeTheRename = { @Sendable (index: Int, place: URL) in
            gate.arrive()
        }
        let first: Task<RenameResult, Never> = Task { @MainActor in
            return await view.renameFolder("Tasks", to: "Assessments", scope: .perSection)
        }
        await fulfillment(of: [reached])

        XCTAssertEqual(gate.wasOnTheMainThread, false, "the swap ran on the main thread")
        XCTAssertTrue(course.isRenamingAFolder)
        XCTAssertFalse(view.saveIsEnabled, "Save is disabled while the rename is under way")
        let second: RenameResult = await view.renameFolder("Concepts", to: "Ideas", scope: .shared)
        XCTAssertNotNil(failed(second), "\(second)")
        XCTAssertEqual(listed(course.directoryURL).contains("Concepts"), true, "the second rename changed nothing")
        gate.open()
        let result: RenameResult = await first.value

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertFalse(course.isRenamingAFolder)
        XCTAssertTrue(view.saveIsEnabled)
        XCTAssertEqual(try journal().read().records.count, 1, "one step: the second rename never began")
    }

    /// A folder holding a symbolic link is renamed as before U4b (part
    /// four's review, L4), the link moved as a link and never followed (it
    /// leads nowhere), and the step undoes and redoes. MUST FAIL with a link
    /// read as not a folder (`.notATree`: refused, cannot tell now).
    func testAFolderHoldingASymbolicLinkIsRenamedWithTheLinkMovedAsALink() async throws {
        let course: Course = try course()
        let link: URL = course.directoryURL.appendingPathComponent("section1/Tasks/Handout.pdf")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/nowhere/Handout.pdf")

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        let moved: String = course.directoryURL.appendingPathComponent("section1/Assessments/Handout.pdf").path
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: moved), "/nowhere/Handout.pdf")
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 1))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "/nowhere/Handout.pdf")
        XCTAssertEqual(journal().redoNewest(resolveRoot: { _ in self.root }), .redone(seq: 1))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: moved), "/nowhere/Handout.pdf")
    }

    /// A per-section rename refused at its second section whose first
    /// section's folder then cannot be moved back says so, naming that
    /// folder at its new name (part four's review, L1): "was not renamed"
    /// would be false of the disk. MUST FAIL with the old sentence.
    func testARenameStoppedWithAFolderLeftRenamedSaysWhichFolder() async throws {
        let course: Course = try course()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 0 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertNotNil(pages(of: course)["section1/Assessments/Quiz 1.md"], "the first section's folder was left renamed")
        XCTAssertTrue(said.hasPrefix("“Tasks” was renamed only in part"), said)
        XCTAssertTrue(said.contains("“section1/Assessments”"), said)
        XCTAssertFalse(said.contains("section2"), said)
    }

    /// A rename refused as changed since and planned again, whose re-plan
    /// is then refused (its destination appeared), leaves no record behind
    /// (part four's review, L2): nothing was changed, so the one-section
    /// restore is offered as before. MUST FAIL with the record cleared only
    /// at the end.
    func testARetryWhoseReplanIsRefusedLeavesNoRecord() async throws {
        let course: Course = try course()
        // Once the step has begun: a teacher's file appears inside section
        // 1's folder (the step is refused as changed since, nothing changed)
        // and a folder at section 2's new name (the re-plan is refused).
        let mine: URL = course.directoryURL.appendingPathComponent("section1/Tasks/Mine.md")
        let appeared: URL = course.directoryURL.appendingPathComponent("section2/Assessments")
        UndoKillPoints.hook = { @Sendable (reached: UndoKillPoint) in
            if reached == .afterBegin && !FileManager.default.fileExists(atPath: appeared.path) {
                try? "Mine.\n".write(to: mine, atomically: true, encoding: .utf8)
                try? FileManager.default.createDirectory(at: appeared, withIntermediateDirectories: true)
            }
            return false
        }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(failed(result), "\(result)")
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "the record is left after a refused re-plan")
    }

    // MARK: - Part six: one piece of work the whole app knows about

    /// A second window's copy of the same course, as `WorkspaceModel`
    /// makes one per window.
    func anotherWindowsCopy(of course: Course) throws -> Course {
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: course.configFileURL)
        return Course(code: course.code, directoryURL: course.directoryURL, configuration: loaded)
    }

    /// While a rename runs in one window, ANOTHER window's copy of the
    /// course knows (U4b part six's review, M2): its Save is disabled and
    /// says why, its own rename is refused with nothing changed and the
    /// first rename's record left as it was, and every structural act,
    /// removal and replacement is refused with a sentence naming the
    /// rename. A Cancel that lands once the swap has begun does not halt it.
    /// MUST FAIL with the busy mark kept on one window's `Course`.
    func testWhileARenameRunsAnotherWindowsCopyOfTheCourseIsHeldToo() async throws {
        let course: Course = try course()
        let other: Course = try anotherWindowsCopy(of: course)
        other.configuration.courseName = "Computer Science"
        let otherView: CourseSettingsView = CourseSettingsView(course: other)
        XCTAssertTrue(otherView.saveIsEnabled)
        let reached: XCTestExpectation = XCTestExpectation(description: "the swap reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        UndoKillPoints.beforeTheRename = { @Sendable (index: Int, place: URL) in
            gate.arrive()
        }
        let first: Task<RenameResult, Never> = Task { @MainActor in
            return await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        }
        await fulfillment(of: [reached])
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        let recorded: Data = try Data(contentsOf: record)

        XCTAssertTrue(other.isRenamingAFolder, "the other window's copy does not know")
        XCTAssertTrue(CourseActivity.folderRenameIsSwapping(folderPath: root.path, courseCode: "ICS3U"))
        XCTAssertFalse(otherView.saveIsEnabled, "the other window's Save is enabled")
        let sentence: String = CourseActivity.folderRenameIsUnderWay(course: "ICS3U")
        XCTAssertEqual(otherView.folderRenameProblem("Concepts", to: "Ideas", scope: .shared), sentence)
        let second: RenameResult = await otherView.renameFolder("Concepts", to: "Ideas", scope: .shared)
        XCTAssertNotNil(failed(second), "\(second)")
        XCTAssertTrue(listed(course.directoryURL).contains("Concepts"), "the second rename changed something")
        XCTAssertEqual(try Data(contentsOf: record), recorded, "the second rename touched the first's record")
        XCTAssertEqual(
            CourseActivity.structuralHoldReason(folderPath: root.path, courseCode: "ICS3U", revisedElsewhere: false),
            CourseActivity.availableOnceTheFolderIsRenamed
        )
        let removal: ScheduledDeployCleanup.RemovalResult = await ScheduledDeployCleanup.removeCourse(
            other, coursesDirectoryURL: root.appendingPathComponent("courses")
        )
        XCTAssertFalse(removal.didRemove)
        XCTAssertEqual(removal.problem, sentence)
        XCTAssertEqual(
            ReferenceReplacer.Problem.folderBeingRenamed(course: "ICS3U").errorDescription, sentence
        )
        first.cancel()
        gate.open()
        let result: RenameResult = await first.value

        XCTAssertNotNil(renamed(result), "a Cancel after the swap began halted it: \(result)")
        XCTAssertFalse(other.isRenamingAFolder)
        XCTAssertNil(CourseActivity.structuralHoldReason(folderPath: root.path, courseCode: "ICS3U", revisedElsewhere: false))
        XCTAssertEqual(try journal().read().records.count, 1, "one step: the second rename never began")
    }

    /// ⌘Q during a rename waits for it (U4b part six's review, M1), as it
    /// waits for a tools copy (#476): the quit's wait resumes only once the
    /// step is made and the rename's claim has ended. MUST FAIL with the
    /// rename left out of the quit's wait (`AppDelegate.waitForWorkUnderWay`,
    /// which `applicationShouldTerminate` awaits; part seven's review, L6).
    func testAQuitDuringARenameWaitsForItToFinish() async throws {
        let course: Course = try course()
        let reached: XCTestExpectation = XCTestExpectation(description: "the swap reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        UndoKillPoints.beforeTheRename = { @Sendable (index: Int, place: URL) in
            gate.arrive()
        }
        let first: Task<RenameResult, Never> = Task { @MainActor in
            return await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        }
        await fulfillment(of: [reached])

        XCTAssertTrue(AppDelegate.quitWaitsForWorkUnderWay(
            toolchainCopying: false, renamingAFolder: CourseActivity.anyFolderRenameIsUnderWay
        ), "the quit does not wait for the rename")
        let quit: Task<(Bool, Int), Never> = Task { @MainActor in
            // The quit's own wait, as `applicationShouldTerminate` runs it
            // (part seven's review, L6).
            await AppDelegate.waitForWorkUnderWay()
            let steps: Int = (try? self.journal().read().records.count) ?? -1
            return (CourseActivity.anyFolderRenameIsUnderWay, steps)
        }
        // Until the quit's wait is registered: a bound on turns, not a time.
        var turns: Int = 0
        while CourseActivity.store.folderRenameWaiters.isEmpty && turns < 10_000 {
            await Task.yield()
            turns += 1
        }
        XCTAssertEqual(CourseActivity.store.folderRenameWaiters.count, 1, "the quit is not waiting for the rename")
        gate.open()
        let (stillUnderWay, steps): (Bool, Int) = await quit.value
        let result: RenameResult = await first.value

        XCTAssertFalse(stillUnderWay, "the quit went on while the rename ran")
        XCTAssertEqual(steps, 1, "the quit went on before the step was made")
        XCTAssertNotNil(renamed(result), "\(result)")
    }

    /// A rename halted at Cancel while it is only planning (the plan writes
    /// nothing) makes nothing (U4b part six's review, L3): no step, no
    /// record, the folders as they were, and the course free again. MUST
    /// FAIL with the halt not asked before the swap.
    func testARenameCancelledWhileItPlansChangesNothing() async throws {
        let course: Course = try course()
        let before: [String: Data] = pages(of: course)
        let halted: Task<RenameResult, Never> = Task { @MainActor in
            return await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        }
        halted.cancel()
        let result: RenameResult = await halted.value

        XCTAssertNotNil(failed(result), "\(result)")
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try journal().read().records.count, 0)
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
        XCTAssertFalse(course.isRenamingAFolder)
    }

    // MARK: - Part seven: Cancel gives the course back

    /// Cancel while the plan is still walking the course (U4b part seven's
    /// review, M1): the plan is held open at its first page on an event,
    /// then the rename is cancelled. The rename returns at once, without
    /// waiting for the held read; the claim is gone, so Save is enabled and
    /// the course is free; nothing is on disk, no step, no record. Letting
    /// the held plan go on afterwards changes nothing: it stops at its next
    /// page and reads no other. MUST FAIL with the plan awaited as a
    /// detached task's `value` (the rename waits for the held read), and
    /// with the plan not checking for cancellation (it reads every page).
    func testCancelWhileThePlanIsHeldGivesTheCourseBackAndTheHeldPlanChangesNothing() async throws {
        let course: Course = try course()
        course.configuration.courseName = "Computer Science"
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let reached: XCTestExpectation = XCTestExpectation(description: "the plan reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        addTeardownBlock {
            gate.open()
        }
        let pagesRead: PlanPageCount = PlanPageCount()
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            pagesRead.add()
            gate.arrive()
        }
        let ended: XCTestExpectation = XCTestExpectation(description: "the cancelled plan stopped")
        SpecialFolderRenamer.planHasEnded = { @Sendable in
            ended.fulfill()
        }
        let returned: XCTestExpectation = XCTestExpectation(description: "the rename returned")
        let halted: Task<RenameResult, Never> = Task { @MainActor in
            let result: RenameResult = await view.renameFolder("Tasks", to: "Assessments", scope: .perSection)
            returned.fulfill()
            return result
        }
        await fulfillment(of: [reached])
        XCTAssertTrue(course.isRenamingAFolder, "the claim is held while the plan walks")
        XCTAssertFalse(view.saveIsEnabled)

        halted.cancel()
        // The event is the rename returning; the bound only turns a rename
        // that waits for the held read into a failure rather than a hang.
        // A rename that waited would never return while the plan is held,
        // so the hold is opened before awaiting it: the test then fails
        // rather than hanging the run.
        let waited: XCTWaiter.Result = await XCTWaiter().fulfillment(of: [returned], timeout: 30)
        if waited != .completed {
            gate.open()
            XCTFail("the rename waited for the held plan after Cancel")
        }
        let result: RenameResult = await halted.value

        XCTAssertNotNil(failed(result), "\(result)")
        XCTAssertFalse(course.isRenamingAFolder, "the course is still held after Cancel")
        XCTAssertFalse(CourseActivity.anyFolderRenameIsUnderWay, "a quit would wait for a cancelled plan")
        XCTAssertTrue(view.saveIsEnabled, "Save is not enabled after Cancel")
        XCTAssertNil(view.folderRenameProblem("Concepts", to: "Ideas", scope: .shared))
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))

        gate.open()
        await fulfillment(of: [ended])

        XCTAssertEqual(pagesRead.count, 1, "the cancelled plan went on reading pages")
        XCTAssertEqual(pages(of: course), before, "the held plan changed a page once it went on")
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0, "the held plan reached the swap")
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
        XCTAssertFalse(course.isRenamingAFolder)
    }

    /// An ended claim is never taken up again (part seven's review, M1):
    /// the swap refuses a rename whose claim has been given back, so a plan
    /// whose rename was cancelled can never reach it. MUST FAIL with
    /// `folderRenameSwapBegins` marking the swap whether or not the claim is
    /// held.
    func testTheSwapRefusesARenameWhoseClaimHasEnded() throws {
        let claim: CourseActivity.FolderRenameRecord = try XCTUnwrap(
            CourseActivity.beginFolderRename(folderPath: root.path, courseCode: "ICS3U")
        )
        CourseActivity.endFolderRename(claim)

        XCTAssertFalse(CourseActivity.folderRenameSwapBegins(claim), "an ended claim began its swap")
        XCTAssertFalse(CourseActivity.anyFolderRenameIsUnderWay)
        XCTAssertFalse(CourseActivity.folderRenameIsSwapping(folderPath: root.path, courseCode: "ICS3U"))
    }

    /// A rename while a copy of the course is being saved (a backup, or the
    /// archive before a removal or restore) is refused before it plans, with
    /// the sentence naming the copy, in the sheet and at the click (part
    /// seven's review, L1). MUST FAIL with the old "The file couldn’t be
    /// saved." sentence, or with the sheet's Rename left enabled.
    func testARenameWhileACopyIsBeingSavedIsRefusedNamingTheCopy() async throws {
        let course: Course = try course()
        let before: [String: Data] = pages(of: course)
        CourseActivity.beginCopy(folderPath: root.path, courseCode: "ICS3U")
        defer {
            CourseActivity.endCopy(folderPath: root.path, courseCode: "ICS3U")
        }
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let sentence: String = AssistWording.courseIsBeingCopiedFromTheMenu(course: "ICS3U")

        XCTAssertEqual(view.folderRenameProblem("Tasks", to: "Assessments", scope: .perSection), sentence)
        let result: RenameResult = await view.renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertEqual(failed(result), sentence)
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try journal().read().records.count, 0)
        XCTAssertFalse(course.isRenamingAFolder)
    }

    /// While a rename of the course runs, a section's greyed Preview and
    /// Deploy say why in their help tags, and the course's sidebar row
    /// shows it busy, as for a copy being zipped (part seven's review, L2).
    /// The folder's tools getting ready still wins. MUST FAIL with the
    /// rename left out of either rule.
    func testWhileARenameRunsPreviewDeployAndTheSidebarRowSayWhy() {
        let reason: String? = SectionDetailView.greyedReason(folderReadinessReason: nil, renamingAFolder: true)
        XCTAssertEqual(reason, CourseActivity.availableOnceTheFolderIsRenamed)
        XCTAssertEqual(
            SectionDetailView.deployHelp(folderReadinessReason: reason, heldElsewhere: false, courseCode: "ICS3U"),
            CourseActivity.availableOnceTheFolderIsRenamed
        )
        XCTAssertNil(SectionDetailView.greyedReason(folderReadinessReason: nil, renamingAFolder: false))
        XCTAssertEqual(SectionDetailView.greyedReason(folderReadinessReason: "Getting ready", renamingAFolder: true), "Getting ready")
        XCTAssertEqual(CourseRowLabel.workUnderWay(isBeingCopied: false, isRenamingAFolder: true), "Renaming a folder")
        XCTAssertEqual(CourseRowLabel.workUnderWay(isBeingCopied: true, isRenamingAFolder: false), "Saving a copy")
        XCTAssertNil(CourseRowLabel.workUnderWay(isBeingCopied: false, isRenamingAFolder: false))
    }

    /// A move back that fails because something appeared at the old name
    /// still names the folder left at its new name (U4b part six's review,
    /// L1). MUST FAIL with a folder counted only when its old name is free.
    func testAMoveBackBlockedAtTheOldNameStillSaysWhichFolderIsRenamed() async throws {
        let course: Course = try course()
        let appeared: URL = course.directoryURL.appendingPathComponent("section1/Tasks/Other.md")
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in
            if index != 1 {
                return false
            }
            try? FileManager.default.createDirectory(
                at: appeared.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? "Other.\n".write(to: appeared, atomically: true, encoding: .utf8)
            return true
        }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertNotNil(pages(of: course)["section1/Assessments/Quiz 1.md"], "the first section's folder was put back")
        XCTAssertTrue(said.hasPrefix("“Tasks” was renamed only in part"), said)
        XCTAssertTrue(said.contains("“section1/Assessments”"), said)
    }
}

/// Holds a rename's swap at its first page until the main actor opens it,
/// and records whether it was reached on the main thread (then it does not
/// hold, so a swap on the main actor fails the test rather than hanging it).
final class RenameHold: @unchecked Sendable {

    // MARK: - Stored properties

    let reached: XCTestExpectation

    let condition: NSCondition = NSCondition()

    var hasArrived: Bool = false

    var isOpen: Bool = false

    var wasOnTheMainThread: Bool? = nil

    // MARK: - Initializer

    init(reached: XCTestExpectation) {
        self.reached = reached
    }

    // MARK: - Functions

    func arrive() {
        condition.lock()
        if hasArrived {
            condition.unlock()
            return
        }
        hasArrived = true
        let onMain: Bool = Thread.isMainThread
        wasOnTheMainThread = onMain
        condition.unlock()
        reached.fulfill()
        if onMain {
            return
        }
        condition.lock()
        while !isOpen {
            condition.wait()
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Counts the pages a plan has begun to read, from any thread.
final class PlanPageCount: @unchecked Sendable {

    // MARK: - Stored properties

    let lock: NSLock = NSLock()

    var pages: Int = 0

    // MARK: - Computed properties

    var count: Int {
        lock.lock()
        let counted: Int = pages
        lock.unlock()
        return counted
    }

    // MARK: - Functions

    func add() {
        lock.lock()
        pages += 1
        lock.unlock()
    }
}
