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
    func processIdentifierThatHasGone() throws -> Int32 {
        var candidate: Int32 = 99_000
        while candidate < 99_999 {
            if TemporaryFolderSweeper.processHasGone(candidate) {
                return candidate
            }
            candidate += 1
        }
        throw XCTSkip("every process id tried is in use")
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

    /// The next run removes what a finished run's record names, then the
    /// record; a record whose process is alive, and a line naming a path
    /// outside the temp folder, are left alone.
    func testAFinishedRunsRecordIsSweptByTheNextRun() throws {
        let temporaryURL: URL = try makeTemporaryFolder(prefix: "temp-helper-sweep")
        let outsideURL: URL = try makeTemporaryFolder(prefix: "temp-helper-outside")
        let goneProcess: Int32 = try processIdentifierThatHasGone()

        let leftFolderURL: URL = temporaryURL.appendingPathComponent("plantoir-home-under-test-\(goneProcess)")
        try FileManager.default.createDirectory(at: leftFolderURL, withIntermediateDirectories: true)
        let lockedFileURL: URL = leftFolderURL.appendingPathComponent("trail.txt")
        try "late line".write(to: lockedFileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(lchflags(lockedFileURL.path, UInt32(UF_IMMUTABLE)), 0)
        let goneRecordURL: URL = temporaryURL.appendingPathComponent(
            TemporaryFolderSweeper.runRecordPrefix + String(goneProcess)
        )
        TemporaryFolderSweeper.writeRunRecord(naming: [leftFolderURL, outsideURL], to: goneRecordURL)

        let liveFolderURL: URL = temporaryURL.appendingPathComponent("plantoir-home-under-test-1")
        try FileManager.default.createDirectory(at: liveFolderURL, withIntermediateDirectories: true)
        let liveRecordURL: URL = temporaryURL.appendingPathComponent(TemporaryFolderSweeper.runRecordPrefix + "1")
        TemporaryFolderSweeper.writeRunRecord(naming: [liveFolderURL], to: liveRecordURL)

        TemporaryFolderSweeper.removeWhatFinishedRunsLeft(
            inFolder: temporaryURL,
            exceptProcess: ProcessInfo.processInfo.processIdentifier
        )

        XCTAssertFalse(somethingIsAt(leftFolderURL.path), "the finished run's folder should be gone, locked file and all")
        XCTAssertFalse(somethingIsAt(goneRecordURL.path), "the finished run's record should be gone")
        XCTAssertTrue(somethingIsAt(outsideURL.path), "a line naming a path outside the folder is ignored")
        XCTAssertTrue(somethingIsAt(liveFolderURL.path), "a live process's folder is left alone")
        XCTAssertTrue(somethingIsAt(liveRecordURL.path), "a live process's record is left alone")
    }

    /// This run has written its own record, naming its per-run folders.
    func testThisRunHasARecordNamingItsFolders() throws {
        let recordText: String = try String(contentsOf: TemporaryFolderSweeper.runRecordURL, encoding: .utf8)
        for folderURL in TemporaryFolderSweeper.runFolders {
            XCTAssertTrue(recordText.contains(folderURL.path + "\n"), "the record should name " + folderURL.lastPathComponent)
        }
    }
}
