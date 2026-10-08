import XCTest
@testable import QuartzTeachers

/// The mirror that keeps a working folder's `.toolchain` in step with the
/// app's own copy.
///
/// Worth its own tests because it is both load-bearing and invisible: the
/// launchers hash that folder to name the image, so a mirror that copies too
/// much rebuilds the image for nothing, and one that copies too little runs
/// the teacher's site build with last week's scripts.
@MainActor
final class ToolchainMirrorTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        // NOT the temporary directory: /var is a symlink to /private/var, and
        // this suite is partly about paths that are reached through symlinks.
        // The home folder is the closest thing to a teacher's real one.
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("plantoir-mirror-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let created: URL = root
        addTeardownBlock {
            try? FileManager.default.removeItem(at: created)
        }
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Copying, and not copying

    func testItCopiesOnceAndThenLeavesEverythingAlone() throws {
        let source: URL = root.appendingPathComponent("source")
        let destination: URL = root.appendingPathComponent("destination")
        try write("one", to: source.appendingPathComponent("a.txt"))
        try write("two", to: source.appendingPathComponent("nested/b.txt"))

        XCTAssertEqual(WorkspaceModel.syncDirectory(from: source, to: destination).changed, 2)
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("nested/b.txt"), encoding: .utf8),
            "two"
        )

        XCTAssertEqual(
            WorkspaceModel.syncDirectory(from: source, to: destination).changed, 0,
            "Nothing changed, so nothing should be written — this is the pass a teacher waits through"
        )
    }

    /// The cheap check is what makes the mirror usable, so it is pinned:
    /// after a sync the copy carries the original's modification date, which
    /// is what lets the next pass answer without reading 61 MB.
    func testTheCopyKeepsTheOriginalsModificationDate() throws {
        let source: URL = root.appendingPathComponent("source")
        let destination: URL = root.appendingPathComponent("destination")
        let file: URL = source.appendingPathComponent("a.txt")
        try write("one", to: file)

        _ = WorkspaceModel.syncDirectory(from: source, to: destination)

        XCTAssertTrue(
            WorkspaceModel.filesLookIdentical(file, destination.appendingPathComponent("a.txt")),
            "The copy should be recognisable without reading it"
        )
    }

    /// Same bytes, different stamp — every file in the bundle, the first pass
    /// after the app is rebuilt. Nothing is written, and the stamp is brought
    /// across so the next pass is cheap.
    func testAFileWithTheSameBytesIsNotRewrittenButIsRestamped() throws {
        let source: URL = root.appendingPathComponent("source")
        let destination: URL = root.appendingPathComponent("destination")
        try write("same", to: source.appendingPathComponent("a.txt"))
        try write("same", to: destination.appendingPathComponent("a.txt"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: destination.appendingPathComponent("a.txt").path
        )

        XCTAssertEqual(WorkspaceModel.syncDirectory(from: source, to: destination).changed, 0)
        XCTAssertTrue(
            WorkspaceModel.filesLookIdentical(
                source.appendingPathComponent("a.txt"),
                destination.appendingPathComponent("a.txt")
            ),
            "and the next pass can tell without reading them"
        )
    }

    func testAChangedFileIsCopiedAndAnExtraOneIsRemoved() throws {
        let source: URL = root.appendingPathComponent("source")
        let destination: URL = root.appendingPathComponent("destination")
        try write("one", to: source.appendingPathComponent("a.txt"))
        _ = WorkspaceModel.syncDirectory(from: source, to: destination)

        try write("changed", to: source.appendingPathComponent("a.txt"))
        try write("stray", to: destination.appendingPathComponent("gone.txt"))

        XCTAssertEqual(WorkspaceModel.syncDirectory(from: source, to: destination).changed, 2)
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("a.txt"), encoding: .utf8),
            "changed"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("gone.txt").path),
            "An extraneous file changes the recipe's hash and rebuilds the image for nothing"
        )
    }

    // MARK: - A copy that fails is not remembered as done (#476)

    /// A destination that will not take a file counts it as failed rather
    /// than swallowing it, so the mirror can say whether the folder is up
    /// to date.
    func testAFileTheFolderWillNotTakeIsCountedAsFailed() throws {
        let source: URL = root.appendingPathComponent("source")
        let destination: URL = root.appendingPathComponent("destination")
        try write("one", to: source.appendingPathComponent("a.txt"))
        try write("two", to: source.appendingPathComponent("b.txt"))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }

        let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.syncDirectory(from: source, to: destination)
        XCTAssertEqual(outcome.failed, 2, "both writes were refused")
        XCTAssertEqual(outcome.changed, 0)
        // Whichever of the two the enumerator met first: the name and the
        // error, joined the way a problem report wants them.
        let firstFailure: String = outcome.firstFailure ?? ""
        XCTAssertTrue(
            firstFailure.hasPrefix("a.txt: ") || firstFailure.hasPrefix("b.txt: "),
            "the first file that failed, with its error: \(firstFailure)"
        )
        XCTAssertTrue(firstFailure.contains("permission"), firstFailure)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        XCTAssertEqual(WorkspaceModel.syncDirectory(from: source, to: destination), WorkspaceModel.MirrorOutcome(changed: 2, failed: 0))
    }

    /// MUST FAIL before #476: the folder was marked fresh BEFORE the copy,
    /// so a copy that failed left it marked for the rest of the run and no
    /// later reload tried again. Now the mark follows a copy with nothing
    /// failed, and the next pass retries until it gets one.
    func testAFolderWhoseCopyFailedIsNotMarkedFreshUntilACopySucceeds() throws {
        let workspace: URL = root.appendingPathComponent("workspace")
        try write("#!/bin/bash\n", to: workspace.appendingPathComponent("preview.sh"))
        let toolchain: URL = workspace.appendingPathComponent(".toolchain")
        try FileManager.default.createDirectory(at: toolchain, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: toolchain.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolchain.path)
            WorkspaceModel.foldersWithFreshToolchain.remove(workspace.path)
            WorkspaceModel.foldersWhoseToolchainCopyFailed.remove(workspace.path)
        }
        WorkspaceModel.foldersWithFreshToolchain.remove(workspace.path)
        WorkspaceModel.foldersWhoseToolchainCopyFailed.remove(workspace.path)

        WorkspaceModel.mirrorToolchain(into: workspace)
        XCTAssertFalse(
            WorkspaceModel.foldersWithFreshToolchain.contains(workspace.path),
            "MUST FAIL before #476: a copy that failed must not be remembered as done"
        )
        XCTAssertTrue(WorkspaceModel.foldersWhoseToolchainCopyFailed.contains(workspace.path), "it is remembered as failed")
        XCTAssertFalse(
            WorkspaceModel.shouldMirrorToolchain(into: workspace),
            "a routine reload does not retry — that would bring back the pause on every rename"
        )
        WorkspaceModel.forgetFailedToolchainCopy(of: workspace)
        XCTAssertTrue(WorkspaceModel.shouldMirrorToolchain(into: workspace), "File ▸ Reload Courses, or a newly pointed window, retries")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolchain.path)
        WorkspaceModel.mirrorToolchain(into: workspace)
        XCTAssertTrue(WorkspaceModel.foldersWithFreshToolchain.contains(workspace.path), "a clean copy is remembered")
        XCTAssertFalse(WorkspaceModel.foldersWhoseToolchainCopyFailed.contains(workspace.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: toolchain.appendingPathComponent("Dockerfile").path))
    }

    // MARK: - Paths reached through a symlink

    /// The bug this replaced: the enumerator hands back RESOLVED paths, so a
    /// folder reached through a symlink did not match the prefix the old
    /// arithmetic assumed. Every destination file then looked extraneous, and
    /// the mirror deleted the whole toolchain and copied it back — every
    /// single pass.
    func testAFolderReachedThroughASymlinkIsMirroredNotEmptied() throws {
        let real: URL = root.appendingPathComponent("real")
        let source: URL = root.appendingPathComponent("source")
        try write("one", to: source.appendingPathComponent("a.txt"))
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)

        let link: URL = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(WorkspaceModel.syncDirectory(from: source, to: link).changed, 1)
        XCTAssertEqual(
            WorkspaceModel.syncDirectory(from: source, to: link).changed, 0,
            "and the second pass must find nothing to do, rather than deleting what it just wrote"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.appendingPathComponent("a.txt").path))
    }

    func testRelativePathsAreFoundThroughASymlinkOrNotAtAll() throws {
        let folder: URL = root.appendingPathComponent("folder")
        XCTAssertEqual(
            WorkspaceModel.relativePath(of: folder.appendingPathComponent("a/b.txt"), under: folder),
            "a/b.txt"
        )
        XCTAssertNil(
            WorkspaceModel.relativePath(
                of: URL(fileURLWithPath: "/somewhere/else.txt"), under: folder
            ),
            "A file outside the folder is not ours to delete"
        )
    }
}
