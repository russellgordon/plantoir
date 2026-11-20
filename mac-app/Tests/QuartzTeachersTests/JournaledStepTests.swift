import XCTest
@testable import QuartzTeachers

/// The door's step as an action makes it (#899, U3), on its own: what a
/// step does with a file another program changed between planning and
/// making it, what a step that cannot be named does when one of its files
/// cannot be written, and what a shadow swap made without the list leaves
/// after a kill. The first review of U3a, MEDIUM 2 and LOWs 3 and 8.
@MainActor
final class JournaledStepTests: XCTestCase {

    // MARK: - Stored properties

    var folders: [URL] = []

    var lockedFolders: [URL] = []

    // MARK: - Setting up

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        UndoKillPoints.beforeTheRename = nil
        UndoKillPoints.putBackFailsAt = nil
        UndoKillPoints.fileInUseAtSwap = nil
        for folder in lockedFolders {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        lockedFolders = []
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
    }

    // MARK: - Helpers

    /// A course with two class pages and the list in a folder of its own.
    /// `inAWorkingFolder` false puts the course in a folder not called
    /// `courses`, so its step cannot be named and is written plainly.
    func course(inAWorkingFolder: Bool) throws -> (course: URL, day1: URL, day2: URL, list: URL) {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("journaled-step-\(UUID().uuidString)", isDirectory: true)
        folders.append(root)
        let course: URL = root
            .appendingPathComponent(inAWorkingFolder ? "courses" : "somewhere else", isDirectory: true)
            .appendingPathComponent("ICS3U", isDirectory: true)
        let classes: URL = course.appendingPathComponent("section1/All Classes", isDirectory: true)
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        let day1: URL = classes.appendingPathComponent("Unit 1, Day 1.md")
        let day2: URL = classes.appendingPathComponent("Unit 1, Day 2.md")
        try "---\ntitle: Unit 1, Day 1\npublish: false\n---\nOne.\n".write(to: day1, atomically: true, encoding: .utf8)
        try "---\ntitle: Unit 1, Day 2\npublish: false\n---\nTwo.\n".write(to: day2, atomically: true, encoding: .utf8)
        let list: URL = root.appendingPathComponent("list", isDirectory: true)
        UndoJournalLocation.folderOverride = list
        return (course: course, day1: day1, day2: day2, list: list)
    }

    func step(for course: URL) -> JournaledStep {
        return JournaledStep(
            courseCode: "ICS3U", courseDirectory: course, section: 1, maker: UndoStepMaker.sheet("publishPages")
        )
    }

    func published(_ text: String) -> String {
        return text.replacingOccurrences(of: "publish: false", with: "publish: true")
    }

    /// Every staged name of the door's beside a file under the folder.
    func stagedNames(under folder: URL) -> [String] {
        var names: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else {
            return names
        }
        while let name = walker.nextObject() as? String {
            if name.contains(UndoSwap.stagedMarker) {
                names.append(name)
            }
        }
        return names
    }

    // MARK: - Tests: a file changed between planning and making

