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

    /// A dead process's note never removes what another swap staged beside
    /// the same page: every shadow swap has a label of its own (the second
    /// review of U3a, LOW 2; one label shared by every process let a dead
    /// note's tidy take a running swap's staged file). MUST FAIL with every
    /// swap labelled `shadow`.
    func testADeadProcesssNoteLeavesAnotherSwapsStagedFiles() throws {
        let made = try course(inAWorkingFolder: false)
        let journal: UndoJournal = UndoJournal(folderURL: made.list)
        let target: UndoSwapTarget = UndoSwapTarget(
            url: made.day1, relativePath: made.day1.lastPathComponent, expected: nil, replacement: Data("new".utf8)
        )
        let deadLabel: String = UndoShadowStaging.newLabel(for: journal)
        XCTAssertNotNil(UndoShadowStaging.writeNote(for: [target], label: deadLabel, in: journal))
        let runningLabel: String = UndoShadowStaging.newLabel(for: journal)
        let running: URL = UndoSwap.besideURL(for: made.day1, label: runningLabel, role: "new")
        try Data("staged by a swap still running".utf8).write(to: running)

        let removed: Int = UndoShadowStaging.tidyLeftovers(of: UndoJournal(folderURL: made.list, processIsAlive: { _ in false }))
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: running.path), "the dead note's tidy removed another swap's staged file")
    }

    // MARK: - Tests: a write after a link's move (U4b3)

    /// A class page that is a symbolic link to a file elsewhere in the
    /// course, its link moved to a new name in the same folder, made by
    /// `moveLink` as Rename folder makes a link's move.
    func linkedDay3(in made: (course: URL, day1: URL, day2: URL, list: URL), target relative: String) throws -> (link: URL, newName: URL, target: URL) {
        let elsewhere: URL = made.course.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let target: URL = elsewhere.appendingPathComponent("Unit 1, Day 3.md")
        try "---\ntitle: Unit 1, Day 3\npublish: false\n---\nThree.\n".write(to: target, atomically: true, encoding: .utf8)
        let link: URL = made.day1.deletingLastPathComponent().appendingPathComponent("Unit 1, Day 3.md")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: relative)
        let newName: URL = link.deletingLastPathComponent().appendingPathComponent("Unit 1, Day 4.md")
        return (link: link, newName: newName, target: target)
    }

    /// A write planned at a link move's `to`, within its folder, is planned
    /// at the file the link leads to: the step names that file and nothing
    /// inside the link's new place, the link arrives at its new name holding
    /// its target as written, and the file is written in place, the only
    /// copy. MUST FAIL without the one-place resolution in
    /// `placeALinkLeadsTo` (the write is planned at the link's new place).
    func testAWriteAtALinkMovesNewPlaceIsPlannedAtTheFileItLeadsTo() throws {
        let made = try course(inAWorkingFolder: true)
        let relative: String = "../../elsewhere/Unit 1, Day 3.md"
        let linked = try linkedDay3(in: made, target: relative)
        let step: JournaledStep = step(for: made.course)
        let sha: String = try XCTUnwrap(UndoTreeReading.linkSha(at: linked.link))
        step.moveLink(linked.link, to: linked.newName, linkSha: sha)
        let retitled: String = "---\ntitle: Unit 1, Day 4\npublish: false\n---\nThree.\n"
        step.write(retitled, to: linked.newName)

        var plannedPaths: [String] = []
        for key in step.plannedOrder {
            plannedPaths.append(key)
        }
        XCTAssertEqual(plannedPaths, [JournaledStep.key(of: linked.target)], "the write was not planned at the file the link leads to")
        XCTAssertNil(step.refusedBeforeMaking)
        try step.make()

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.newName.path), relative)
        XCTAssertFalse(FileManager.default.fileExists(atPath: linked.link.path))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: linked.link.path), "the link is still at its old name")
        XCTAssertEqual(try String(contentsOf: linked.target, encoding: .utf8), retitled)
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// A link moved to ANOTHER folder and then written through: no writer
    /// does it, and a relative target could lead elsewhere from there, so
    /// the step is refused "cannot tell now" when planned, before anything
    /// changes. MUST FAIL with the refusal for another folder removed.
    func testAWriteThroughALinkMovedToAnotherFolderIsRefusedBeforeAnythingChanges() throws {
        let made = try course(inAWorkingFolder: true)
        let relative: String = "../../elsewhere/Unit 1, Day 3.md"
        let linked = try linkedDay3(in: made, target: relative)
        let otherFolder: URL = made.course.appendingPathComponent("section1/Other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let moved: URL = otherFolder.appendingPathComponent("Unit 1, Day 4.md")
        let targetText: String = try String(contentsOf: linked.target, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.moveLink(linked.link, to: moved, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: linked.link)))
        step.write("---\ntitle: Unit 1, Day 4\n---\n", to: moved)
        // Refused when planned, never left to the door to find unnamable
        // (which would make a "could not record" trail line first).
        XCTAssertNotNil(step.refusedBeforeMaking, "the write through a link moved to another folder was planned")

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                return XCTFail("not refused as cannot tell now: \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.link.path), relative)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(try String(contentsOf: linked.target, encoding: .utf8), targetText)
    }

    // MARK: - Tests: a place a link's move leaves (U4b3 door-6)

    /// A class page that is a symbolic link at `name` in the class folder,
    /// leading to `destination` as written (relative, or a whole path).
    func linkedPage(named name: String, in made: (course: URL, day1: URL, day2: URL, list: URL), leadingTo destination: String) throws -> URL {
        let link: URL = made.day1.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
        return link
    }

    /// A page the link leads to, in a folder of the course called
    /// `elsewhere`, or outside the working folder when `outside` is true.
    func linkedFile(named name: String, in made: (course: URL, day1: URL, day2: URL, list: URL), outside: Bool = false) throws -> URL {
        var folder: URL = made.course.appendingPathComponent("elsewhere", isDirectory: true)
        if outside {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("journaled-step-outside-\(UUID().uuidString)", isDirectory: true)
            folders.append(folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file: URL = folder.appendingPathComponent(name)
        try "---\ntitle: Linked\npublish: false\n---\nLinked.\n".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// The ops of the newest step in the list.
    func newestOps() throws -> [UndoOp] {
        let fold: UndoFold = try UndoJournalLocation.standardJournal().read()
        var newest: UndoStepRecord? = nil
        for (_, record) in fold.records {
            if newest == nil || record.step.seq > (newest?.step.seq ?? 0) {
                newest = record
            }
        }
        return try XCTUnwrap(newest).step.ops
    }

    /// Every "could not record" trail line while `body` runs.
    func couldNotRecordLines(while body: () throws -> Void) rethrows -> [UndoUnrecordedChange] {
        var lines: [UndoUnrecordedChange] = []
        let before = UndoTrailHook.couldNotRecordLine
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            lines.append(change)
        }
        defer {
            UndoTrailHook.couldNotRecordLine = before
        }
        try body()
        return lines
    }

    func isALink(_ url: URL) -> Bool {
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Shape A: the link moves on (Day 3 to Day 4) and a new page is
    /// planned at the place it leaves. Through the plan the place reads
    /// free until the write; the step is recorded as the link's move then a
    /// new file at Day 3, never followed through the leaving link. MUST FAIL
    /// with `fileExists` following the leaving link (true), or with the
    /// write's before read from the disk there (the link: not recorded).
    func testAWriteAtThePlaceALinkMoveLeavesIsRecordedAsANewFile() throws {
        let made = try course(inAWorkingFolder: true)
        let relative: String = "../../elsewhere/Unit 1, Day 3.md"
        let linked = try linkedDay3(in: made, target: relative)
        let targetText: String = try String(contentsOf: linked.target, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.moveLink(linked.link, to: linked.newName, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: linked.link)))

        XCTAssertFalse(step.fileExists(linked.link), "the place the link leaves reads as taken")
        XCTAssertNil(step.readText(linked.link))
        XCTAssertNil(step.readData(linked.link))
        XCTAssertThrowsError(try step.readTextOrThrow(linked.link))
        let onDisk: [URL] = [made.day1, made.day2, linked.link]
        var listed: [String] = []
        for url in step.markdownFiles(under: made.course, onDisk: onDisk) {
            listed.append(url.lastPathComponent)
        }
        // Review E of U4b3: a moved link is listed at neither name.
        XCTAssertEqual(listed, ["Unit 1, Day 1.md", "Unit 1, Day 2.md"])

        step.write("New.\n", to: linked.link)
        XCTAssertTrue(step.fileExists(linked.link))
        XCTAssertEqual(step.readText(linked.link), "New.\n")
        XCTAssertNil(step.refusedBeforeMaking)
        listed = []
        for url in step.markdownFiles(under: made.course, onDisk: onDisk) {
            listed.append(url.lastPathComponent)
        }
        XCTAssertEqual(listed, ["Unit 1, Day 1.md", "Unit 1, Day 2.md", "Unit 1, Day 3.md"])

        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [], "the step was not recorded")
        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(ops.count, 2)
        if ops.count == 2 {
            XCTAssertNotNil(ops[0].linkSha, "the link's move is not first")
            XCTAssertEqual(ops[1].knownKind, .writeFile)
            XCTAssertEqual(ops[1].path?.hasSuffix("section1/All Classes/Unit 1, Day 3.md"), true, "\(ops[1].path ?? "nil")")
            XCTAssertNil(ops[1].beforeSha)
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.newName.path), relative)
        XCTAssertFalse(isALink(linked.link), "Day 3 is still a link")
        XCTAssertEqual(try String(contentsOf: linked.link, encoding: .utf8), "New.\n")
        XCTAssertEqual(try String(contentsOf: linked.target, encoding: .utf8), targetText)
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// Shape A with the retitle U4b3 part 2 makes: the link's new name read
    /// through the plan (the file it leads to) and written back retitled,
    /// planned at that file; still one step.
    func testARetitleThroughTheMovedLinkIsPlannedAtTheFileItLeadsTo() throws {
        let made = try course(inAWorkingFolder: true)
        let relative: String = "../../elsewhere/Unit 1, Day 3.md"
        let linked = try linkedDay3(in: made, target: relative)
        let step: JournaledStep = step(for: made.course)
        step.moveLink(linked.link, to: linked.newName, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: linked.link)))
        step.write("New.\n", to: linked.link)
        let read: String = try XCTUnwrap(step.readText(linked.newName))
        let retitled: String = read.replacingOccurrences(of: "title: Unit 1, Day 3", with: "title: Unit 1, Day 4")
        XCTAssertNotEqual(read, retitled)
        step.write(retitled, to: linked.newName)

        XCTAssertEqual(step.plannedOrder, [JournaledStep.key(of: linked.link), JournaledStep.key(of: linked.target)])
        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [])
        XCTAssertEqual(try UndoJournalLocation.standardJournal().read().records.count, 1)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.newName.path), relative)
        XCTAssertEqual(try String(contentsOf: linked.target, encoding: .utf8), retitled)
        XCTAssertEqual(try String(contentsOf: linked.link, encoding: .utf8), "New.\n")
    }

    /// Shape B: Day 3 (a plain page) is copied to Day 4 and removed, the
    /// link at Day 2 moves into Day 3, and a new page is made at Day 2, as
    /// Insert Class plans a link below a plain class. Recorded, each place
    /// is left before it is filled (the door-4 rule), so the door takes it
    /// as one step. MUST FAIL with today's op order (the move before the
    /// removal it fills).
    func testARemovalALinkMovesIntoIsRecordedBeforeTheMove() throws {
        let made = try course(inAWorkingFolder: true)
        let target: URL = try linkedFile(named: "Unit 1, Day 2.md", in: made)
        let relative: String = "../../elsewhere/Unit 1, Day 2.md"
        let day2: URL = try linkedPage(named: "Unit 1, Day 2.md", in: made, leadingTo: relative)
        let classes: URL = made.day1.deletingLastPathComponent()
        let day3: URL = classes.appendingPathComponent("Unit 1, Day 3.md")
        let day4: URL = classes.appendingPathComponent("Unit 1, Day 4.md")
        try "---\ntitle: Unit 1, Day 3\n---\nThree.\n".write(to: day3, atomically: true, encoding: .utf8)
        let targetText: String = try String(contentsOf: target, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write("---\ntitle: Unit 1, Day 4\n---\nThree.\n", to: day4)
        step.remove(day3)
        step.moveLink(day2, to: day3, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: day2)))
        XCTAssertFalse(step.fileExists(day2))
        XCTAssertEqual(step.readText(day3), targetText, "the link's new place does not read as the file it leads to")
        step.write("New.\n", to: day2)

        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [])
        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(ops.count, 4)
        XCTAssertEqual(UndoCheck.handovers(in: ops).count, 2, "a place is not left before it is filled")
        XCTAssertTrue(UndoStep.wholeOpsStandAlone(ops))
        XCTAssertEqual(try String(contentsOf: day4, encoding: .utf8), "---\ntitle: Unit 1, Day 4\n---\nThree.\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day3.path), relative)
        XCTAssertFalse(isALink(day2))
        XCTAssertEqual(try String(contentsOf: day2, encoding: .utf8), "New.\n")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), targetText)
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// Shape C: two links in a row (Day 2 and Day 3) each move up one, and a
    /// new page is made at Day 2. Planned lowest first here, so the order
    /// must put the move that leaves Day 3 before the one that fills it:
    /// one step. MUST FAIL with today's op order.
    func testTwoLinksInARowMoveUpAsOneStep() throws {
        let made = try course(inAWorkingFolder: true)
        _ = try linkedFile(named: "Unit 1, Day 2.md", in: made)
        _ = try linkedFile(named: "Unit 1, Day 3.md", in: made)
        let relative2: String = "../../elsewhere/Unit 1, Day 2.md"
        let relative3: String = "../../elsewhere/Unit 1, Day 3.md"
        let day2: URL = try linkedPage(named: "Unit 1, Day 2.md", in: made, leadingTo: relative2)
        let day3: URL = try linkedPage(named: "Unit 1, Day 3.md", in: made, leadingTo: relative3)
        let day4: URL = day3.deletingLastPathComponent().appendingPathComponent("Unit 1, Day 4.md")
        let step: JournaledStep = step(for: made.course)
        step.moveLink(day2, to: day3, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: day2)))
        step.moveLink(day3, to: day4, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: day3)))
        step.write("New.\n", to: day2)

        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [])
        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(UndoCheck.handovers(in: ops).count, 2)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day4.path), relative3)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day3.path), relative2)
        XCTAssertEqual(try String(contentsOf: day2, encoding: .utf8), "New.\n")
    }

    /// Shape B with the link leading OUT of the working folder and a retitle
    /// planned through it: the step cannot be named, so it leaves one "could
    /// not record" line saying it went ahead, and is made unrecorded in the
    /// handing-over order, whole. MUST FAIL with today's order (the move is
    /// refused at Day 3, which the removal has not yet left).
    func testAnUnrecordedHandoverIsMadeInTheHandingOverOrder() throws {
        let made = try course(inAWorkingFolder: true)
        let target: URL = try linkedFile(named: "Unit 1, Day 2.md", in: made, outside: true)
        let day2: URL = try linkedPage(named: "Unit 1, Day 2.md", in: made, leadingTo: target.path)
        let classes: URL = made.day1.deletingLastPathComponent()
        let day3: URL = classes.appendingPathComponent("Unit 1, Day 3.md")
        let day4: URL = classes.appendingPathComponent("Unit 1, Day 4.md")
        try "---\ntitle: Unit 1, Day 3\n---\nThree.\n".write(to: day3, atomically: true, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.write("---\ntitle: Unit 1, Day 4\n---\nThree.\n", to: day4)
        step.remove(day3)
        step.moveLink(day2, to: day3, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: day2)))
        step.write("New.\n", to: day2)
        let read: String = try XCTUnwrap(step.readText(day3))
        step.write(read.replacingOccurrences(of: "title: Linked", with: "title: Unit 1, Day 3"), to: day3)

        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [.wentAhead])
        XCTAssertEqual(try UndoJournalLocation.standardJournal().read().records.count, 0)
        XCTAssertEqual(try String(contentsOf: day4, encoding: .utf8), "---\ntitle: Unit 1, Day 4\n---\nThree.\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day3.path), target.path)
        XCTAssertEqual(try String(contentsOf: day2, encoding: .utf8), "New.\n")
        XCTAssertFalse(isALink(day2))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "---\ntitle: Unit 1, Day 3\npublish: false\n---\nLinked.\n")
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// A link moved onto a page the step does not remove: nothing hands the
    /// place over, and no caller checks it, so the door refuses the step
    /// `changedSince` (its move never replaces) and nothing changes.
    func testALinkMovedOntoAPageTheStepKeepsIsRefusedAndNothingChanges() throws {
        let made = try course(inAWorkingFolder: true)
        let relative: String = "../../elsewhere/Unit 1, Day 3.md"
        let linked = try linkedDay3(in: made, target: relative)
        let day2Text: String = try String(contentsOf: made.day2, encoding: .utf8)
        let step: JournaledStep = step(for: made.course)
        step.moveLink(linked.link, to: made.day2, linkSha: try XCTUnwrap(UndoTreeReading.linkSha(at: linked.link)))

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.changedSince, _) = error else {
                return XCTFail("not refused as changed since: \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.link.path), relative)
        XCTAssertFalse(isALink(made.day2))
        XCTAssertEqual(try String(contentsOf: made.day2, encoding: .utf8), day2Text)
    }

    // MARK: - Recorded by JournaledStep (relink-4)

    /// Where a relinked link's two texts lead.
    enum RelinkLeads: CaseIterable {
        /// To two pages of the course, by relative text.
        case inside
        /// To two files outside the working folder, by absolute text.
        case outToAFile
        /// To nothing, outside the working folder.
        case outToNothing
    }

    /// A relink alone, its texts leading inside, out to a file and out to
    /// nothing: one step, one op with both shas, both texts in the list
    /// byte for byte, the link at its new name holding exactly the new
    /// text and nothing at the old; Undo puts the old name and old text
    /// back, Redo the new; nothing outside read, written or made. MUST FAIL
    /// with the relink recorded as a plain link's move (the old text at the
    /// new name) or with either text left out of the list.
    func testARelinkAloneIsRecordedWithBothTextsAndUndoneAndRedone() throws {
        for leads in RelinkLeads.allCases {
            let made = try course(inAWorkingFolder: true)
            let texts: (old: String, new: String) = try relinkTexts(leads, in: made)
            let outside: URL? = outsideFolderOf(texts.old, leads: leads)
            let outsideBefore: [String: String] = try timesUnder(outside)
            let classes: URL = made.day1.deletingLastPathComponent()
            let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: texts.old)
            let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
            let before: [String: String] = try everythingUnder(made.course)
            JournaledStep.modeOverride = .live
            let step: JournaledStep = step(for: made.course)
            XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data(texts.new.utf8)), "\(leads)")
            try step.make()

            let ops: [UndoOp] = try newestOps()
            XCTAssertEqual(ops.count, 1, "\(leads)")
            let op: UndoOp = try XCTUnwrap(ops.first)
            XCTAssertTrue(op.isARelink, "\(leads)")
            XCTAssertNil(op.linkSha, "\(leads)")
            let journal: UndoJournal = UndoJournalLocation.standardJournal()
            XCTAssertEqual(journal.readBlob(sha: try XCTUnwrap(op.linkShaBefore)), Data(texts.old.utf8), "\(leads)")
            XCTAssertEqual(journal.readBlob(sha: try XCTUnwrap(op.linkShaAfter)), Data(texts.new.utf8), "\(leads)")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day5.path), texts.new, "\(leads)")
            XCTAssertFalse(standsAnything(day4), "\(leads)")
            let after: [String: String] = try everythingUnder(made.course)

            let root: URL = workingFolder(of: made)
            XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1), "\(leads)")
            XCTAssertEqual(try everythingUnder(made.course), before, "\(leads)")
            XCTAssertEqual(journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .redone(seq: 1), "\(leads)")
            XCTAssertEqual(try everythingUnder(made.course), after, "\(leads)")
            XCTAssertEqual(stagedNames(under: made.course), [], "\(leads)")
            XCTAssertEqual(try timesUnder(outside), outsideBefore, "\(leads): something outside was read, written or made")
            JournaledStep.modeOverride = nil
        }
    }

    /// Insert Class's shape: the link at Day 4 is relinked to Day 5 (its
    /// text `Unit 1, Day 3.md` becoming `Unit 1, Day 4.md`), the page at
    /// Day 3 is written, retitled, at Day 4 (the place the link leaves, a
    /// new file there, never through the leaving link) and removed, and a
    /// new page is made at Day 3. One step in the handing-over order; Undo
    /// and Redo exact. MUST FAIL with the old place read as taken (door-6's
    /// reading skipped for a relink).
    func testARelinkWhoseOldPlaceIsFilledInTheSameStepIsOneStep() throws {
        let made = try course(inAWorkingFolder: true)
        let classes: URL = made.day1.deletingLastPathComponent()
        let day3: URL = classes.appendingPathComponent("Unit 1, Day 3.md")
        let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
        try "---\ntitle: Unit 1, Day 3\n---\nThree.\n".write(to: day3, atomically: true, encoding: .utf8)
        let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: "Unit 1, Day 3.md")
        let before: [String: String] = try everythingUnder(made.course)
        JournaledStep.modeOverride = .live
        let step: JournaledStep = step(for: made.course)
        XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data("Unit 1, Day 4.md".utf8)))
        XCTAssertFalse(step.fileExists(day4), "the place the relink leaves reads as taken")
        step.write("---\ntitle: Unit 1, Day 4\n---\nThree.\n", to: day4)
        step.remove(day3)
        step.write("New.\n", to: day3)
        try step.make()

        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(UndoCheck.handovers(in: ops).count, 1)
        XCTAssertTrue(UndoStep.wholeOpsStandAlone(ops))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day5.path), "Unit 1, Day 4.md")
        XCTAssertFalse(isALink(day4))
        XCTAssertEqual(try String(contentsOf: day4, encoding: .utf8), "---\ntitle: Unit 1, Day 4\n---\nThree.\n")
        XCTAssertEqual(try String(contentsOf: day3, encoding: .utf8), "New.\n")
        let after: [String: String] = try everythingUnder(made.course)

        let root: URL = workingFolder(of: made)
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), before)
        XCTAssertEqual(journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .redone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), after)
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// Two relinks in a row, the second filling the place the first
    /// leaves (Day 4 to Day 5, Day 3 to Day 4, each with its own new
    /// text), planned lowest first so the order must change: one step,
    /// exact both ways.
    func testTwoRelinksInARowAreOneStep() throws {
        let made = try course(inAWorkingFolder: true)
        let classes: URL = made.day1.deletingLastPathComponent()
        let day3: URL = try linkedPage(named: "Unit 1, Day 3.md", in: made, leadingTo: "../../elsewhere/three.md")
        let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: "../../elsewhere/four.md")
        let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
        let before: [String: String] = try everythingUnder(made.course)
        JournaledStep.modeOverride = .live
        let step: JournaledStep = step(for: made.course)
        XCTAssertTrue(step.relinkLink(day3, to: day4, textAfter: Data("../../elsewhere/four.md".utf8)))
        XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data("../../elsewhere/five.md".utf8)))
        try step.make()

        let ops: [UndoOp] = try newestOps()
        XCTAssertEqual(ops.count, 2)
        XCTAssertEqual(UndoCheck.handovers(in: ops).count, 1)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day5.path), "../../elsewhere/five.md")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day4.path), "../../elsewhere/four.md")
        XCTAssertFalse(standsAnything(day3))
        let after: [String: String] = try everythingUnder(made.course)

        let root: URL = workingFolder(of: made)
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), before)
        XCTAssertEqual(journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .redone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), after)
    }

    /// A write planned at a relink's new name, by either way of planning
    /// one, would be a write through a link whose text the step changes:
    /// the step is refused before anything changes, nothing on the list,
    /// the link and what it leads to untouched. MUST FAIL with the refusal
    /// taken out (the write goes through the link).
    func testAWriteAtARelinksNewNameIsRefusedBeforeAnythingChanges() throws {
        for byReadBytes in [false, true] {
            let made = try course(inAWorkingFolder: true)
            let target: URL = try linkedFile(named: "Unit 1, Day 3.md", in: made)
            let classes: URL = made.day1.deletingLastPathComponent()
            let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: "../../elsewhere/Unit 1, Day 3.md")
            let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
            let before: [String: String] = try everythingUnder(made.course)
            let step: JournaledStep = step(for: made.course)
            XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data("../../elsewhere/Unit 1, Day 4.md".utf8)))
            if byReadBytes {
                step.write(Data("Through.\n".utf8), to: day5, plannedFrom: try Data(contentsOf: target))
            } else {
                step.write("Through.\n", to: day5)
            }
            XCTAssertThrowsError(try step.make(), "\(byReadBytes)") { error in
                guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                    return XCTFail("not refused as cannot tell now: \(error)")
                }
            }
            XCTAssertEqual(try everythingUnder(made.course), before, "\(byReadBytes)")
            XCTAssertEqual(try UndoJournalLocation.standardJournal().read().records.count, 0, "\(byReadBytes)")
        }
    }

    /// The list refusing the relink's SECOND text (its blob folder locked)
    /// with the switch off: one trail line saying the action went ahead,
    /// nothing on the list, and the relink made as the door would have
    /// made it, the link at its new name holding the new text.
    func testARelinkWhoseNewTextTheListRefusesGoesAheadUnrecorded() throws {
        let made = try course(inAWorkingFolder: true)
        let classes: URL = made.day1.deletingLastPathComponent()
        let oldText: String = "../../elsewhere/old.md"
        let newText: String = "../../elsewhere/new.md"
        let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: oldText)
        let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        let oldFolder: URL = journal.blobURL(sha: UndoHash.sha256(of: Data(oldText.utf8))).deletingLastPathComponent()
        let newFolder: URL = journal.blobURL(sha: UndoHash.sha256(of: Data(newText.utf8))).deletingLastPathComponent()
        XCTAssertNotEqual(oldFolder.path, newFolder.path, "the two texts' blobs share a folder: choose other texts")
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: newFolder.path)
        lockedFolders.append(newFolder)
        let step: JournaledStep = step(for: made.course)
        XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data(newText.utf8)))

        let lines: [UndoUnrecordedChange] = try couldNotRecordLines {
            try step.make()
        }
        XCTAssertEqual(lines, [.wentAhead])
        XCTAssertEqual(try journal.read().records.count, 0)
        XCTAssertNil(journal.readBlob(sha: UndoHash.sha256(of: Data(newText.utf8))))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day5.path), newText)
        XCTAssertFalse(standsAnything(day4))
        XCTAssertEqual(stagedNames(under: made.course), [])
    }

    /// The handed-over place left by a relink leading OUT of the working
    /// folder, filled in Insert Class's way (the page below written there,
    /// retitled, and removed from its own place; relink-3's parked case
    /// met through a write, not a page's move): the link is moved as a
    /// link, never followed, so the step is recorded and made, Undo and
    /// Redo exact, nothing outside touched.
    func testAPageWrittenIntoThePlaceALinkLeadingOutLeavesIsOneStep() throws {
        let made = try course(inAWorkingFolder: true)
        let texts: (old: String, new: String) = try relinkTexts(.outToAFile, in: made)
        let outside: URL? = outsideFolderOf(texts.old, leads: .outToAFile)
        let outsideBefore: [String: String] = try timesUnder(outside)
        let classes: URL = made.day1.deletingLastPathComponent()
        let day3: URL = classes.appendingPathComponent("Unit 1, Day 3.md")
        let day5: URL = classes.appendingPathComponent("Unit 1, Day 5.md")
        try "---\ntitle: Unit 1, Day 3\n---\nThree.\n".write(to: day3, atomically: true, encoding: .utf8)
        let day4: URL = try linkedPage(named: "Unit 1, Day 4.md", in: made, leadingTo: texts.old)
        let before: [String: String] = try everythingUnder(made.course)
        JournaledStep.modeOverride = .live
        let step: JournaledStep = step(for: made.course)
        XCTAssertTrue(step.relinkLink(day4, to: day5, textAfter: Data(texts.new.utf8)))
        step.write("---\ntitle: Unit 1, Day 4\n---\nThree.\n", to: day4)
        step.remove(day3)
        try step.make()

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: day5.path), texts.new)
        XCTAssertEqual(try String(contentsOf: day4, encoding: .utf8), "---\ntitle: Unit 1, Day 4\n---\nThree.\n")
        XCTAssertFalse(isALink(day4))
        XCTAssertFalse(standsAnything(day3))
        let after: [String: String] = try everythingUnder(made.course)
        let root: URL = workingFolder(of: made)
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        XCTAssertEqual(journal.undoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .undone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), before)
        XCTAssertEqual(journal.redoNewest(resolveRoot: { _ in root }, places: UndoMemoryPlaces()), .redone(seq: 1))
        XCTAssertEqual(try everythingUnder(made.course), after)
        XCTAssertEqual(try timesUnder(outside), outsideBefore)
    }

    // MARK: - Helpers (relink-4)

    /// A relink's old and new texts: two pages of the course by relative
    /// text, two files laid outside the working folder by absolute text,
    /// or two absolute places outside naming nothing.
    func relinkTexts(_ leads: RelinkLeads, in made: (course: URL, day1: URL, day2: URL, list: URL)) throws -> (old: String, new: String) {
        switch leads {
        case .inside:
            _ = try linkedFile(named: "old.md", in: made)
            _ = try linkedFile(named: "new.md", in: made)
            return (old: "../../elsewhere/old.md", new: "../../elsewhere/new.md")
        case .outToAFile:
            let old: URL = try linkedFile(named: "old.md", in: made, outside: true)
            let new: URL = old.deletingLastPathComponent().appendingPathComponent("new.md")
            try "---\ntitle: New\n---\nNew.\n".write(to: new, atomically: true, encoding: .utf8)
            return (old: old.path, new: new.path)
        case .outToNothing:
            let folder: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("journaled-step-outside-\(UUID().uuidString)", isDirectory: true)
            folders.append(folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (old: folder.appendingPathComponent("gone old.md").path, new: folder.appendingPathComponent("gone new.md").path)
        }
    }

    /// The folder outside the working folder a text leads into, or nil.
    func outsideFolderOf(_ text: String, leads: RelinkLeads) -> URL? {
        if leads == .inside {
            return nil
        }
        return URL(fileURLWithPath: text).deletingLastPathComponent()
    }

    /// Every item in a folder by name with its access and modification
    /// times, read with `lstat` only: nothing made there, read or written.
    func timesUnder(_ folder: URL?) throws -> [String: String] {
        var found: [String: String] = [:]
        guard let folder else {
            return found
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            var information: stat = stat()
            XCTAssertEqual(lstat(folder.appendingPathComponent(name).path, &information), 0)
            found[name] = "\(information.st_atimespec.tv_sec).\(information.st_atimespec.tv_nsec) \(information.st_mtimespec.tv_sec).\(information.st_mtimespec.tv_nsec)"
        }
        return found
    }

    /// The working folder holding the course's `courses` folder.
    func workingFolder(of made: (course: URL, day1: URL, day2: URL, list: URL)) -> URL {
        return made.course.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Whether anything at all stands at the place, a link leading nowhere
    /// included (`lstat`).
    func standsAnything(_ url: URL) -> Bool {
        var information: stat = stat()
        return lstat(url.path, &information) == 0
    }

    /// Everything under the folder by relative path: a link by its text, a
    /// file by its bytes, a folder as a folder. Never followed.
    func everythingUnder(_ folder: URL) throws -> [String: String] {
        var found: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else {
            return found
        }
        while let name = walker.nextObject() as? String {
            let url: URL = folder.appendingPathComponent(name)
            let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
            let type: FileAttributeType? = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                found[name] = "link to " + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
            } else if type == .typeDirectory {
                found[name] = "folder"
            } else {
                found[name] = "file " + (try Data(contentsOf: url)).base64EncodedString()
            }
        }
        return found
    }
}
