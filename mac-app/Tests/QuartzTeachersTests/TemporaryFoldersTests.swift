import Darwin
import Foundation
import XCTest
@testable import QuartzTeachers

/// The test helper that removes the suite's temporary folders
/// (`TemporaryFolders.swift`, #978 and its follow-ups) is itself tested here:
/// a symbolic link handed to it never reaches its target, things that point
/// at a folder let go before it is removed, and a finished run's record is
/// swept by the next run.
final class TemporaryFoldersTests: XCTestCase {

    // MARK: - Functions

    /// The user flags on a path, read without following a link.
    func userFlags(atPath path: String) -> UInt32 {
        var status: stat = stat()
        if lstat(path, &status) != 0 {
            return 0
        }
        return status.st_flags
    }

    /// True when anything, a dangling link included, is at the path.
    func somethingIsAt(_ path: String) -> Bool {
        var status: stat = stat()
        return lstat(path, &status) == 0
    }

    /// A process id no process has now, found by asking.
    func processIdentifierThatHasGone(after earlier: Int32 = 98_999) throws -> Int32 {
        var candidate: Int32 = earlier + 1
        while candidate < 99_999 {
            if TemporaryFolderSweeper.processHasGone(candidate) {
                return candidate
            }
            candidate += 1
        }
        throw XCTSkip("every process id tried is in use")
    }

    /// A process id above 1 that a live process other than this one holds.
    func processIdentifierThatIsAlive() throws -> Int32 {
        let ownProcess: Int32 = ProcessInfo.processInfo.processIdentifier
        var candidate: Int32 = 2
        while candidate < 99_999 {
            if candidate != ownProcess && TemporaryFolderSweeper.processHasGone(candidate) == false {
                return candidate
            }
            candidate += 1
        }
        throw XCTSkip("no other live process was found")
    }

    /// A scratch folder standing in for the temp folder, with a sentinel
    /// file in it, so a sweep that reached the folder itself would show.
    func makeScratchTemporaryFolder() throws -> (folder: URL, sentinel: URL) {
        let folderURL: URL = try makeTemporaryFolder(prefix: "temp-helper-sweep")
        let sentinelURL: URL = folderURL.appendingPathComponent("sentinel.txt")
        try "still here".write(to: sentinelURL, atomically: true, encoding: .utf8)
        return (folderURL, sentinelURL)
    }

    /// Writes a record into the scratch folder, exactly as given.
    func writeRecord(_ text: String, forProcess processIdentifier: Int32, in folderURL: URL) throws -> URL {
        let recordURL: URL = folderURL.appendingPathComponent(
            TemporaryFolderSweeper.runRecordPrefix + String(processIdentifier)
        )
        try text.write(to: recordURL, atomically: true, encoding: .utf8)
        return recordURL
    }

    /// Makes a folder in the scratch folder with a locked file inside.
    func makeLockedFolder(named name: String, in folderURL: URL) throws -> URL {
        let madeURL: URL = folderURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: madeURL, withIntermediateDirectories: true)
        let lockedFileURL: URL = madeURL.appendingPathComponent("trail.txt")
        try "late line".write(to: lockedFileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(lchflags(lockedFileURL.path, UInt32(UF_IMMUTABLE)), 0)
        return madeURL
    }

    /// Runs the sweep over the scratch folder only.
    func sweep(_ folderURL: URL) {
        TemporaryFolderSweeper.removeWhatFinishedRunsLeft(
            inFolder: folderURL,
            exceptProcess: ProcessInfo.processInfo.processIdentifier
        )
    }

    // MARK: - Tests

    /// A folder handed in that is itself a symbolic link: the link goes,
    /// and the folder it points at keeps every file and every flag.
    func testASymbolicLinkIsRemovedWithoutTouchingItsTarget() throws {
        let targetURL: URL = try makeTemporaryFolder(prefix: "temp-helper-target")
        let lockedFileURL: URL = targetURL.appendingPathComponent("locked.txt")
        try "kept".write(to: lockedFileURL, atomically: true, encoding: .utf8)
        let innerFolderURL: URL = targetURL.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: innerFolderURL, withIntermediateDirectories: true)
        XCTAssertEqual(lchflags(lockedFileURL.path, UInt32(UF_IMMUTABLE)), 0, "the target's file could not be locked")
        XCTAssertEqual(lchflags(innerFolderURL.path, UInt32(UF_IMMUTABLE)), 0, "the target's folder could not be locked")

        let holderURL: URL = try makeTemporaryFolder(prefix: "temp-helper-link")
        let linkURL: URL = holderURL.appendingPathComponent("link-to-target")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        TemporaryFolders.unlockAndRemove(linkURL)