    /// A page an action planned, edited by another program (Obsidian)
    /// before the step is made: the step is refused, nothing of it is
    /// written, and the page is left as the other program wrote it. MUST
    /// FAIL with the step's before read at `make()` (U3a's first round),
    /// which took the edit in as the before and wrote over it.
    func testAFileEditedBetweenPlanAndMakeIsRefusedAndLeftAsTheOtherProgramWroteIt() throws {
        let made = try course(inAWorkingFolder: true)
        let step: JournaledStep = step(for: made.course)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        let edited: String = day2Text + "Written in Obsidian meanwhile.\n"
        try edited.write(to: made.day2, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.changedSince, let fileName) = error else {
                return XCTFail("not refused as changed since: \(error)")
            }
            XCTAssertEqual(fileName, "Unit 1, Day 2.md")
        }
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), edited, "the other program's edit was written over")
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), day1Text, "half the step was written")
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// A page that appears at a new page's place between planning and
    /// making (`ClassInsertionPlanner`'s plain `write` of a page that was
    /// not there): refused, and the page that appeared is kept. MUST FAIL
    /// with the before read at `make()`.
    func testAPageAppearingAtANewPagesPlaceIsRefused() throws {
        let made = try course(inAWorkingFolder: true)
        let step: JournaledStep = step(for: made.course)
        let newPage: URL = made.day2.deletingLastPathComponent().appendingPathComponent("Unit 1, Day 3.md")
        step.write("---\ntitle: Unit 1, Day 3\npublish: false\n---\n", to: newPage)
        let theirs: String = "---\ntitle: Unit 1, Day 3\n---\nThe teacher's own page.\n"
        try theirs.write(to: newPage, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.changedSince, _) = error else {
                return XCTFail("not refused as changed since: \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: newPage, encoding: .utf8), theirs)
    }

    /// The same for a step that cannot be named (written plainly): the
    /// edit is kept and nothing of the step is written.
    func testAStepWrittenPlainlyRefusesAFileEditedSincePlanning() throws {
        let made = try course(inAWorkingFolder: false)
        let step: JournaledStep = step(for: made.course)
        XCTAssertNil(step.workingFolderURL, "the course is in a working folder, so this proves nothing")
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        step.write(published(day1Text), to: made.day1)
        let edited: String = day1Text + "Written in Obsidian meanwhile.\n"
        try edited.write(to: made.day1, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try step.make())
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), edited)
    }

    // MARK: - Tests: a step that cannot be named is all or none

    /// A course outside a working folder, one of whose two files cannot be
    /// written: nothing is written, so "Nothing was changed" is true. MUST
    /// FAIL on U3a's first-round `writePlainly`, which wrote the first file
    /// and then stopped at the second.
    func testAStepWrittenPlainlyWritesAllOrNone() throws {
        let made = try course(inAWorkingFolder: false)
        let otherFolder: URL = made.course.appendingPathComponent("Concepts", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let notes: URL = otherFolder.appendingPathComponent("Notes.md")
        try "---\ntitle: Notes\npublish: false\n---\nNotes.\n".write(to: notes, atomically: true, encoding: .utf8)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let notesText: String = try String(contentsOf: notes, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(notesText), to: notes)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: otherFolder.path)
        lockedFolders.append(otherFolder)

        XCTAssertThrowsError(try step.make())
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), day1Text, "the first file was written alone")
        XCTAssertEqual(try String(contentsOf: notes, encoding: .utf8), notesText)
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// And when every file can be written, every file is, as before.
    func testAStepWrittenPlainlyWritesEveryFile() throws {
        let made = try course(inAWorkingFolder: false)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        try step.make()
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), published(day1Text))
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), published(day2Text))
        XCTAssertEqual(stagedNames(under: made.course), [])
        XCTAssertEqual(UndoShadowStaging.tidyLeftovers(of: UndoJournal(folderURL: made.list)), 0)
        let notes: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: made.list.appendingPathComponent(UndoShadowStaging.folderName).path
        )) ?? []
        XCTAssertEqual(notes, [], "a finished swap left its note")
    }

    // MARK: - Tests: a shadow swap without the list, killed part way

    /// A step written plainly, killed between its two swaps: the staged
    /// files are left beside the pages, as a process that died there leaves
    /// them. The next recovery, once that process is gone, removes the
    /// staged new content and writes nothing of the teacher's: the pages
    /// stay as the process left them. The first page's kept original is
    /// the only copy of what it held and stays beside it (the second review
    /// of U3a, MEDIUM c). MUST FAIL with `UndoShadowStaging.tidyLeftovers`
    /// taken out of recovery (U3a's first round never tidied a `shadow`
    /// swap's files), and with the kept original tidied away.
    func testAShadowSwapWithoutTheListKilledPartWayIsTidiedByTheNextRecovery() throws {
        let made = try course(inAWorkingFolder: false)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        UndoKillPoints.hook = { point in point == .beforeSwap(1) }
        XCTAssertThrowsError(try step.make()) { error in
            XCTAssertEqual(error as? JournaledStepError, .stoppedByATest)
        }
        UndoKillPoints.hook = nil
        XCTAssertFalse(stagedNames(under: made.course).isEmpty, "the kill left nothing staged, so this proves nothing")
        let leftByTheProcess: [String] = [
            try String(contentsOf: made.day1, encoding: .utf8), try String(contentsOf: made.day2, encoding: .utf8),
        ]

        // This process's own note is never tidied while it is running.
        XCTAssertEqual(UndoShadowStaging.tidyLeftovers(of: UndoJournal(folderURL: made.list)), 0)
        XCTAssertFalse(stagedNames(under: made.course).isEmpty)

        let later: UndoJournal = UndoJournal(folderURL: made.list, processIsAlive: { _ in false })
        try later.withLock(waitingAtMost: 2, inShadow: true) { writer in
            UndoRecovery.run(writer, mode: .shadow, trySwapsNow: true, resolveRoot: { _ in nil })
        }
        let left: [String] = stagedNames(under: made.course)
        XCTAssertEqual(left.count, 1, "the staged new content was left, or the original tidied away: \(left)")
        XCTAssertTrue((left.first ?? "").hasSuffix("-orig"), "\(left)")
        let keptURL: URL = made.course.appendingPathComponent(left.first ?? "?")
        XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), day1Text, "the kept original is not what the page held")
        XCTAssertEqual(
            [try String(contentsOf: made.day1, encoding: .utf8), try String(contentsOf: made.day2, encoding: .utf8)],
            leftByTheProcess, "recovery wrote into the course"
        )
        let notes: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: made.list.appendingPathComponent(UndoShadowStaging.folderName).path
        )) ?? []
        XCTAssertEqual(notes, [], "the dead process's note was kept")
    }

    // MARK: - Tests: the swap itself

    /// Another program edits a page IN PLACE between the swap's re-read and
    /// its rename (the Windows W2b review's finding, matched on the Mac):
    /// the edit lands in the inode the kept original links to. The original
    /// is read back after the rename, found changed, and put back over the
    /// new content, so the edit is kept whole; the swaps already made are
    /// reversed and the step is refused `changedSince`. Mirrors Windows'
    /// `UndoSwapTests.AnEditThatRacesTheSwapIsPutBackAndTheSwapRefused`.
    /// MUST FAIL on the swap before, which tidied the original, edit and
    /// all, away and left the page new.
    func testAnEditThatRacesTheSwapIsPutBackAndTheSwapRefused() throws {
        let made = try course(inAWorkingFolder: true)
        JournaledStep.modeOverride = .live
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        let added: String = "Written in Obsidian during the swap.\n"
        UndoKillPoints.beforeTheRename = { index, url in
            if index != 1 {
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(added.utf8))
            try? handle.close()
        }
        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.changedSince, let fileName) = error else {
                return XCTFail("not refused as changed since: \(error)")
            }
            XCTAssertEqual(fileName, "Unit 1, Day 2.md")
        }
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text + added, "the racing edit was lost")
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), day1Text, "the first swap was not reversed")
        XCTAssertEqual(stagedNames(under: made.course), [])
        XCTAssertEqual(try UndoJournal(folderURL: made.list).read().records[1]?.phase, .failed)
    }

    /// A reversal that cannot complete (the first page cannot be put back
    /// after the second is refused) leaves the step IN FLIGHT, never closed
    /// `failed`: the first page is new with its original beside it, and
    /// only recovery, once this process is gone, can settle that from the
    /// content (the Windows W3 review's finding, matched on the Mac; no new
    /// refusal word). It is refused PART WAY (`leftPartWay`, the second
    /// review of U3a, MEDIUM a), never as a plain refusal that says nothing
    /// was changed. Recovery then puts the page back and closes the step
    /// rolled back, with nothing staged left. MUST FAIL on the swap before,
    /// which ignored `reverse()` and closed the step `failed`, so recovery
    /// never looked at it and the page stayed new.
    func testAReversalThatCannotCompleteLeavesTheStepForRecovery() async throws {
        let made = try course(inAWorkingFolder: true)
        JournaledStep.modeOverride = .live
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        UndoKillPoints.fileInUseAtSwap = { index in index == 1 }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.leftPartWay(.fileIsInUse, _, _) = error else {
                return XCTFail("not refused part way, as in use: \(error)")
            }
        }
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
        JournaledStep.modeOverride = nil
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), published(day1Text), "the put-back did not fail, so this proves nothing")
        XCTAssertEqual(try UndoJournal(folderURL: made.list).read().records[1]?.phase, .begun, "the step was closed, not left for recovery")

        let root: URL = made.course.deletingLastPathComponent().deletingLastPathComponent()
        let later: UndoJournal = UndoJournal(folderURL: made.list, processIsAlive: { _ in false })
        await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in root })
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), day1Text, "recovery did not put the page back")
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text)
        XCTAssertEqual(stagedNames(under: made.course), [])
        XCTAssertEqual(try later.read().records[1]?.phase, .rolledBack)
    }

    // MARK: - Tests: a reversal that cannot complete, in SHADOW

    /// Every teacher today runs in shadow. A reversal that cannot complete
    /// there (the second review of U3a, MEDIUM): the step is refused PART
    /// WAY, naming the kept original; the first page holds the new content
    /// and its earlier content is kept beside it. At the next recovery, once
    /// this process is gone, shadow closes the step `interrupted`, removes
    /// the staged NEW content, and KEEPS the original, the only copy of what
    /// the page held. MUST FAIL with `tidyClosedSteps` tidying every staged
    /// name (the second round's code deleted the original).
    func testInShadowAReversalThatCannotCompleteKeepsTheOriginal() throws {
        let made = try course(inAWorkingFolder: true)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        UndoKillPoints.fileInUseAtSwap = { index in index == 1 }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        var kept: [String] = []
        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.leftPartWay(.fileIsInUse, _, let keptOriginals) = error else {
                return XCTFail("not refused part way: \(error)")
            }
            kept = keptOriginals
            XCTAssertTrue(error.localizedDescription.contains(keptOriginals.first ?? "?"), error.localizedDescription)
        }
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
        XCTAssertEqual(kept.count, 1)
        let keptURL: URL = made.day1.deletingLastPathComponent().appendingPathComponent(kept.first ?? "?")
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), published(day1Text))
        XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), day1Text)
        XCTAssertEqual(try UndoJournal(folderURL: made.list).read().records[1]?.phase, .begun)

        let root: URL = made.course.deletingLastPathComponent().deletingLastPathComponent()
        let later: UndoJournal = UndoJournal(folderURL: made.list, processIsAlive: { _ in false })
        try later.withLock(waitingAtMost: 2, inShadow: true) { writer in
            UndoRecovery.run(writer, mode: .shadow, trySwapsNow: true, resolveRoot: { _ in root })
        }
        XCTAssertEqual(try later.read().records[1]?.phase, .interrupted)
        XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), day1Text, "the only copy of the page's earlier content was tidied away")
        XCTAssertEqual(stagedNames(under: made.course).count, 1, "\(stagedNames(under: made.course))")
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), published(day1Text), "shadow recovery wrote into the course")
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text)
    }

    /// The same without the list (a step that cannot be named): the swap's
    /// note is KEPT (MEDIUM c), so once this process is gone the next tidy
    /// finds the staged new content and removes it, and keeps the original.
    /// MUST FAIL with the note dropped on `notPutBack` (the staged new
    /// content is then never found).
    func testInShadowWithoutTheListAReversalThatCannotCompleteKeepsItsNote() throws {
        let made = try course(inAWorkingFolder: false)
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write(published(day1Text), to: made.day1)
        step.write(published(day2Text), to: made.day2)
        UndoKillPoints.fileInUseAtSwap = { index in index == 1 }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        var kept: [String] = []
        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.leftPartWay(_, _, let keptOriginals) = error else {
                return XCTFail("not refused part way: \(error)")
            }
            kept = keptOriginals
        }
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
        XCTAssertEqual(stagedNames(under: made.course).count, 2, "the new content of the second page was not left staged")
        let removed: Int = UndoShadowStaging.tidyLeftovers(of: UndoJournal(folderURL: made.list, processIsAlive: { _ in false }))
        XCTAssertEqual(removed, 1)
        let keptURL: URL = made.day1.deletingLastPathComponent().appendingPathComponent(kept.first ?? "?")
        XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), day1Text, "the original was tidied away")
        XCTAssertEqual(stagedNames(under: made.course), ["section1/All Classes/" + (kept.first ?? "?")])
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text)
    }

    // MARK: - Tests: recovery and pruning keep what has not settled

    /// A live step killed between its swaps whose content the list no
    /// longer holds: recovery's first tidy, before it knows whether the
    /// step can be settled, leaves the kept original of the page that was
    /// swapped, the only copy of what it held (the Windows recovery
    /// review's 15). Seen at the kill point just after that tidy. What the
    /// closing does with it is the two `recoveryCases` rows on missing
    /// content. MUST FAIL with the first tidy removing every staged name,
    /// as before.
    func testRecoveryTidiesNoOnlyCopyBeforeItKnowsTheStepSettles() throws {
        let made = try course(inAWorkingFolder: true)
        JournaledStep.modeOverride = .live
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write("Rewritten whole.\n", to: made.day1)
        step.write("Rewritten whole too.\n", to: made.day2)
        UndoKillPoints.hook = { point in point == .beforeSwap(1) }
        XCTAssertThrowsError(try step.make())
        UndoKillPoints.hook = nil
        JournaledStep.modeOverride = nil
        XCTAssertEqual(try String(contentsOf: made.day1, encoding: .utf8), "Rewritten whole.\n")
        try FileManager.default.removeItem(at: made.list.appendingPathComponent("content", isDirectory: true))

        let root: URL = made.course.deletingLastPathComponent().deletingLastPathComponent()
        let later: UndoJournal = UndoJournal(folderURL: made.list, processIsAlive: { _ in false })
        UndoKillPoints.hook = { point in point == .afterRecoveryTidied }
        try later.withLock(waitingAtMost: 2, inShadow: false) { writer in
            UndoRecovery.run(writer, mode: .live, trySwapsNow: true, resolveRoot: { _ in root })
        }
        UndoKillPoints.hook = nil
        XCTAssertEqual(try later.read().records[1]?.phase, .begun, "recovery went past the tidy, so this proves nothing")
        var originals: [String] = []
        for name in stagedNames(under: made.course) where name.hasSuffix("-orig") {
            originals.append(name)
        }
        XCTAssertEqual(originals.count, 1, "\(stagedNames(under: made.course))")
        let keptURL: URL = made.course.appendingPathComponent(originals.first ?? "?")
        XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), day1Text)
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text)
    }

    /// Pruning never runs in a hold where recovery did not (the Windows
    /// recovery review's 14): a dead step past the limits would be closed
    /// `unsettled` and its original and content deleted, though recovery
    /// could still settle it. MUST FAIL without the guard in `prune`.
    func testPruningRefusesWithoutRecoveryInTheSameHold() throws {
        let made = try course(inAWorkingFolder: true)
        JournaledStep.modeOverride = .live
        let day1Text: String = try String(contentsOf: made.day1, encoding: .utf8)
        let first: JournaledStep = step(for: made.course)
        first.write(published(day1Text), to: made.day1)
        UndoKillPoints.hook = { point in point == .beforeSwap(0) }
        XCTAssertThrowsError(try first.make())
        UndoKillPoints.hook = nil
        let day2: URL = made.day2
        var text: String = try String(contentsOf: day2, encoding: .utf8)
        for count in 1...(UndoSwitch.stepsKept + 1) {
            let next: JournaledStep = step(for: made.course)
            text += "Line \(count).\n"
            next.write(text, to: day2)
            try next.make()
        }
        JournaledStep.modeOverride = nil
        let later: UndoJournal = UndoJournal(folderURL: made.list, processIsAlive: { _ in false })
        XCTAssertEqual(try later.read().records[1]?.phase, .begun)
        try later.withLock(waitingAtMost: 2, inShadow: false) { writer in
            UndoPruning.prune(writer, mode: .live, resolveRoot: { _ in nil })
        }
        XCTAssertEqual(try later.read().records[1]?.phase, .begun, "pruned without a recovery in the same hold")
    }
}
