import Foundation
@testable import QuartzTeachers

/// Checks of the journal core that are not contract cases, because they are
/// about how the mac's own pieces behave rather than what the list answers:
/// reading on from where the fold stopped, the identifier file on a damaged
/// or half-made file, and the lock's waiting (#899, U1, after its two
/// reviews). Each returns what it found wrong, so the standalone harness and
/// `UndoJournalCoreTests` run the same code.
enum UndoCoreChecks {

    // MARK: - Functions

    /// The fold is read on from where it stopped (the core review's W4), and
    /// read whole again when the bytes it read are no longer there.
    static func foldReadsOnFromWhereItStopped(under parent: URL) throws -> [String] {
        var failures: [String] = []
        let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: "read-on")
        try UndoContractReplay.write("---\npublish: false\n---\nBody.\n", to: "p.md", in: place.root)
        // Four steps leave the page as it began, so the next one changes it.
        _ = UndoContractReplay.writeSteps(count: 4, onPage: "p.md", root: place.root, journalFolder: place.journalFolder)
        let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
        _ = try journal.read()

        let fullBefore: Int = UndoFoldCache.fullReads
        _ = UndoContractReplay.writeSteps(count: 1, onPage: "p.md", root: place.root, journalFolder: place.journalFolder)
        let readOn: UndoFold = try journal.read()
        if UndoFoldCache.fullReads != fullBefore {
            failures.append("a step appended by this process made the next read a full one")
        }
        UndoFoldCache.forget(place.journalFolder)
        let whole: UndoFold = try journal.read()
        if readOn != whole {
            failures.append("the fold read on is not the fold read whole")
        }
        if whole.records.count != 5 || whole.highestSeq != 5 {
            failures.append("expected 5 steps, read \(whole.records.count) (highest \(whole.highestSeq))")
        }

        // Another process rewrites the bytes already read (it never should):
        // the cache must notice and read everything again.
        let segment: URL = journal.segmentURL(number: 1)
        var bytes: Data = try Data(contentsOf: segment)
        // Damage the newest complete line's closing brace, keeping the length
        // and the file itself (written in place, not replaced).
        bytes[bytes.count - 2] = 0x78
        let handle: FileHandle = try FileHandle(forUpdating: segment)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: bytes)
        try handle.close()
        let fullBeforeDamage: Int = UndoFoldCache.fullReads
        let afterDamage: UndoFold = try journal.read()
        if UndoFoldCache.fullReads != fullBeforeDamage + 1 {
            failures.append("bytes rewritten under the cache did not make a full read")
        }
        if afterDamage.unreadableLines != 1 {
            failures.append("the damaged line was not counted as unreadable (\(afterDamage.unreadableLines))")
        }

        // A segment replaced by another file is read whole again too.
        UndoFoldCache.forget(place.journalFolder)
        _ = try journal.read()
        let replacement: URL = place.journalFolder.appendingPathComponent("replacement")
        try Data(contentsOf: segment).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(segment, withItemAt: replacement)
        let fullBeforeReplacing: Int = UndoFoldCache.fullReads
        _ = try journal.read()
        if UndoFoldCache.fullReads != fullBeforeReplacing + 1 {
            failures.append("a segment replaced by another file did not make a full read")
        }
        return failures
    }

    /// A `folder-id` that holds no identifier is set aside and a new one made;
    /// an empty one made a moment ago is a creator at work (the contract
    /// review's INCOMPLETE 3, the core review's I2).
    static func identifierFileNeverBlocksForGood(under parent: URL) throws -> [String] {
        var failures: [String] = []
        let folder: URL = parent.appendingPathComponent("identifier", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let damaged: URL = folder.appendingPathComponent("folder-id")
        try Data("not an identifier, a sync conflict's leftovers\n".utf8).write(to: damaged)
        let made: String = try UndoIdentifierFile.readOrCreate(at: damaged)
        if UndoIdentifierFile.read(at: damaged) != made {
            failures.append("a damaged identifier file was not replaced by a readable one")
        }
        if made != made.lowercased() || UUID(uuidString: made) == nil {
            failures.append("the new identifier is not a lower-case UUID: \(made)")
        }
        var setAside: Int = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasPrefix("folder-id.unreadable-") {
            setAside += 1
        }
        if setAside != 1 {
            failures.append("the damaged file was not kept aside (\(setAside) kept)")
        }

        let young: URL = folder.appendingPathComponent("young-id")
        try Data().write(to: young)
        do {
            _ = try UndoIdentifierFile.readOrCreate(at: young)
            failures.append("an empty identifier file made a moment ago was replaced")
        } catch UndoJournalError.identifierBeingMade {
            // A creator at work: not yet.
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: young.path
        )
        let afterTheGrace: String = try UndoIdentifierFile.readOrCreate(at: young)
        if UndoIdentifierFile.read(at: young) != afterTheGrace {
            failures.append("an empty identifier file left by a dead creator still blocks")
        }

        let upper: URL = folder.appendingPathComponent("upper-id")
        let identifier: String = UUID().uuidString
        try Data(("\u{FEFF}" + identifier + "\r\n").utf8).write(to: upper)
        if UndoIdentifierFile.read(at: upper) != identifier.lowercased() {
            failures.append("an identifier in upper case with a mark and CR LF was not read as the same one")
        }
        return failures
    }

    /// A waiter is woken by the grant itself, and a wait that runs out never
    /// keeps the lock (the core review's I3).
    static func lockWaitsForTheGrant(under parent: URL) throws -> [String] {
        var failures: [String] = []
        let folder: URL = parent.appendingPathComponent("lock", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url: URL = folder.appendingPathComponent(".lock")

        let holder: UndoLock = try UndoLock.take(at: url, waitingAtMost: 1)
        let releaser: Thread = Thread {
            Thread.sleep(forTimeInterval: 0.2)
            holder.release()
        }
        releaser.start()
        let started: Date = Date()
        let waiter: UndoLock = try UndoLock.take(at: url, waitingAtMost: 5)
        let waited: Double = Date().timeIntervalSince(started)
        if waited > 1.5 {
            failures.append("the waiter took \(waited) s for a lock freed after 0.2 s")
        }
        waiter.release()

        let second: UndoLock = try UndoLock.take(at: url, waitingAtMost: 1)
        do {
            _ = try UndoLock.take(at: url, waitingAtMost: 0.1)
            failures.append("a held lock was taken twice")
        } catch UndoJournalError.lockBusy {
            // Gave up, as it should.
        }
        second.release()
        do {
            let third: UndoLock = try UndoLock.take(at: url, waitingAtMost: 2)
            third.release()
        } catch {
            failures.append("a wait that ran out kept the lock: \(error)")
        }
        return failures
    }
}