        XCTAssertFalse(somethingIsAt(linkURL.path), "the link itself should be gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedFileURL.path), "the target's file must not be touched")
        XCTAssertNotEqual(userFlags(atPath: lockedFileURL.path) & UInt32(UF_IMMUTABLE), 0, "the target's file must stay locked")
        XCTAssertNotEqual(userFlags(atPath: innerFolderURL.path) & UInt32(UF_IMMUTABLE), 0, "the target's folder must stay locked")
        XCTAssertTrue(FileManager.default.fileExists(atPath: innerFolderURL.path), "the target's folder must not be touched")
    }

    /// A dangling link (its target already gone) is removed too.
    func testADanglingLinkIsRemoved() throws {
        let holderURL: URL = try makeTemporaryFolder(prefix: "temp-helper-dangling")
        let linkURL: URL = holderURL.appendingPathComponent("link-to-nothing")
        try FileManager.default.createSymbolicLink(
            atPath: linkURL.path,
            withDestinationPath: holderURL.appendingPathComponent("never-made").path
        )

        TemporaryFolders.unlockAndRemove(linkURL)

        XCTAssertFalse(somethingIsAt(linkURL.path))
    }

    /// A locked folder with a link inside it to a locked folder elsewhere:
    /// the folder goes, the link's target keeps its file and its flag.
    func testALinkInsideAFolderIsNotFollowed() throws {
        let targetURL: URL = try makeTemporaryFolder(prefix: "temp-helper-inner-target")
        let lockedFileURL: URL = targetURL.appendingPathComponent("locked.txt")
        try "kept".write(to: lockedFileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(lchflags(lockedFileURL.path, UInt32(UF_IMMUTABLE)), 0)

        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("temp-helper-outer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        removeWhenTestEnds(folderURL)
        try FileManager.default.createSymbolicLink(
            atPath: folderURL.appendingPathComponent("link").path,
            withDestinationPath: targetURL.path
        )
        XCTAssertEqual(lchflags(folderURL.path, UInt32(UF_IMMUTABLE)), 0)

        TemporaryFolders.unlockAndRemove(folderURL)

        XCTAssertFalse(somethingIsAt(folderURL.path), "the locked folder should be gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedFileURL.path))
        XCTAssertNotEqual(userFlags(atPath: lockedFileURL.path) & UInt32(UF_IMMUTABLE), 0)
    }

    /// The trail store is put back BEFORE its folder is removed. The check
    /// is a teardown block registered first, so it runs after both of the
    /// helper's blocks.
    func testTheTrailStoreIsPutBackBeforeItsFolderGoes() throws {
        let storeBefore: URL = ActivityTrail.store.folderURL
        nonisolated(unsafe) var trailFolderURL: URL? = nil
        addTeardownBlock {
            XCTAssertEqual(
                ActivityTrail.store.folderURL, storeBefore,
                "the store should point where it did before the test"
            )
            if let trailFolderURL {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: trailFolderURL.path),
                    "the throwaway trail should be gone"
                )
            }
        }
        trailFolderURL = useThrowawayTrail(prefix: "temp-helper-trail")

        ActivityTrail.note(.workingFolderOpened, "a line written by TemporaryFoldersTests")

        XCTAssertEqual(ActivityTrail.store.folderURL, trailFolderURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(trailFolderURL).path), "the line made the folder")
    }

