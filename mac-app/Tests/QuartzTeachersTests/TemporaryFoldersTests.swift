import Darwin
import Foundation
import XCTest
@testable import QuartzTeachers

/// The test helper that removes the suite's temporary folders
/// (`TemporaryFolders.swift`, #978 and its follow-ups) is itself tested here:
/// a symbolic link handed to it never reaches its target, things that point
/// at a folder let go before it is removed, and a finished run's folders are
/// recognised by name alone and removed by the next run.
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

    /// Starts a child process that stays alive until this test ends, and
    /// returns its id: a live process other than this one.
    func startLiveChildProcess() throws -> Int32 {
        let child: Process = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["600"]
        try child.run()
        addTeardownBlock {
            child.terminate()
            child.waitUntilExit()
        }
        return child.processIdentifier
    }

    /// A scratch folder standing in for the temp folder, with a sentinel
    /// file in it, so a sweep that reached the folder itself would show.
    func makeScratchTemporaryFolder() throws -> (folder: URL, sentinel: URL) {
        let folderURL: URL = try makeTemporaryFolder(prefix: "temp-helper-sweep")
        let sentinelURL: URL = folderURL.appendingPathComponent("sentinel.txt")
        try "still here".write(to: sentinelURL, atomically: true, encoding: .utf8)
        return (folderURL, sentinelURL)
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

    /// Every shape a run makes, for a process that has gone: removed,
    /// locked files and all. The sentinel beside them stays.
    func testAFinishedRunsFoldersAreRemovedByName() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        var madeURLs: [URL] = []
        for name in [
            "plantoir-home-under-test-\(goneProcess)",
            "plantoir-builds-under-test-\(goneProcess)",
            "plantoir-assist-under-test-\(goneProcess)",
            "plantoir-resting-folder-under-test-\(goneProcess)",
            "Plantoir-tests-\(goneProcess)-\(UUID().uuidString)",
        ] {
            madeURLs.append(try makeLockedFolder(named: name, in: scratch.folder))
        }

        sweep(scratch.folder)

        for madeURL in madeURLs {
            XCTAssertFalse(somethingIsAt(madeURL.path), madeURL.lastPathComponent + " should be gone")
        }
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path))
    }

    /// A live process's folders (a child this test keeps alive, standing for
    /// a run still going or a reused pid) and this run's own are left.
    func testALiveProcessesAndThisRunsFoldersAreLeft() throws {
        let scratch = try makeScratchTemporaryFolder()
        let liveProcess: Int32 = try startLiveChildProcess()
        XCTAssertFalse(TemporaryFolderSweeper.processHasGone(liveProcess))
        let ownProcess: Int32 = ProcessInfo.processInfo.processIdentifier
        var keptURLs: [URL] = []
        for processIdentifier in [liveProcess, ownProcess] {
            keptURLs.append(try makeLockedFolder(named: "plantoir-home-under-test-\(processIdentifier)", in: scratch.folder))
            keptURLs.append(try makeLockedFolder(
                named: "Plantoir-tests-\(processIdentifier)-\(UUID().uuidString)", in: scratch.folder
            ))
        }

        sweep(scratch.folder)

        for keptURL in keptURLs {
            XCTAssertTrue(somethingIsAt(keptURL.path), keptURL.lastPathComponent + " should be left alone")
        }
    }

    /// Names that are not exactly a run-folder shape with a plain pid: a
    /// sign, a leading zero, 0, 1, non-digits, extra text, a truncated name,
    /// the old pid-less `Plantoir-tests-<UUID>`, a bad or lower-case UUID,
    /// and an unrelated entry. All left.
    func testANameThatIsNotExactlyARunFolderIsLeft() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let uuidText: String = UUID().uuidString
        let names: [String] = [
            "plantoir-home-under-test-+\(goneProcess)",
            "plantoir-home-under-test--\(goneProcess)",
            "plantoir-home-under-test-0\(goneProcess)",
            "plantoir-home-under-test-0",
            "plantoir-home-under-test-1",
            "plantoir-home-under-test-abc",
            "plantoir-home-under-test-\(goneProcess)x",
            "plantoir-home-under-test-\(goneProcess).old",
            "plantoir-home-under-test-",
            "plantoir-home-under-te",
            "Plantoir-tests-\(uuidText)",
            "Plantoir-tests-\(goneProcess)-not-a-uuid",
            "Plantoir-tests-\(goneProcess)-\(uuidText.lowercased())",
            "Plantoir-tests-\(goneProcess)-\(uuidText)-extra",
            "Plantoir-tests-0\(goneProcess)-\(uuidText)",
            "somebody-elses-folder-under-test-\(goneProcess)",
        ]
        var keptURLs: [URL] = []
        for name in names {
            keptURLs.append(try makeLockedFolder(named: name, in: scratch.folder))
        }

        sweep(scratch.folder)

        for keptURL in keptURLs {
            XCTAssertTrue(somethingIsAt(keptURL.path), keptURL.lastPathComponent + " should be left alone")
        }
        XCTAssertTrue(somethingIsAt(scratch.sentinel.path))
    }

    /// A plain file at a matching name is removed as a file; a link at one,
    /// pointing at a folder of locked files, is removed as a link and its
    /// target keeps every file and flag.
    func testAFileOrALinkAtARunFolderNameIsNeverFollowed() throws {
        let scratch = try makeScratchTemporaryFolder()
        let goneProcess: Int32 = try processIdentifierThatHasGone()
        let fileURL: URL = scratch.folder.appendingPathComponent("plantoir-assist-under-test-\(goneProcess)")
        try "a file, not a folder".write(to: fileURL, atomically: true, encoding: .utf8)
        let targetURL: URL = try makeLockedFolder(named: "link-target", in: try makeTemporaryFolder(prefix: "temp-helper-target"))
        let lockedFileURL: URL = targetURL.appendingPathComponent("trail.txt")
        let linkURL: URL = scratch.folder.appendingPathComponent("plantoir-builds-under-test-\(goneProcess)")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: targetURL.path)

        sweep(scratch.folder)

        XCTAssertFalse(somethingIsAt(fileURL.path), "the file should be gone")
        XCTAssertFalse(somethingIsAt(linkURL.path), "the link itself should be gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedFileURL.path), "the link's target must not be touched")
        XCTAssertNotEqual(userFlags(atPath: lockedFileURL.path) & UInt32(UF_IMMUTABLE), 0, "the target must stay locked")
    }

    /// An empty folder: nothing to do, nothing goes wrong.
    func testAnEmptyFolderIsSweptWithoutTrouble() throws {
        let folderURL: URL = try makeTemporaryFolder(prefix: "temp-helper-empty")

        sweep(folderURL)

        XCTAssertTrue(somethingIsAt(folderURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folderURL.path), [])
    }

    /// The shapes are read from this run's own folders, where the names are
    /// made: four that end in the pid and one that adds a UUID. Every run
    /// folder of this run is recognised as this run's.
    func testTheSweepKnowsTheRunsFolderNames() {
        let shapes: [TemporaryFolderSweeper.RunFolderNameShape] = TemporaryFolderSweeper.runFolderNameShapes()
        XCTAssertEqual(shapes.count, 5, "home, builds, assistant support, the resting folder and the trail")
        XCTAssertTrue(shapes.contains(TemporaryFolderSweeper.RunFolderNameShape(stem: "plantoir-home-under-test-", endsWithUUID: false)))
        XCTAssertTrue(shapes.contains(TemporaryFolderSweeper.RunFolderNameShape(stem: "Plantoir-tests-", endsWithUUID: true)))
        let ownProcess: Int32 = ProcessInfo.processInfo.processIdentifier
        for folderURL in TemporaryFolderSweeper.runFolders {
            XCTAssertEqual(
                TemporaryFolderSweeper.processIdentifier(inRunFolderNamed: folderURL.lastPathComponent), ownProcess,
                folderURL.lastPathComponent + " should be recognised as this run's"
            )
        }
        XCTAssertNil(TemporaryFolderSweeper.processIdentifier(inRunFolderNamed: "."))
        XCTAssertNil(TemporaryFolderSweeper.processIdentifier(inRunFolderNamed: ".."))
        XCTAssertNil(TemporaryFolderSweeper.processIdentifier(inRunFolderNamed: "plantoir-home-under-test-12345/.."))
        XCTAssertEqual(TemporaryFolderSweeper.processIdentifier(inRunFolderNamed: "plantoir-home-under-test-12345"), 12_345)
    }
}
