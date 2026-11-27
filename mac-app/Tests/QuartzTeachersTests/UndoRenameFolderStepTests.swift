import XCTest
import AppKit
import SwiftUI
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
        useFreshFolders()
    }

    /// A new list folder and working folder, the list and the trail pointed
    /// at them. Never takes `previousTrail` again: a test that starts over
    /// calls this, not `setUp`, or the trail it puts back at the end is this
    /// test's own, whose folder is removed and then made again by every
    /// later class's lines (the folder the suite reported left behind).
    func useFreshFolders() {
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
        FolderRenameRun.runsUnderWay = []
        FolderRenameRun.quitIsGoingAhead = false
        // The trail put back is the one from before this test, never one
        // this class made: that folder is removed, and every later line
        // would make it again. MUST FAIL with a test that starts over by
        // calling `setUp` (it takes `previousTrail` a second time).
        XCTAssertFalse(
            previousTrail.folderURL.lastPathComponent == ".trail"
                && previousTrail.folderURL.deletingLastPathComponent().lastPathComponent.hasPrefix("undo-rename-"),
            "the trail put back is one of this class's own"
        )
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

    /// The plan's pages are in the order of their paths after the move
    /// (`ClassPages.isInPathOrder`), never the order the disk lists them
    /// (review 1 of U4b2-11, M1). Independent of the volume's own order
    /// (review 2 of U4b2-11, LOW C: an HFS+ folder lists in path order
    /// already): the plan's order is checked, and the same pages handed to
    /// `inPathOrder` in both orders come back in that one order.
    /// MUST FAIL with the plan's pages left in walk order (on APFS) and with
    /// `inPathOrder` returning its pages as given (on every volume).
    func testARenamePlansItsPagesInPathOrderNotTheDisksOrder() throws {
        let course: Course = try course()
        try "Start with [[Concepts/Arrays]].\n".write(
            to: course.directoryURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8
        )

        let planned: FolderRenamePlan = try SpecialFolderRenamer.plan(
            "Concepts", to: "Ideas", scope: .shared,
            courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertEqual(placesInside(course, of: planned.pages), ["Ideas/Arrays.md", "section1/index.md"])

        var reversed: [FolderRenamePlan.Page] = []
        for page in planned.pages {
            reversed.insert(page, at: 0)
        }
        XCTAssertEqual(
            placesInside(course, of: SpecialFolderRenamer.inPathOrder(reversed, under: course.directoryURL)),
            ["Ideas/Arrays.md", "section1/index.md"]
        )
        XCTAssertEqual(
            placesInside(course, of: SpecialFolderRenamer.inPathOrder(planned.pages, under: course.directoryURL)),
            ["Ideas/Arrays.md", "section1/index.md"]
        )
    }

    /// A linked page is ordered by its own place, never its target's (review
    /// 2 of U4b2-11, LOW B): `section1/zzz.md` is a link to a page outside
    /// the course whose path sorts before every page of the course, and it
    /// still comes after `section1/index.md`, by its place in the course.
    /// MUST FAIL with each page keyed by `UndoFolderPlaces.canonicalPath`
    /// (which follows the link).
    func testALinkedPageIsInPathOrderByItsOwnPlaceNotItsTarget() throws {
        let course: Course = try course()
        try "Start with [[Concepts/Arrays]].\n".write(
            to: course.directoryURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8
        )
        let outside: URL = root.deletingLastPathComponent().appendingPathComponent("aaa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: outside)
        }
        let target: URL = outside.appendingPathComponent("aaa.md")
        try "See [[Concepts/Loops]].\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: course.directoryURL.appendingPathComponent("section1/zzz.md"), withDestinationURL: target
        )
        XCTAssertTrue(
            UndoFolderPlaces.canonicalPath(of: target).lowercased() < UndoFolderPlaces.canonicalPath(of: course.directoryURL).lowercased(),
            "the link's target no longer sorts before the course, so this test could not fail"
        )

        let planned: FolderRenamePlan = try SpecialFolderRenamer.plan(
            "Concepts", to: "Ideas", scope: .shared,
            courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )

        XCTAssertEqual(
            placesInside(course, of: planned.pages),
            ["Ideas/Arrays.md", "section1/index.md", "section1/zzz.md"]
        )
    }

    /// Two paths alike once lowercased, in case only, are ordered by their
    /// UTF-8 bytes as spelled, no locale (review 2 of U4b2-11, LOW A), so the
    /// one order is total and never the walk's.
    /// MUST FAIL with the tie left to the order the pages came in.
    func testPathsAlikeButForCaseOrUnicodeFormAreOrderedByTheirBytes() {
        let upper: URL = URL(fileURLWithPath: "/course/Unit/A.md")
        let lower: URL = URL(fileURLWithPath: "/course/Unit/a.md")
        XCTAssertTrue(ClassPages.isInPathOrder(upper, lower))
        XCTAssertFalse(ClassPages.isInPathOrder(lower, upper))
        // A file URL spells a path in one Unicode form whatever form it was
        // given in (measured: both come back decomposed), so on the Mac two
        // URLs that differ only in Unicode form are one place and no tie.
        let composed: URL = URL(fileURLWithPath: "/course/Unit/caf\u{E9}.md")
        let decomposed: URL = URL(fileURLWithPath: "/course/Unit/cafe\u{301}.md")
        XCTAssertEqual(Array(composed.path.utf8), Array(decomposed.path.utf8))
        XCTAssertFalse(ClassPages.isInPathOrder(composed, decomposed))
        XCTAssertFalse(ClassPages.isInPathOrder(upper, upper))
        XCTAssertTrue(ClassPages.isInPathOrder(lower, URL(fileURLWithPath: "/course/Unit/B.md")))
    }

    /// Each planned page's place inside the course, by the folder's own
    /// spelling made canonical.
    func placesInside(_ course: Course, of pages: [FolderRenamePlan.Page]) -> [String] {
        var placed: [String] = []
        let prefix: String = UndoFolderPlaces.canonicalPath(of: course.directoryURL) + "/"
        for page in pages {
            let path: String = UndoFolderPlaces.placeResolvingOnlyAbove(course.directoryURL, of: page.url) ?? page.url.path
            placed.append(String(path.dropFirst(prefix.count)))
        }
        return placed
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
            useFreshFolders()
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

    // MARK: - A per-section or shared folder that is itself a link (#1055: refused)

    /// Section 2's `Tasks` made a symbolic link, `../library/Tasks`, to a
    /// folder elsewhere in the course that holds section 2's page, which
    /// names section 1's quiz through `Tasks`.
    func linkSectionTwosTasks(in course: Course) throws {
        let sectionTwo: URL = course.directoryURL.appendingPathComponent("section2/Tasks")
        try FileManager.default.removeItem(at: sectionTwo)
        let target: URL = course.directoryURL.appendingPathComponent("library/Tasks")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "Quiz two, after [[Tasks/Quiz 1]].\n".write(
            to: target.appendingPathComponent("Quiz 2.md"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(atPath: sectionTwo.path, withDestinationPath: "../library/Tasks")
    }

    /// The target a symbolic link inside the course holds, or nil when
    /// nothing there is a link (never followed).
    func linkTarget(_ course: Course, _ place: String) -> String? {
        let path: String = course.directoryURL.appendingPathComponent(place).path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return nil
        }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// A dangling link at a section's place (it leads nowhere) is skipped,
    /// as before U4b, where `fileExists` followed it and found nothing: the
    /// other section's folder is renamed, the link is left at its old name
    /// with its target, and the step holds one move (review 1 of U4b2-15,
    /// L2). MUST FAIL with a dangling link planned as a link's move.
    func testADanglingLinkAtASectionsPlaceIsSkippedAsBeforeU4b() async throws {
        let course: Course = try course()
        let sectionTwo: URL = course.directoryURL.appendingPathComponent("section2/Tasks")
        try FileManager.default.removeItem(at: sectionTwo)
        try FileManager.default.createSymbolicLink(atPath: sectionTwo.path, withDestinationPath: "../nowhere/Tasks")

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Activities", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(linkTarget(course, "section2/Tasks"), "../nowhere/Tasks", "the dangling link was moved or changed")
        XCTAssertNil(linkTarget(course, "section2/Activities"))
        XCTAssertEqual(pages(of: course)["section1/Activities/Quiz 1.md"], Data("See [[Activities/Quiz 2]].\n".utf8))
        var moves: Int = 0
        for op in try newestOps() where op.kind == "move" {
            moves += 1
        }
        XCTAssertEqual(moves, 1, "only section 1's folder moves")
    }

    /// Everything under a folder by its path inside it, never following a
    /// link: a file by its bytes, a link by the text it holds, a folder by a
    /// mark. `leaving` names top-level entries left out (the trail).
    func everything(under folder: URL, leaving: [String] = []) -> [String: String] {
        var result: [String: String] = [:]
        var toVisit: [String] = [""]
        while !toVisit.isEmpty {
            let inside: String = toVisit.removeLast()
            let here: URL = inside.isEmpty ? folder : folder.appendingPathComponent(inside)
            let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: here.path)) ?? []
            for name in names {
                if inside.isEmpty && leaving.contains(name) {
                    continue
                }
                let path: String = inside.isEmpty ? name : inside + "/" + name
                let url: URL = folder.appendingPathComponent(path)
                let attributes: [FileAttributeKey: Any] = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
                let type: FileAttributeType? = attributes[.type] as? FileAttributeType
                if type == .typeSymbolicLink {
                    let target: String = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?"
                    result[path] = "link " + target
                } else if type == .typeDirectory {
                    result[path] = "folder"
                    toVisit.append(path)
                } else {
                    let data: Data = (try? Data(contentsOf: url)) ?? Data()
                    result[path] = "file " + data.base64EncodedString()
                }
            }
        }
        return result
    }

    /// The plan's refusal of a folder that is a link, by its error: U4b's
    /// `cannotTellNow` naming the folder's path, the file name its own.
    func assertThePlanRefuses(
        _ oldName: String, to newName: String, scope: FolderScope, in course: Course, place: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let location: URL = course.directoryURL.appendingPathComponent(place)
        do {
            _ = try SpecialFolderRenamer.plan(
                oldName, to: newName, scope: scope,
                courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
            )
            XCTFail("the plan of a folder that is a link was not refused", file: file, line: line)
        } catch JournaledStepError.refused(let refusal, let fileName) {
            XCTAssertEqual(refusal, .cannotTellNow(path: location.path), file: file, line: line)
            XCTAssertEqual(fileName, location.lastPathComponent, file: file, line: line)
        } catch {
            XCTFail("refused otherwise: \(error)", file: file, line: line)
        }
    }

    /// The sentence the teacher reads: the door's existing one for a
    /// refused step, naming the folder (U4b, before U4b2-15).
    func refusalSentence(renaming oldName: String, folder: String) -> String {
        let said: String = CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: folder]).localizedDescription
        return SpecialFolderRenamer.nothingWasChanged(renaming: oldName, said: said)
    }

    /// No step on the list, whether or not the list folder was ever made.
    func stepsOnTheList() -> Int {
        guard let fold = try? journal().read() else {
            return 0
        }
        return fold.records.count
    }

    /// Section 2's `Tasks` is a symbolic link: Rename folder refuses before
    /// anything changes, as U4b did (#1055: links are not supported), live
    /// and with the switch off. Every file and link under the working folder
    /// is as it was, the link compared by its text; no step; no rename
    /// record. MUST FAIL with the link moved as a link (U4b2-15).
    func testAPerSectionFolderThatIsALinkIsRefusedBeforeAnythingChanges() async throws {
        let modes: [UndoMode] = [.live, .shadow]
        for mode in modes {
            try? FileManager.default.removeItem(at: listFolder)
            try? FileManager.default.removeItem(at: root)
            useFreshFolders()
            JournaledStep.modeOverride = mode
            let course: Course = try course()
            try linkSectionTwosTasks(in: course)
            let before: [String: String] = everything(under: root, leaving: [".trail"])
            let settingsBytes: Data = try Data(contentsOf: course.configFileURL)

            assertThePlanRefuses("Tasks", to: "Activities", scope: .perSection, in: course, place: "section2/Tasks")
            let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Activities", scope: .perSection)

            XCTAssertEqual(failed(result), refusalSentence(renaming: "Tasks", folder: "Tasks"), "\(mode)")
            XCTAssertEqual(everything(under: root, leaving: [".trail"]), before, "something changed, \(mode)")
            XCTAssertEqual(linkTarget(course, "section2/Tasks"), "../library/Tasks", "\(mode)")
            XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBytes, "\(mode)")
            XCTAssertEqual(course.configuration.perSectionFolders, ["All Classes", "Tasks"], "\(mode)")
            XCTAssertEqual(stepsOnTheList(), 0, "a step was made, \(mode)")
            let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "a rename record was left, \(mode)")
        }
    }

    /// The shared folder `Concepts` is a link leading OUT of the working
    /// folder: refused the same way, and the folder it leads to, the page
    /// inside it included, is byte for byte as it was. MUST FAIL with the
    /// link moved as a link (U4b2-15).
    func testASharedFolderThatIsALinkOutOfTheWorkingFolderIsRefusedAndWhatItLeadsToIsUntouched() async throws {
        let course: Course = try course()
        let outside: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-rename-outside-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("See [[Concepts/Loops]].\n".utf8).write(to: outside.appendingPathComponent("Loops.md"))
        let concepts: URL = course.directoryURL.appendingPathComponent("Concepts")
        try FileManager.default.removeItem(at: concepts)
        try FileManager.default.createSymbolicLink(atPath: concepts.path, withDestinationPath: outside.path)
        let before: [String: String] = everything(under: root, leaving: [".trail"])
        let outsideBefore: [String: String] = everything(under: outside)
        let settingsBytes: Data = try Data(contentsOf: course.configFileURL)

        assertThePlanRefuses("Concepts", to: "Ideas", scope: .shared, in: course, place: "Concepts")
        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        XCTAssertEqual(failed(result), refusalSentence(renaming: "Concepts", folder: "Concepts"))
        XCTAssertEqual(everything(under: root, leaving: [".trail"]), before, "something changed")
        XCTAssertEqual(everything(under: outside), outsideBefore, "what the link leads to changed")
        XCTAssertEqual(linkTarget(course, "Concepts"), outside.path)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBytes)
        XCTAssertEqual(stepsOnTheList(), 0, "a step was made")
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "a rename record was left")
    }

    /// A per-section rename with no link plans the same moves and pages,
    /// and its step holds the same ops, as before #1055 (recorded from a
    /// run on the base, 839bbbce3). MUST FAIL with any plain folder's move
    /// changed by the revert.
    func testAPlainPerSectionRenameStillPlansTheSameMoves() async throws {
        let course: Course = try course()
        let prefix: String = UndoFolderPlaces.canonicalPath(of: course.directoryURL) + "/"
        let planned: FolderRenamePlan = try SpecialFolderRenamer.plan(
            "Tasks", to: "Assessments", scope: .perSection,
            courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        var plannedLines: [String] = []
        for move in planned.moves {
            let from: String = String(UndoFolderPlaces.canonicalPath(of: move.from).dropFirst(prefix.count))
            let to: String = String(UndoFolderPlaces.canonicalPath(of: move.to).dropFirst(prefix.count))
            plannedLines.append("move " + from + " -> " + to + " link " + String(move.isALink))
        }
        for page in planned.pages {
            let path: String = String(UndoFolderPlaces.canonicalPath(of: page.url).dropFirst(prefix.count))
            plannedLines.append("page " + path + " = " + (String(data: page.rewritten, encoding: .utf8) ?? "?"))
        }
        XCTAssertEqual(plannedLines, [
            "move section1/Tasks -> section1/Assessments link false",
            "move section2/Tasks -> section2/Assessments link false",
            "page section1/Assessments/Quiz 1.md = See [[Assessments/Quiz 2]].\n",
            "page section1/index.md = Start with [[Assessments/Quiz 1]].\n",
        ])

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        var opLines: [String] = []
        for op in try newestOps() {
            var line: String = op.kind
            if let from = op.from {
                line += " from " + from
            }
            if let to = op.to {
                line += " to " + to
            }
            if let path = op.path {
                line += " path " + path
            }
            if let keyPath = op.keyPath {
                line += " key " + keyPath.joined(separator: ".")
            }
            if let listingSha = op.listingSha {
                line += " listing " + listingSha
            }
            opLines.append(line)
        }
        XCTAssertEqual(opLines, [
            "move from courses/ICS3U/section1/Tasks to courses/ICS3U/section1/Assessments listing 23dc9b20edc443f6a84df5c3cee6945e26e2916d80cebb537b821091f00992df",
            "move from courses/ICS3U/section2/Tasks to courses/ICS3U/section2/Assessments listing 27442be4b0b580a302ae1aaa6ac7e86c4951d74290046c9c7a8d4b917446f15b",
            "writeFile path courses/ICS3U/section1/Assessments/Quiz 1.md",
            "writeFile path courses/ICS3U/section1/index.md",
            "editJSON path courses/ICS3U/course_config.json key expandable",
            "editJSON path courses/ICS3U/course_config.json key hidden",
            "editJSON path courses/ICS3U/course_config.json key per_section_folders",
        ])
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
    /// step is made and the rename's claim has ended. The rename runs from
    /// a sheet's `FolderRenameRun`, so the quit's halting of what only plans
    /// (U4b2-7) is proved to leave a swap that has begun alone. MUST FAIL
    /// with the rename left out of the quit's wait
    /// (`AppDelegate.waitForWorkUnderWay`, which `applicationShouldTerminate`
    /// awaits; part seven's review, L6).
    func testAQuitDuringARenameWaitsForItToFinish() async throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let reached: XCTestExpectation = XCTestExpectation(description: "the swap reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        addTeardownBlock {
            gate.open()
        }
        UndoKillPoints.beforeTheRename = { @Sendable (index: Int, place: URL) in
            gate.arrive()
        }
        let run: FolderRenameRun = FolderRenameRun()
        let finished: XCTestExpectation = XCTestExpectation(description: "the rename told its sheet")
        var told: RenameResult? = nil
        run.start(
            renaming: "Tasks", to: "Assessments", using: view.renameFromTheSheet(scope: .perSection),
            canNoLongerBeHalted: view.renameSwapHasBegun
        ) { result in
            told = result
            finished.fulfill()
        }
        await fulfillment(of: [reached], timeout: 30)

        XCTAssertTrue(
            AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans(), "the quit does not wait for the rename"
        )
        XCTAssertTrue(run.isRenaming, "the quit halted a rename whose swap had begun")
        let quit: Task<(Bool, Int), Never> = Task { @MainActor in
            // The quit's own wait, as `applicationShouldTerminate` runs it
            // (part seven's review, L6).
            await AppDelegate.waitForWorkUnderWay()
            let steps: Int = (try? self.journal().read().records.count) ?? -1
            return (CourseActivity.anyFolderRenameSwapIsUnderWay, steps)
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
        await fulfillment(of: [finished], timeout: 30)

        XCTAssertFalse(stillUnderWay, "the quit went on while the rename ran")
        XCTAssertEqual(steps, 1, "the quit went on before the step was made")
        let result: RenameResult = try XCTUnwrap(told)
        XCTAssertNotNil(renamed(result), "\(result)")
    }

    /// ⌘Q while a rename only plans (U4b part eight's review, L3; U4b2-7):
    /// the plan is held open at its first page on an event, as a dead
    /// volume would hold it. The quit halts the rename the way its sheet's
    /// Cancel does and does not wait at all; the rename then returns
    /// without the held read, its claim ended and nothing written: the
    /// course's folders, pages and settings as before, no step, no record.
    /// MUST FAIL with the quit counting a claim that is not yet swapping
    /// (it waits, as before), and with the quit not halting the run.
    func testAQuitWhileARenameOnlyPlansHaltsItAndDoesNotWait() async throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let foldersBefore: [String] = listed(course.directoryURL)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let reached: XCTestExpectation = XCTestExpectation(description: "the plan reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        addTeardownBlock {
            gate.open()
        }
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            gate.arrive()
        }
        let returned: XCTestExpectation = XCTestExpectation(description: "the rename returned")
        let sheetRename: (String, String) async -> RenameResult = view.renameFromTheSheet(scope: .perSection)
        let run: FolderRenameRun = FolderRenameRun()
        var told: Bool = false
        run.start(
            renaming: "Tasks", to: "Assessments",
            using: { oldName, newName in
                let result: RenameResult = await sheetRename(oldName, newName)
                returned.fulfill()
                return result
            },
            canNoLongerBeHalted: view.renameSwapHasBegun
        ) { result in
            told = true
        }
        await fulfillment(of: [reached], timeout: 30)
        XCTAssertTrue(course.isRenamingAFolder, "the claim is held while the plan walks")

        // The quit's own decision, as `applicationShouldTerminate` runs it.
        let waits: Bool = AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans()

        XCTAssertFalse(waits, "the quit waits for a rename that only plans")
        // The rename returning is the event; the bound only turns a halt
        // that did not reach the plan into a failure rather than a hang
        // (the hold is opened first, so the run ends either way).
        let waited: XCTWaiter.Result = await XCTWaiter().fulfillment(of: [returned], timeout: 30)
        if waited != .completed {
            gate.open()
            XCTFail("the quit did not halt the rename while it planned")
            await fulfillment(of: [returned], timeout: 30)
            return
        }
        let quit: XCTestExpectation = XCTestExpectation(description: "the quit's wait returned")
        Task { @MainActor in
            await AppDelegate.waitForWorkUnderWay()
            quit.fulfill()
        }
        await fulfillment(of: [quit], timeout: 30)
        // Its task ends on the main actor after the rename returns.
        var turns: Int = 0
        while run.isRenaming && turns < 10_000 {
            await Task.yield()
            turns += 1
        }

        XCTAssertFalse(run.isRenaming)
        XCTAssertFalse(told, "a halted rename told its sheet")
        XCTAssertFalse(course.isRenamingAFolder, "the claim was not ended")
        XCTAssertTrue(CourseActivity.store.activeFolderRenames.isEmpty)
        XCTAssertEqual(listed(course.directoryURL), foldersBefore)
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    /// A rename pressed while a quit waits (U4b2-7 review 1, M1 and L1):
    /// once the quit has gone ahead, no rename may start. The run refuses at
    /// once, claims nothing and writes nothing, and the sheet's Rename is
    /// disabled by the same `canStart`. MUST FAIL with `start` not asking
    /// whether a quit is going ahead.
    func testARenamePressedWhileAQuitWaitsDoesNotStart() async throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let foldersBefore: [String] = listed(course.directoryURL)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let run: FolderRenameRun = FolderRenameRun()
        XCTAssertTrue(run.canStart)

        // The quit's own decision; nothing is under way, so it would not
        // wait, but it is going ahead all the same.
        _ = AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans()

        XCTAssertFalse(run.canStart, "Rename stays enabled while a quit is going ahead")
        var told: Bool = false
        run.start(
            renaming: "Tasks", to: "Assessments", using: view.renameFromTheSheet(scope: .perSection),
            canNoLongerBeHalted: view.renameSwapHasBegun
        ) { result in
            told = true
        }
        let started: Bool = run.isRenaming
        // A run that did start is let finish, so the test ends on its own.
        if started {
            var turns: Int = 0
            while run.isRenaming && turns < 100_000 {
                await Task.yield()
                turns += 1
            }
        }

        XCTAssertFalse(started, "a rename started while a quit was going ahead")
        XCTAssertFalse(told)
        XCTAssertTrue(FolderRenameRun.runsUnderWay.isEmpty)
        XCTAssertEqual(listed(course.directoryURL), foldersBefore)
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
    }

    /// A plan that finishes while a quit waits (U4b2-7 review 1, M1): a
    /// rename the quit's halt did not reach (here one started outside any
    /// sheet's run, as a run registered after the decision would be) is
    /// held at its first page while the quit goes ahead, then let go. Its
    /// swap is refused at the one place it would begin, with nothing
    /// written and no record, so the quit, which waits only for swaps
    /// already begun, can never end the process inside one. MUST FAIL with
    /// `FolderRenameRun.swapBegins` not asking whether a quit is going
    /// ahead (the folders are renamed).
    func testAPlanThatFinishesWhileAQuitWaitsNeverBeginsItsSwap() async throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let foldersBefore: [String] = listed(course.directoryURL)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let reached: XCTestExpectation = XCTestExpectation(description: "the plan reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        addTeardownBlock {
            gate.open()
        }
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            gate.arrive()
        }
        let renaming: Task<RenameResult, Never> = Task { @MainActor in
            return await view.renameFolder("Tasks", to: "Assessments", scope: .perSection)
        }
        await fulfillment(of: [reached], timeout: 30)

        XCTAssertFalse(
            AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans(), "the quit waits for a rename that only plans"
        )
        gate.open()
        let result: RenameResult = await renaming.value

        XCTAssertNotNil(failed(result), "a swap began while a quit was going ahead: \(result)")
        XCTAssertFalse(CourseActivity.anyFolderRenameSwapIsUnderWay)
        XCTAssertFalse(course.isRenamingAFolder, "the claim was not ended")
        XCTAssertEqual(listed(course.directoryURL), foldersBefore)
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    /// The sheet's three calls into `FolderRenameRun` (U4b2-7 review 1, L2),
    /// read off the source because a view's `@State` cannot be driven from a
    /// unit test: Cancel halts through the run, the sheet going away halts
    /// through the run, Rename starts the run with the closure it was
    /// handed, and Rename is enabled by the run's `canStart`. MUST FAIL with
    /// any one of those calls taken out of the view. Backed since U4b2-8 by
    /// the real sheet, hosted and pressed
    /// (`testTheRealSheetsCancelHaltsAHeldPlanAndClosesTheSheet`,
    /// `testTheRealSheetGoingAwayHaltsAHeldPlan`), which catch a halt
    /// commented out or moved into a fresh `Task`.
    func testTheRenameSheetCallsItsRunForEveryWayOut() throws {
        let sourceURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers/Views/CourseSettings/StringListEditorView.swift")
        let source: String = try String(contentsOf: sourceURL, encoding: .utf8)

        let cancel: String = UndoRenameFolderStepTests.body(of: "func cancelRename()", in: source)
        XCTAssertTrue(cancel.contains("if renameRun.haltIfStillPlanning() {"), "Cancel does not halt through the run")
        XCTAssertTrue(cancel.contains("pendingRename = nil"), "Cancel does not close the sheet")
        let halt: String = UndoRenameFolderStepTests.body(of: "func haltARenameStillPlanning()", in: source)
        XCTAssertTrue(halt.contains("renameRun.haltIfStillPlanning()"), "the sheet going away does not halt through the run")
        XCTAssertTrue(
            source.contains(".onDisappear {\n                    haltARenameStillPlanning()\n                }"),
            "the rename sheet going away does not halt its rename"
        )
        let start: String = UndoRenameFolderStepTests.body(of: "func startRename(of item: String, finishing: Bool)", in: source)
        XCTAssertTrue(start.contains("guard let onRename, renameRun.canStart else {"), "Rename starts without asking the run")
        XCTAssertTrue(start.contains("renameRun.start("), "Rename does not start the run")
        XCTAssertTrue(start.contains("using: onRename,"), "Rename hands the run something other than its closure")
        XCTAssertTrue(
            source.contains(".defaultButton(isEnabled: problem == nil && renameRun.canStart)"),
            "Rename is not disabled by the run's canStart"
        )
        XCTAssertTrue(source.contains(".disabled(cancelIsDisabled)"))
        XCTAssertTrue(source.contains("let cancelIsDisabled: Bool = !renameRun.canBeHalted"))
    }

    /// The real rename sheet, hosted off screen (U4b2-8, U4b2-7 review 2's
    /// LOW-a): its own Rename button, pressed through accessibility as
    /// VoiceOver presses it, starts the run with the closure the sheet was
    /// handed, the plan is held at its first page, and its own Cancel button
    /// halts the rename at once and closes the sheet, with nothing written.
    /// Runs the view's real chain, so a halt commented out, moved into a
    /// fresh `Task`, or put on the wrong button fails here where a reading
    /// of the source would pass. MUST FAIL with Cancel not halting through
    /// the run.
    func testTheRealSheetsCancelHaltsAHeldPlanAndClosesTheSheet() throws {
        let course: Course = try course()
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let gate: RenameHold = holdThePlanAtItsFirstPage()
        let reached: XCTestExpectation = gate.reached
        let returned: XCTestExpectation = XCTestExpectation(description: "the rename returned")
        let run: FolderRenameRun = FolderRenameRun()
        let host: TableHost = hostTheRenameSheet(of: view, run: run, returned: returned)
        defer {
            host.close()
        }
        XCTAssertNotNil(host.window.attachedSheet, "the rename sheet did not open")
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)

        XCTAssertTrue(RenameSheetButtons.press("Rename", inWindowTitled: host.window.title), "the sheet has no Rename button to press")
        wait(for: [reached], timeout: 30)
        XCTAssertTrue(run.isRenaming, "the sheet's Rename did not start its run")
        XCTAssertTrue(course.isRenamingAFolder, "the claim is held while the plan walks")

        XCTAssertTrue(RenameSheetButtons.press("Cancel", inWindowTitled: host.window.title), "the sheet has no Cancel button to press")
        // The halt is in the button's own turn: the run's task is cancelled
        // before the press returns.
        XCTAssertNil(run.renameTask, "Cancel did not halt the rename in its own turn")
        let waited: XCTWaiter.Result = XCTWaiter().wait(for: [returned], timeout: 30)
        if waited != .completed {
            gate.open()
            XCTFail("the sheet's Cancel did not reach the held plan")
            return
        }
        host.pump(0.3)

        XCTAssertFalse(run.isRenaming)
        XCTAssertNil(host.window.attachedSheet, "Cancel did not close the sheet")
        XCTAssertFalse(course.isRenamingAFolder, "the course is still held after Cancel")
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
    }

    /// The real Course Settings page, its grouped `Form` and all, hosted off
    /// screen (U4b2-8 review 1, M1): its per-section folders row's rename
    /// pencil, the sheet's field and its Rename are used through
    /// accessibility, and the plan is held at its first page. Making the
    /// window much shorter, and scrolling the form to its top and its
    /// bottom, takes the row out of view, and the rename goes on: a lazily
    /// drawn row leaving the visible area is not the teacher leaving the
    /// rename. Leaving the page then halts it, with nothing written. MUST
    /// FAIL with the page's `.onDisappear` not halting, and with a list
    /// not handed the page's run. (A list's own `.onDisappear`, as the
    /// first round of this piece had it, did not fire here when the row
    /// left the visible area, measured 2026-11-26; the halt lives on the
    /// page so that it cannot, whatever a later macOS draws lazily.)
    func testTheRealSettingsPageShrunkOrScrolledKeepsARenameAndLeavingItHalts() throws {
        let course: Course = try course()
        let before: [String: Data] = pages(of: course)
        let gate: RenameHold = holdThePlanAtItsFirstPage()
        let shown: RenameSheetShown = RenameSheetShown()
        let size: NSSize = NSSize(width: 900, height: 1100)
        let window: NSWindow = OffScreenWindow(
            contentRect: NSRect(origin: TableHost.offScreenOrigin(for: size), size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "settings-page-\(UUID().uuidString)"
        SheetsHungOffScreenStayThere.install()
        window.contentView = NSHostingView(rootView: ShownWhile(shown: shown) {
            CourseSettingsView(course: course)
        })
        window.setFrameOrigin(TableHost.offScreenOrigin(for: size))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.close()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(window)

        XCTAssertTrue(
            RenameSheetButtons.press(identifiedAs: "rename-Tasks", inWindowTitled: window.title),
            "the per-section Tasks row has no one rename pencil to press"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertNotNil(window.attachedSheet, "the rename sheet did not open")
        XCTAssertTrue(RenameSheetButtons.type("Assessments", intoFieldIdentifiedAs: "renameField", inWindowTitled: window.title))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(RenameSheetButtons.press("Rename", inWindowTitled: window.title), "the sheet has no Rename button to press")
        wait(for: [gate.reached], timeout: 30)
        XCTAssertTrue(course.isRenamingAFolder, "the claim is held while the plan walks")

        // Much shorter: the Content Structure rows leave the visible area.
        window.setContentSize(NSSize(width: 900, height: 220))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(RenameSheetButtons.isInView("rename-Tasks", of: window), "the row is still in view in the shorter window")
        XCTAssertTrue(course.isRenamingAFolder, "making the window shorter halted the rename")
        XCTAssertNotNil(window.attachedSheet, "making the window shorter closed the sheet")
        // Scrolled to the top and to the bottom of the form.
        let scrolled: Int = RenameSheetButtons.scrollEveryScrollView(in: window, toTop: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        _ = RenameSheetButtons.scrollEveryScrollView(in: window, toTop: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertGreaterThan(scrolled, 0, "the page has no scroll view to scroll")
        XCTAssertFalse(RenameSheetButtons.isInView("rename-Tasks", of: window), "the row is still in view after scrolling")
        XCTAssertTrue(course.isRenamingAFolder, "scrolling the form halted the rename")

        // Leaving the page (as choosing Planning, or another course, does).
        shown.isShown = false
        let given: XCTNSPredicateExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { (object: Any?, bindings: [String: Any]?) -> Bool in
                return MainActor.assumeIsolated {
                    return !course.isRenamingAFolder
                }
            }, object: nil
        )
        let waited: XCTWaiter.Result = XCTWaiter().wait(for: [given], timeout: 30)
        XCTAssertEqual(waited, .completed, "leaving the page did not halt the rename while it planned")
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try journal().read().records.count, 0)
        XCTAssertEqual(gate.arrivedCount, 1)
    }

    /// Holds the plan at its first page until the test ends, and at the
    /// end lets it go and waits for its walk to end before `tearDown`
    /// clears the hooks the walk reads (U4b2-8 review 1, L5).
    func holdThePlanAtItsFirstPage() -> RenameHold {
        let reached: XCTestExpectation = XCTestExpectation(description: "the plan reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        let ended: XCTestExpectation = XCTestExpectation(description: "the held plan's walk ended")
        ended.assertForOverFulfill = false
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            gate.arrive()
        }
        SpecialFolderRenamer.planHasEnded = { @Sendable in
            ended.fulfill()
        }
        addTeardownBlock { @MainActor in
            gate.open()
            if gate.arrivedCount > 0 {
                await self.fulfillment(of: [ended], timeout: 30)
            }
        }
        return gate
    }

    /// The per-section folders list as Course Settings builds it, with its
    /// rename sheet already open on Tasks and Assessments typed, hosted off
    /// screen. Its rename is the sheet's own closure, wrapped only to say
    /// when it returned.
    func hostTheRenameSheet(of view: CourseSettingsView, run: FolderRenameRun, returned: XCTestExpectation) -> TableHost {
        let configuration: CourseConfiguration = view.course.configuration
        let sheetRename: (String, String) async -> RenameResult = view.renameFromTheSheet(scope: .perSection)
        let editor: StringListEditorView = StringListEditorView(
            title: "Per-section folders",
            removalTrail: view.removalTrail(for: .perSectionFolders),
            items: Binding(
                get: { return configuration.perSectionFolders },
                set: { newValue in configuration.perSectionFolders = newValue }
            ),
            onRename: { oldName, newName in
                let result: RenameResult = await sheetRename(oldName, newName)
                returned.fulfill()
                return result
            },
            renameCanNoLongerBeHalted: view.renameSwapHasBegun,
            pendingRename: PendingRename(item: "Tasks", interruptedRenameTarget: nil),
            proposedName: "Assessments",
            renameRun: run
        )
        SheetsHungOffScreenStayThere.install()
        let host: TableHost = TableHost(editor)
        host.window.title = "rename-sheet-\(UUID().uuidString)"
        host.pump(0.6)
        return host
    }

    /// A second quit request while a quit is going ahead (U4b2-8, U4b2-7
    /// review 2's LOW-b). AppKit can ask again during a `.terminateLater`
    /// wait (it runs the run loop in the modal panel mode, which takes a
    /// second ⌘Q or a log out), so the request is answered `.terminateLater`
    /// before anything is asked: never the work-under-way question again,
    /// and never `.terminateCancel` with the latch set. Before any quit has
    /// gone ahead, a request is answered as always. The delegate asks this
    /// first, before the question (its first statement, comments aside).
    /// MUST FAIL with the answer ignoring the latch, and with the delegate
    /// not asking it first.
    func testASecondQuitRequestWhileAQuitGoesAheadAsksNothingAndRefusesNothing() throws {
        XCTAssertNil(AppDelegate.answerWhileAQuitGoesAhead(), "a first quit request is answered early")

        _ = AppDelegate.quitWaitsAfterHaltingWhatOnlyPlans()

        XCTAssertEqual(
            AppDelegate.answerWhileAQuitGoesAhead(), .terminateLater,
            "a second quit request while a quit goes ahead would be asked again, and could be refused"
        )
        let sourceURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers/App/AppDelegate.swift")
        let source: String = try String(contentsOf: sourceURL, encoding: .utf8)
        let statements: [String] = UndoRenameFolderStepTests.codeLines(
            after: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {", in: source
        )
        XCTAssertGreaterThan(statements.count, 2)
        if statements.count > 2 {
            XCTAssertEqual(statements[0], "return MainActor.assumeIsolated {")
            XCTAssertEqual(
                statements[1], "if let answer = AppDelegate.answerWhileAQuitGoesAhead() {",
                "the delegate does not ask about a quit already going ahead first"
            )
            XCTAssertEqual(statements[2], "return answer")
        }
    }

    /// The lines of code after `signature`, trimmed, with blank lines and
    /// comment lines left out, so a line commented out does not count.
    static func codeLines(after signature: String, in source: String) -> [String] {
        guard let start = source.range(of: signature) else {
            XCTFail("no \(signature) in the source")
            return []
        }
        var lines: [String] = []
        for line in source[start.upperBound...].split(separator: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") {
                continue
            }
            lines.append(trimmed)
            if lines.count == 10 {
                break
            }
        }
        return lines
    }

    /// The text of a function, from its signature to the next function or
    /// section in the same type.
    static func body(of signature: String, in source: String) -> String {
        guard let start = source.range(of: signature) else {
            XCTFail("no \(signature) in the source")
            return ""
        }
        let rest: Substring = source[start.upperBound...]
        var end: String.Index = rest.endIndex
        for marker in ["\n    func ", "\n    // MARK: -", "\n    @ViewBuilder"] {
            if let found = rest.range(of: marker), found.lowerBound < end {
                end = found.lowerBound
            }
        }
        return String(rest[..<end])
    }

    /// The sheet's Cancel reaches the plan (U4b part eight's review, L1;
    /// U4b2-7): driven from the sheet's own run and the very closure the
    /// sheet is handed (`renameFromTheSheet`), with the plan held open at
    /// its first page. Cancel (`haltIfStillPlanning`, which the sheet's
    /// Cancel, its going away and a quit all call) gives the course back
    /// at once, says nothing to the sheet, and writes nothing. MUST FAIL
    /// with the halt not cancelling the run's task, and with `onRename`
    /// awaited in a fresh `Task` (in the run or in `renameFromTheSheet`).
    func testTheSheetsCancelReachesAHeldPlan() async throws {
        let course: Course = try course()
        // An edit not yet saved, so Save has something to be enabled for.
        course.configuration.courseName = "Computer Science"
        let view: CourseSettingsView = CourseSettingsView(course: course)
        let before: [String: Data] = pages(of: course)
        let settingsBefore: Data = try Data(contentsOf: course.configFileURL)
        let reached: XCTestExpectation = XCTestExpectation(description: "the plan reached its first page")
        let gate: RenameHold = RenameHold(reached: reached)
        addTeardownBlock {
            gate.open()
        }
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            gate.arrive()
        }
        let returned: XCTestExpectation = XCTestExpectation(description: "the rename returned")
        let sheetRename: (String, String) async -> RenameResult = view.renameFromTheSheet(scope: .perSection)
        let run: FolderRenameRun = FolderRenameRun()
        var told: Bool = false
        run.start(
            renaming: "Tasks", to: "Assessments",
            using: { oldName, newName in
                let result: RenameResult = await sheetRename(oldName, newName)
                returned.fulfill()
                return result
            },
            canNoLongerBeHalted: view.renameSwapHasBegun
        ) { result in
            told = true
        }
        await fulfillment(of: [reached], timeout: 30)
        XCTAssertTrue(course.isRenamingAFolder, "the claim is held while the plan walks")
        XCTAssertTrue(run.canBeHalted, "Cancel is disabled while the rename only plans")

        XCTAssertTrue(run.haltIfStillPlanning(), "Cancel refused to halt a rename that only plans")
        let waited: XCTWaiter.Result = await XCTWaiter().fulfillment(of: [returned], timeout: 30)
        if waited != .completed {
            gate.open()
            XCTFail("the sheet's Cancel did not reach the held plan")
            await fulfillment(of: [returned], timeout: 30)
            return
        }
        var turns: Int = 0
        while run.isRenaming && turns < 10_000 {
            await Task.yield()
            turns += 1
        }

        XCTAssertFalse(run.isRenaming)
        XCTAssertFalse(told, "a halted rename told its sheet")
        XCTAssertFalse(course.isRenamingAFolder, "the course is still held after Cancel")
        XCTAssertTrue(view.saveIsEnabled, "Save is not enabled after Cancel")
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try Data(contentsOf: course.configFileURL), settingsBefore)
        XCTAssertEqual(try journal().read().records.count, 0)
        let record: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
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
        // rather than hanging the run. It ends there: a rename that waited
        // planned outside `planHaltingAtCancel`, so `planHasEnded` is never
        // called and the wait for `ended` below would never return (measured
        // 2026-11-25: with the plan awaited as a detached task's `value`, the
        // run failed here and then hung at that wait).
        let waited: XCTWaiter.Result = await XCTWaiter().fulfillment(of: [returned], timeout: 30)
        if waited != .completed {
            gate.open()
            XCTFail("the rename waited for the held plan after Cancel")
            _ = await halted.value
            return
        }
        let result: RenameResult = await halted.value

        XCTAssertNotNil(failed(result), "\(result)")
        XCTAssertFalse(course.isRenamingAFolder, "the course is still held after Cancel")
        XCTAssertTrue(CourseActivity.store.activeFolderRenames.isEmpty, "the cancelled plan's claim is still held")
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

    /// Rename-then-Cancel, again and again, on a dead volume (U4b2-8, part
    /// eight's L2): each round's plan is held at its first page on an event,
    /// as a read stuck inside the system would hold it, and is cancelled
    /// there. There are four more rounds than this Mac has cores, so more
    /// than the threads Swift's shared pool has. Each round's plan still
    /// starts, and with every one of them stuck an unrelated `Task` still
    /// runs at once: the stuck reads hold none of the pool. MUST FAIL with
    /// the walk run in a detached task.
    ///
    /// Synchronous on purpose: its waits spin the main run loop and need no
    /// thread of the pool, so a starved pool fails the test on its bounds
    /// rather than hanging it (measured 2026-11-26: written `async`, with
    /// the walk detached, the run hung in XCTest's async wait with all
    /// twelve of the pool's threads held in the plans).
    func testRenameThenCancelOnADeadVolumeLeavesTheSharedThreadsFree() throws {
        let course: Course = try course()
        let before: [String: Data] = pages(of: course)
        let cores: Int = ProcessInfo.processInfo.activeProcessorCount
        let rounds: Int = cores + 4
        let gate: EveryPlanHold = EveryPlanHold()
        addTeardownBlock {
            gate.open()
        }
        SpecialFolderRenamer.planReadsAPage = { @Sendable (page: URL) in
            gate.arrive()
        }
        let ended: XCTestExpectation = XCTestExpectation(description: "every held plan stopped once let go")
        ended.expectedFulfillmentCount = rounds
        SpecialFolderRenamer.planHasEnded = { @Sendable in
            ended.fulfill()
        }
        let threadsBefore: Int = ThreadCount.inThisProcess()

        var roundsHeld: Int = 0
        while roundsHeld < rounds {
            let round: Int = roundsHeld + 1
            let reached: XCTestExpectation = XCTestExpectation(description: "round \(round)'s plan reached its first page")
            gate.nextArrival(fulfils: reached)
            let returned: XCTestExpectation = XCTestExpectation(description: "round \(round)'s rename returned")
            let renaming: Task<Void, Never> = Task { @MainActor in
                let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
                XCTAssertNotNil(self.failed(result), "\(result)")
                returned.fulfill()
            }
            // The event is the plan reaching its first page; the bound only
            // turns a plan that never started into a failure, not a hang.
            let started: XCTWaiter.Result = XCTWaiter().wait(for: [reached], timeout: 30)
            renaming.cancel()
            let came: XCTWaiter.Result = XCTWaiter().wait(for: [returned], timeout: 30)
            XCTAssertEqual(came, .completed, "round \(round)'s rename did not return after Cancel")
            XCTAssertFalse(course.isRenamingAFolder, "round \(round) still holds the course after Cancel")
            if started != .completed {
                XCTFail("round \(round)'s plan never started, with \(roundsHeld) held on a Mac of \(cores) cores: the stuck reads hold the shared threads")
                break
            }
            roundsHeld += 1
        }
        let threadsHeld: Int = ThreadCount.inThisProcess()

        let unrelated: XCTestExpectation = XCTestExpectation(description: "an unrelated task ran")
        Task.detached {
            unrelated.fulfill()
        }
        // A free pool runs it at once; the bound turns a starved pool into a
        // failure rather than a hang.
        let ran: XCTWaiter.Result = XCTWaiter().wait(for: [unrelated], timeout: 10)
        XCTAssertEqual(ran, .completed, "an unrelated task did not run while \(roundsHeld) plans were held")

        gate.open()
        if roundsHeld == rounds {
            wait(for: [ended], timeout: 30)
            XCTAssertEqual(gate.arrivals, rounds, "a cancelled plan went on reading pages")
        }
        let threadsAfter: Int = ThreadCount.inThisProcess()
        print("U4b2-8 threads: cores \(cores), rounds \(rounds), before \(threadsBefore), with \(roundsHeld) plans held \(threadsHeld), after they were let go \(threadsAfter)")
        XCTAssertEqual(pages(of: course), before)
        XCTAssertEqual(try journal().read().records.count, 0)
        XCTAssertTrue(CourseActivity.store.activeFolderRenames.isEmpty)
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
        XCTAssertTrue(CourseActivity.store.activeFolderRenames.isEmpty)
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

    // MARK: - The final sweep (M1, L4)

    /// The activity trail as written so far.
    func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    /// A rename stopped part way with a folder left at its new name writes
    /// one `folder renamed` line saying so, naming the folder at its new
    /// name and how many files were kept beside their pages, never a page's
    /// name (the final sweep, M1). MUST FAIL with no line on that return.
    func testARenameLeftRenamedOnlyInPartWritesATrailLine() async throws {
        let course: Course = try course()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 0 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(failed(result), "\(result)")
        let expected: String = SpecialFolderRenamer.renamedOnlyInPartLine(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection,
            places: ["section1/Assessments"], keptBeside: 0
        )
        XCTAssertTrue(trail().contains(expected), trail())
        XCTAssertFalse(trail().contains("Quiz"), "a page's name is on the trail")
    }

    /// A rename stopped part way with every folder put back but a page's
    /// original kept beside it writes one `folder renamed` line saying the
    /// folder was not renamed and how many files were kept (the final
    /// sweep, M1). MUST FAIL with no line on that return.
    func testARenameStoppedPartWayWithItsFoldersPutBackWritesATrailLine() async throws {
        let course: Course = try course()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 2 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 1 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.stoppedPartWay(renaming: "Concepts", said: "")), said)
        let expected: String = SpecialFolderRenamer.stoppedPartWayLine(
            renaming: "Concepts", to: "Ideas", course: "ICS3U", scope: .shared, keptBeside: 1
        )
        XCTAssertTrue(trail().contains(expected), trail())
        XCTAssertFalse(trail().contains("Arrays"), "a page's name is on the trail")
    }

    /// A course left with its folder moved and its settings not, by a
    /// rename killed with the switch off: what `testWithTheSwitchOffARenameKilledPartWayIsFinishedFromItsRecord`
    /// starts from.
    func courseWithAnInterruptedRename() async throws -> Course {
        JournaledStep.modeOverride = .shadow
        let course: Course = try course()
        UndoKillPoints.hook = { reached in reached == .beforeSwap(1) }
        _ = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)
        UndoKillPoints.hook = nil
        try recoverInShadow()
        let target: String? = SpecialFolderRenamer.interruptedRenameTarget(
            from: "Concepts", scope: .shared, courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertEqual(target, "Ideas", "the kill did not leave an interrupted rename")
        return course
    }

    /// A refused attempt to FINISH an interrupted rename leaves the earlier
    /// run's record, so the sheet still offers the name to finish with (the
    /// final sweep, L4): this run moved no folder and wrote no record.
    /// MUST FAIL with every refusal clearing the record.
    func testARefusedFinishOfAnInterruptedRenameKeepsItsRecord() async throws {
        let course: Course = try await courseWithAnInterruptedRename()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 0 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.nothingWasChanged(renaming: "Concepts", said: "")), said)
        let target: String? = SpecialFolderRenamer.interruptedRenameTarget(
            from: "Concepts", scope: .shared, courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertEqual(target, "Ideas", "the refusal cleared the earlier run's record")
    }

    /// The same when the finish is refused as changed since on every try,
    /// planned again each time and then given up (the final sweep, L4): the
    /// retry's clearing reaches only a record this run wrote. MUST FAIL with
    /// the retry clearing the record.
    func testAFinishRefusedAsChangedSinceOnEveryTryKeepsItsRecord() async throws {
        let course: Course = try await courseWithAnInterruptedRename()
        let page: URL = course.directoryURL.appendingPathComponent("Ideas/Arrays.md")
        UndoKillPoints.hook = { @Sendable (reached: UndoKillPoint) in
            if reached == .afterBegin {
                // Still naming the folder, so each re-plan relinks the page
                // again and each make finds it changed again.
                try? ("See [[Concepts/Loops]], changed " + UUID().uuidString + ".\n").write(
                    to: page, atomically: true, encoding: .utf8
                )
            }
            return false
        }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        XCTAssertNotNil(failed(result), "\(result)")
        let target: String? = SpecialFolderRenamer.interruptedRenameTarget(
            from: "Concepts", scope: .shared, courseDirectory: course.directoryURL, sectionNumbers: [1, 2]
        )
        XCTAssertEqual(target, "Ideas", "a refused retry cleared the earlier run's record")
    }

    // MARK: - U4b2-5: a finish run's part-way line names the folders as the disk has them

    /// A run FINISHING an interrupted rename moves no folder (the earlier
    /// run did), so a part-way ending must read the disk for the folders at
    /// the new name: "Ideas" is there, so the trail line and the sentence say
    /// the rename stopped only in part, never that the folder was not
    /// renamed (part nine's review, L1). The swap fails at the settings
    /// and the page's put-back fails, so its original is kept beside it.
    /// MUST FAIL with the folders taken from this run's planned moves.
    func testAFinishStoppedPartWaySaysTheFolderIsAtItsNewName() async throws {
        let course: Course = try await courseWithAnInterruptedRename()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 0 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Concepts", to: "Ideas", scope: .shared)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent("Ideas").path))
        let expectedSentence: String = SpecialFolderRenamer.renamedOnlyInPart(
            renaming: "Concepts", to: "Ideas", places: ["Ideas"], said: ""
        )
        XCTAssertTrue(said.hasPrefix(expectedSentence), said)
        let expectedLine: String = SpecialFolderRenamer.renamedOnlyInPartLine(
            renaming: "Concepts", to: "Ideas", course: "ICS3U", scope: .shared,
            places: ["Ideas"], keptBeside: 1
        )
        XCTAssertTrue(trail().contains(expectedLine), trail())
        XCTAssertFalse(trail().contains("did not rename the folder Concepts"), trail())
        var linesForThisEnding: Int = 0
        for line in trail().components(separatedBy: "\n") {
            if line.contains("the folder Concepts to Ideas") && line.contains("could not put everything back") {
                linesForThisEnding += 1
            }
        }
        XCTAssertEqual(linesForThisEnding, 1, trail())
    }

    /// A course with a per-section rename of Tasks to Assessments killed at
    /// the first swap once `movedFolder` is at its new name, with the switch
    /// off: the folders moved by then stay moved, the settings do not know,
    /// and the record names the rename and every place it moves. Keyed on
    /// the disk, not on a swap's index (the step orders its swaps by path).
    /// Section 2's page links into the folder, so a relink inside section 2
    /// is swapped after section 2's move.
    func courseWithAKilledRename(killedOnce movedFolder: String) async throws -> Course {
        JournaledStep.modeOverride = .shadow
        let course: Course = try course()
        try "See [[Tasks/Quiz 1]].\n".write(
            to: course.directoryURL.appendingPathComponent("section2/Tasks/Quiz 2.md"), atomically: true, encoding: .utf8
        )
        let moved: URL = course.directoryURL.appendingPathComponent(movedFolder)
        UndoKillPoints.hook = { @Sendable (reached: UndoKillPoint) in
            if case .beforeSwap = reached {
                return FileManager.default.fileExists(atPath: moved.path)
            }
            return false
        }
        _ = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)
        UndoKillPoints.hook = nil
        try recoverInShadow()
        return course
    }

    /// The review's scenario (review 1 of U4b2-5, M1): a per-section start
    /// run where one section already holds a folder at the new name, made by
    /// hand and never this rename's. Every folder is moved back, a page's
    /// original is kept: the line and the sheet say "did not rename" and
    /// never name the hand-made folder. MUST FAIL with every place at the new
    /// name counted, whether this rename's or not.
    func testAStopWithEveryFolderBackNeverNamesAFolderThatWasAlwaysAtTheNewName() async throws {
        let course: Course = try course()
        let section2: URL = course.directoryURL.appendingPathComponent("section2")
        try FileManager.default.moveItem(
            at: section2.appendingPathComponent("Tasks"), to: section2.appendingPathComponent("Assessments")
        )
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 2 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 1 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.stoppedPartWay(renaming: "Tasks", said: "")), said)
        XCTAssertFalse(said.contains("section2/Assessments"), said)
        let expected: String = SpecialFolderRenamer.stoppedPartWayLine(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection, keptBeside: 1
        )
        XCTAssertTrue(trail().contains(expected), trail())
        XCTAssertFalse(trail().contains("section2/Assessments"), trail())
    }

    /// A per-section FINISH run (review 1, L1 a): the earlier run moved both
    /// sections, this run moves none, and its part-way ending names both
    /// places, in section order, inside the course. MUST FAIL with the
    /// recorded places not read.
    func testAPerSectionFinishStoppedPartWayNamesEverySectionAtTheNewName() async throws {
        let course: Course = try await courseWithAKilledRename(killedOnce: "section2/Assessments")
        // This run moves nothing: its first swap is made, its second
        // refused, and the first's put-back fails, so one original is kept.
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index >= 1 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 0 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        let said: String = try XCTUnwrap(failed(result), "\(result)")
        let places: [String] = ["section1/Assessments", "section2/Assessments"]
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.renamedOnlyInPart(
            renaming: "Tasks", to: "Assessments", places: places, said: ""
        )), said)
        let expected: String = SpecialFolderRenamer.renamedOnlyInPartLine(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection,
            places: places, keptBeside: 1
        )
        XCTAssertTrue(trail().contains(expected), trail())
    }

    /// A start run after a killed one (review 1, L1 b): the earlier run moved
    /// section 1, this run moves section 2 and cannot move it back. Both are
    /// this rename's and both are named; only this run's was before. MUST
    /// FAIL with the earlier run's places left out of the reading or of the
    /// record this run writes.
    func testAStartRunAfterAKilledOneNamesTheSectionsBothRunsMoved() async throws {
        let course: Course = try await courseWithAKilledRename(killedOnce: "section1/Assessments")
        // The first swap after section 2's move is refused, and something
        // appears at section 2's old name, so its move back is blocked (as
        // `testAMoveBackBlockedAtTheOldNameStillSaysWhichFolderIsRenamed`).
        let movedThisRun: URL = course.directoryURL.appendingPathComponent("section2/Assessments")
        let appeared: URL = course.directoryURL.appendingPathComponent("section2/Tasks/Other.md")
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in
            if !FileManager.default.fileExists(atPath: movedThisRun.path) {
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
        let places: [String] = ["section1/Assessments", "section2/Assessments"]
        XCTAssertTrue(said.hasPrefix(SpecialFolderRenamer.renamedOnlyInPart(
            renaming: "Tasks", to: "Assessments", places: places, said: ""
        )), said)
        let expected: String = SpecialFolderRenamer.renamedOnlyInPartLine(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection,
            places: places, keptBeside: 0
        )
        XCTAssertTrue(trail().contains(expected), trail())
        let record: Data? = recordOnDisk(of: course)
        XCTAssertEqual(
            SpecialFolderRenamer.placesMoved(byTheRecord: record, renaming: "Tasks", to: "Assessments", scope: .perSection),
            places, "the record this run wrote lost the earlier run's place"
        )
    }

    // MARK: - U4b2-3: another folder's record is never this rename's to clear

    /// Another folder's interrupted rename, as a run killed part way leaves
    /// it: its record's bytes, for comparing after.
    func recordAnotherFoldersInterruptedRename(in course: Course) throws -> Data {
        SpecialFolderRenamer.recordRenameStarting(
            from: "Concepts", to: "Ideas", scope: .shared, courseDirectory: course.directoryURL
        )
        return try Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL))
    }

    func recordOnDisk(of course: Course) -> Data? {
        return try? Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course.directoryURL))
    }

    /// A successful rename of another folder leaves the earlier record as it
    /// was (review 1 of U4b2-3, M1, scenario A). MUST FAIL with the success
    /// clearing the record unconditionally, or this run's record not put back.
    func testASuccessfulRenameOfAnotherFolderLeavesAnEarlierRecord() async throws {
        let course: Course = try course()
        let earlier: Data = try recordAnotherFoldersInterruptedRename(in: course)

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(recordOnDisk(of: course), earlier, "the earlier run's record was not left as it was")
    }

    /// A rename that moves no folder (a per-section folder no section has)
    /// writes no record and clears none (M1, scenario B).
    func testARenameThatMovesNothingLeavesAnEarlierRecord() async throws {
        let course: Course = try course()
        let earlier: Data = try recordAnotherFoldersInterruptedRename(in: course)

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("All Classes", to: "All Days", scope: .perSection)

        XCTAssertNotNil(renamed(result), "\(result)")
        XCTAssertEqual(recordOnDisk(of: course), earlier, "the earlier run's record was not left as it was")
    }

    /// A rename of another folder refused at its make, with nothing
    /// changed, puts the earlier record back.
    func testARefusedRenameOfAnotherFolderLeavesAnEarlierRecord() async throws {
        let course: Course = try course()
        let earlier: Data = try recordAnotherFoldersInterruptedRename(in: course)
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }

        let result: RenameResult = await CourseSettingsView(course: course).renameFolder("Tasks", to: "Assessments", scope: .perSection)

        XCTAssertNotNil(failed(result), "\(result)")
        XCTAssertEqual(recordOnDisk(of: course), earlier, "the earlier run's record was not left as it was")
    }

    /// Refused as changed since, planned again, and the re-plan refused:
    /// the earlier record is back, not cleared by the retry.
    func testARetryOfARenameOfAnotherFolderLeavesAnEarlierRecord() async throws {
        let course: Course = try course()
        let earlier: Data = try recordAnotherFoldersInterruptedRename(in: course)
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
        XCTAssertEqual(recordOnDisk(of: course), earlier, "the retry cleared the earlier run's record")
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

    var arrivals: Int = 0

    // MARK: - Computed properties

    /// How many pages the plan has begun to read, held or not.
    var arrivedCount: Int {
        condition.lock()
        let counted: Int = arrivals
        condition.unlock()
        return counted
    }

    // MARK: - Initializer

    init(reached: XCTestExpectation) {
        self.reached = reached
    }

    // MARK: - Functions

    func arrive() {
        condition.lock()
        arrivals += 1
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

/// Whether the hosted page, and so its rename sheet, is in the window.
@MainActor
@Observable
final class RenameSheetShown {

    // MARK: - Stored properties

    var isShown: Bool = true
}

/// The hosted page while `shown` says so, and nothing after (U4b2-8).
struct ShownWhile<Content: View>: View {

    // MARK: - Stored properties

    var shown: RenameSheetShown
    @ViewBuilder let content: () -> Content

    // MARK: - Body

    var body: some View {
        if shown.isShown {
            content()
        } else {
            Color.clear
        }
    }
}

/// Finds a button in a window by the name VoiceOver reads, and presses it
/// the way VoiceOver does (U4b2-8): through the accessibility API an
/// assistive app uses (`AccessibilityTree`), which is also what makes
/// SwiftUI build the tree at all (asked in process, it has no children).
@MainActor
enum RenameSheetButtons {

    // MARK: - Functions

    /// Presses the one button named `name` in the window titled
    /// `windowTitle`, sheet included. False when there is none.
    static func press(_ name: String, inWindowTitled windowTitle: String) -> Bool {
        var matching: [AXUIElement] = []
        for window in windows(titled: windowTitle) {
            collectButtons(named: name, under: window, into: &matching, depth: 0)
        }
        if matching.count != 1 {
            return false
        }
        return AXUIElementPerformAction(matching[0], kAXPressAction as CFString) == .success
    }

    /// Sets the text of the field identified as `identifier`, as an
    /// assistive app types into it.
    static func type(_ text: String, intoFieldIdentifiedAs identifier: String, inWindowTitled windowTitle: String) -> Bool {
        let matching: [AXUIElement] = elements(identifiedAs: identifier, inWindowTitled: windowTitle)
        if matching.count != 1 {
            return false
        }
        return AXUIElementSetAttributeValue(matching[0], kAXValueAttribute as CFString, text as CFString) == .success
    }

    /// Presses the one element identified as `identifier`.
    static func press(identifiedAs identifier: String, inWindowTitled windowTitle: String) -> Bool {
        let matching: [AXUIElement] = elements(identifiedAs: identifier, inWindowTitled: windowTitle)
        if matching.count != 1 {
            return false
        }
        return AXUIElementPerformAction(matching[0], kAXPressAction as CFString) == .success
    }

    static func elements(identifiedAs identifier: String, inWindowTitled windowTitle: String) -> [AXUIElement] {
        var matching: [AXUIElement] = []
        for window in windows(titled: windowTitle) {
            AccessibilityTree.collectElements(identifiedAs: identifier, under: window, into: &matching, depth: 0)
        }
        return matching
    }

    /// The windows whose title starts with `windowTitle`: a page may add a
    /// subtitle to its window's title (Course Settings names the course).
    static func windows(titled windowTitle: String) -> [AXUIElement] {
        let application: AXUIElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var found: [AXUIElement] = []
        for window in AccessibilityTree.elementList(of: application, attribute: kAXWindowsAttribute) {
            if AccessibilityTree.text(of: window, attribute: kAXTitleAttribute).hasPrefix(windowTitle) {
                found.append(window)
            }
        }
        return found
    }

    /// Whether the element identified as `identifier` is drawn inside the
    /// window's frame: false when it has been scrolled or shrunk out of
    /// view, or is not in the tree at all. Accessibility frames are in
    /// screen points from the top of the main display.
    static func isInView(_ identifier: String, of window: NSWindow) -> Bool {
        let mainDisplayHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0
        let windowFrame: CGRect = CGRect(
            x: window.frame.minX, y: mainDisplayHeight - window.frame.maxY,
            width: window.frame.width, height: window.frame.height
        )
        for element in elements(identifiedAs: identifier, inWindowTitled: window.title) {
            if AccessibilityTree.frame(of: element).intersects(windowFrame) {
                return true
            }
        }
        return false
    }

    /// Scrolls every scroll view in the window to its top or its bottom,
    /// and says how many there were.
    static func scrollEveryScrollView(in window: NSWindow, toTop: Bool) -> Int {
        var scrollViews: [NSScrollView] = []
        if let content = window.contentView {
            collectScrollViews(in: content, into: &scrollViews)
        }
        for scrollView in scrollViews {
            guard let document = scrollView.documentView else {
                continue
            }
            let visibleHeight: CGFloat = scrollView.contentView.bounds.height
            var y: CGFloat = 0
            let bottom: CGFloat = max(0, document.frame.height - visibleHeight)
            if document.isFlipped == toTop {
                y = 0
            } else {
                y = bottom
            }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        return scrollViews.count
    }

    static func collectScrollViews(in view: NSView, into found: inout [NSScrollView]) {
        if let scrollView = view as? NSScrollView {
            found.append(scrollView)
        }
        for subview in view.subviews {
            collectScrollViews(in: subview, into: &found)
        }
    }

    static func collectButtons(named name: String, under node: AXUIElement, into found: inout [AXUIElement], depth: Int) {
        if depth > 60 {
            return
        }
        if AccessibilityTree.text(of: node, attribute: kAXRoleAttribute) == kAXButtonRole {
            let title: String = AccessibilityTree.text(of: node, attribute: kAXTitleAttribute)
            let description: String = AccessibilityTree.text(of: node, attribute: kAXDescriptionAttribute)
            if title == name || description == name {
                found.append(node)
            }
        }
        for child in AccessibilityTree.elementList(of: node, attribute: kAXChildrenAttribute) {
            collectButtons(named: name, under: child, into: &found, depth: depth + 1)
        }
    }
}

/// Holds EVERY plan at its first page until the test opens it, as reads
/// stuck on a dead volume would hold them (U4b2-8). Each arrival fulfils
/// the expectation the test named for it, and is counted.
final class EveryPlanHold: @unchecked Sendable {

    // MARK: - Stored properties

    let condition: NSCondition = NSCondition()

    var waitingFor: XCTestExpectation? = nil

    var arrived: Int = 0

    var isOpen: Bool = false

    // MARK: - Computed properties

    var arrivals: Int {
        condition.lock()
        let counted: Int = arrived
        condition.unlock()
        return counted
    }

    // MARK: - Functions

    /// The expectation the next plan to arrive fulfils.
    func nextArrival(fulfils expectation: XCTestExpectation) {
        condition.lock()
        waitingFor = expectation
        condition.unlock()
    }

    func arrive() {
        condition.lock()
        arrived += 1
        let reached: XCTestExpectation? = waitingFor
        waitingFor = nil
        condition.unlock()
        reached?.fulfill()
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

/// How many threads this process has now, as the system counts them.
enum ThreadCount {

    // MARK: - Functions

    static func inThisProcess() -> Int {
        var info: proc_taskinfo = proc_taskinfo()
        let size: Int32 = Int32(MemoryLayout<proc_taskinfo>.size)
        let filled: Int32 = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, size)
        if filled != size {
            return -1
        }
        return Int(info.pti_threadnum)
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