    /// A fixture shown in the app's window: when the test ends the window is
    /// pointed elsewhere first, and only then does the fixture go.
    @MainActor
    func testTheWindowLetsGoOfAFixtureBeforeItGoes() async throws {
        guard let workspace = WorkspaceModel.windowModels.first else {
            throw XCTSkip("No window model registered; the interface is not on screen")
        }
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        addTeardownBlock { @MainActor in
            var shownPath: String = ""
            if let shownURL = workspace.workspaceURL {
                shownPath = shownURL.path
            }
            XCTAssertNotEqual(shownPath, fixtureURL.path, "the window should have let go of the fixture")
            XCTAssertEqual(shownPath, TemporaryFolders.restingFolderURL?.path, "the window rests on the run's resting folder")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixtureURL.path), "the fixture should be gone")
        }
        removeWhenTestEndsAfterTheWindowLetsGo(fixtureURL)

        workspace.chooseWorkspace(at: fixtureURL)

        XCTAssertEqual(workspace.workspaceURL?.path, fixtureURL.path)
    }

    /// The next run removes what a finished run's record names, locked files
    /// and all, then the record.
    func testAFinishedRunsRecordIsSweptByTheNextRun() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let homeURL: URL = try makeLockedFolder(named: "plantoir-home-under-test-\(goneProcess)", in: scratch.folder)
        let restingURL: URL = try makeLockedFolder(named: "plantoir-resting-folder-under-test-\(goneProcess)", in: scratch.folder)
        let throwawayURL: URL = try makeLockedFolder(named: "Plantoir-tests-\(UUID().uuidString)", in: scratch.folder)
        let recordURL: URL = try writeRecord(
            homeURL.path + "\n" + restingURL.path + "\n" + throwawayURL.path + "\n",
            forProcess: goneProcess, in: scratch.folder
        )

        sweep(scratch.folder)

        XCTAssertFalse(somethingIsAt(homeURL.path))
        XCTAssertFalse(somethingIsAt(restingURL.path))
        XCTAssertFalse(somethingIsAt(throwawayURL.path))
        XCTAssertFalse(somethingIsAt(recordURL.path), "the finished run's record should be gone")
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path))
    }

    /// `<T>/.` and `<T>/x/..` both name the temp folder itself: skipped.
    func testALineNamingTheTemporaryFolderItselfIsSkipped() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        _ = try writeRecord(
            scratch.folder.path + "/.\n" + scratch.folder.path + "/x/..\n" + scratch.folder.path + "/\n"
                + scratch.folder.path + "\n",
            forProcess: goneProcess, in: scratch.folder
        )
        try FileManager.default.createDirectory(
            at: scratch.folder.appendingPathComponent("x"), withIntermediateDirectories: true
        )

        sweep(scratch.folder)

        XCTAssertTrue(somethingIsAt(scratch.folder.path), "the temp folder itself must never be removed")
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path), "nothing in the temp folder may be removed")
        XCTAssertTrue(somethingIsAt(scratch.folder.appendingPathComponent("x").path))
    }

    /// An unrelated entry, a truncated name, another pid's name, and a run
    /// folder named with a trailing slash or a path under it: all skipped.
    func testALineNamingAnythingButThatRunsFoldersIsSkipped() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let otherGoneProcess: Int32 = try processIdentifierThatHasGone(after: goneProcess)
        let unrelatedURL: URL = try makeLockedFolder(named: "somebody-elses-folder", in: scratch.folder)
        let truncatedURL: URL = try makeLockedFolder(named: "plantoir-home-under-test-", in: scratch.folder)
        let shortenedURL: URL = try makeLockedFolder(named: "plantoir-home-under-te", in: scratch.folder)
        let otherProcessURL: URL = try makeLockedFolder(
            named: "plantoir-home-under-test-\(otherGoneProcess)", in: scratch.folder
        )
        let badUUIDURL: URL = try makeLockedFolder(named: "Plantoir-tests-not-a-uuid", in: scratch.folder)
        let lowerUUIDURL: URL = try makeLockedFolder(
            named: "Plantoir-tests-\(UUID().uuidString.lowercased())", in: scratch.folder
        )
        let homeURL: URL = try makeLockedFolder(named: "plantoir-home-under-test-\(goneProcess)", in: scratch.folder)
        var lines: String = ""
        for namedURL in [unrelatedURL, truncatedURL, shortenedURL, otherProcessURL, badUUIDURL, lowerUUIDURL] {
            lines += namedURL.path + "\n"
        }
        lines += homeURL.path + "/\n"
        lines += homeURL.path + "/trail.txt\n"
        lines += scratch.sentinel.path + "\n"
        _ = try writeRecord(lines, forProcess: goneProcess, in: scratch.folder)

        sweep(scratch.folder)

        for keptURL in [unrelatedURL, truncatedURL, shortenedURL, otherProcessURL, badUUIDURL, lowerUUIDURL, homeURL] {
            XCTAssertTrue(somethingIsAt(keptURL.path), keptURL.lastPathComponent + " should be left alone")
        }
        XCTAssertTrue(somethingIsAt(homeURL.appendingPathComponent("trail.txt").path))
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path))
    }

    /// A link planted at a valid name, pointing at a folder of locked files:
    /// the link goes, the target keeps every file and flag.
    func testALinkPlantedAtARunFolderNameIsRemovedAsALink() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let targetURL: URL = try makeLockedFolder(named: "link-target", in: try makeTemporaryFolder(prefix: "temp-helper-target"))
        let lockedFileURL: URL = targetURL.appendingPathComponent("trail.txt")
        let linkURL: URL = scratch.folder.appendingPathComponent("plantoir-builds-under-test-\(goneProcess)")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)
        _ = try writeRecord(linkURL.path + "\n", forProcess: goneProcess, in: scratch.folder)

        sweep(scratch.folder)

        XCTAssertFalse(somethingIsAt(linkURL.path), "the link itself should be gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedFileURL.path), "the link's target must not be touched")
        XCTAssertNotEqual(userFlags(atPath: lockedFileURL.path) & UInt32(UF_IMMUTABLE), 0, "the target must stay locked")
    }

    /// An empty record and a garbage record remove nothing but themselves.
    func testAnEmptyOrGarbageRecordRemovesNothingElse() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let otherGoneProcess: Int32 = try processIdentifierThatHasGone(after: goneProcess)
        let emptyRecordURL: URL = try writeRecord("", forProcess: goneProcess, in: scratch.folder)
        let garbageRecordURL: URL = try writeRecord(
            "\u{0}\u{1}garbage\n\n../../..\n/\n~\n*\n", forProcess: otherGoneProcess, in: scratch.folder
        )

        sweep(scratch.folder)

        XCTAssertFalse(somethingIsAt(emptyRecordURL.path))
        XCTAssertFalse(somethingIsAt(garbageRecordURL.path))
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path))
    }

    /// A record whose process is alive (the first live process found other
    /// than this one, which stands for a pid reused by an unrelated process
    /// as well as for a run still going) is left alone, and so are its folders; so are records whose
    /// names do not carry a pid written plainly.
    func testALiveRunsRecordAndMisnamedRecordsAreLeftAlone() throws {
        let scratch = try makeScratchTemporaryFolder()
        let liveProcess: Int32 = try processIdentifierThatIsAlive()
        XCTAssertFalse(TemporaryFolderSweeper.processHasGone(liveProcess))
        let liveHomeURL: URL = try makeLockedFolder(named: "plantoir-home-under-test-\(liveProcess)", in: scratch.folder)
        let liveRecordURL: URL = try writeRecord(liveHomeURL.path + "\n", forProcess: liveProcess, in: scratch.folder)

        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let goneHomeURL: URL = try makeLockedFolder(named: "plantoir-home-under-test-\(goneProcess)", in: scratch.folder)
        var misnamedRecordURLs: [URL] = []
        for misnamed in ["0\(goneProcess)", "+\(goneProcess)", "\(goneProcess).txt", "0", "1", "-5"] {
            let recordURL: URL = scratch.folder.appendingPathComponent(TemporaryFolderSweeper.runRecordPrefix + misnamed)
            try (goneHomeURL.path + "\n").write(to: recordURL, atomically: true, encoding: .utf8)
            misnamedRecordURLs.append(recordURL)
        }

        sweep(scratch.folder)

        XCTAssertTrue(somethingIsAt(liveHomeURL.path), "a live process's folder is left alone")
        XCTAssertTrue(somethingIsAt(liveRecordURL.path), "a live process's record is left alone")
        XCTAssertTrue(somethingIsAt(goneHomeURL.path), "a misnamed record is never read")
        for recordURL in misnamedRecordURLs {
            XCTAssertTrue(somethingIsAt(recordURL.path), recordURL.lastPathComponent + " should be left alone")
        }
    }

    /// The names the sweep accepts are read from this run's own folders:
    /// four stems that take a pid, and one prefix that takes a UUID.
    func testTheSweepKnowsTheRunsFolderNames() {
        let shapes = TemporaryFolderSweeper.runFolderNameShapes()
        XCTAssertEqual(shapes.processStems.count, 4, "home, builds, assistant support and the resting folder")
        XCTAssertTrue(shapes.processStems.contains("plantoir-home-under-test-"))
        XCTAssertTrue(shapes.processStems.contains("plantoir-resting-folder-under-test-"))
        XCTAssertEqual(shapes.uuidPrefixes, ["Plantoir-tests-"])
        XCTAssertFalse(TemporaryFolderSweeper.isRunFolderName(".", forProcess: 12_345))
        XCTAssertFalse(TemporaryFolderSweeper.isRunFolderName("..", forProcess: 12_345))
        XCTAssertFalse(TemporaryFolderSweeper.isRunFolderName("plantoir-home-under-test-12345/..", forProcess: 12_345))
        XCTAssertTrue(TemporaryFolderSweeper.isRunFolderName("plantoir-home-under-test-12345", forProcess: 12_345))
    }

    /// This run has written its own record, naming its per-run folders.
    func testThisRunHasARecordNamingItsFolders() throws {
        let recordText: String = try String(contentsOf: TemporaryFolderSweeper.runRecordURL, encoding: .utf8)
        for folderURL in TemporaryFolderSweeper.runFolders {
            XCTAssertTrue(recordText.contains(folderURL.path + "\n"), "the record should name " + folderURL.lastPathComponent)
        }
    }
}
