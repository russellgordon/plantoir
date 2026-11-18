import Darwin
import XCTest

/// What `UITestFolders` will and will not remove (#978). Launches nothing,
/// so it needs no screen; it runs with the rest of the UI target.
final class UITestFoldersTests: XCTestCase {

    // MARK: - Computed properties

    var temporaryFolderURL: URL {
        return FileManager.default.temporaryDirectory
    }

    // MARK: - Functions

    /// A folder outside the two removable names, removed when this test
    /// ends, flags cleared first. Made here, so its path is one this test
    /// built.
    func makeScratchFolder() throws -> URL {
        let folderURL: URL = temporaryFolderURL.appendingPathComponent("uitestfolders-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        addTeardownBlock {
            if let enumerator = FileManager.default.enumerator(atPath: folderURL.path) {
                for case let relativePath as String in enumerator {
                    lchflags(folderURL.appendingPathComponent(relativePath).path, 0)
                }
            }
            try? FileManager.default.removeItem(at: folderURL)
        }
        return folderURL
    }

    /// A file holding `text`, locked with `uchg`.
    func writeLockedFile(at fileURL: URL, text: String) throws {
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chflags(fileURL.path, UInt32(UF_IMMUTABLE)), 0, "Could not lock \(fileURL.path).")
    }

    func flagsOf(_ fileURL: URL) -> UInt32 {
        var status: stat = stat()
        if lstat(fileURL.path, &status) != 0 {
            return 0
        }
        return status.st_flags
    }

    // MARK: - Tests

    func testOnlyTheTwoNamesDirectlyInTheTempFolderAreRemovable() {
        let uuid: String = UUID().uuidString
        XCTAssertTrue(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("cq4t-fixture-\(uuid)")))
        XCTAssertTrue(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("plantoir-state-\(uuid)")))

        XCTAssertFalse(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("cq4t-fixture-\(uuid.lowercased())")))
        XCTAssertFalse(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("cq4t-fixture-\(uuid)-extra")))
        XCTAssertFalse(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("cq4t-fixture-")))
        XCTAssertFalse(UITestFolders.isRemovableName(temporaryFolderURL.appendingPathComponent("cq4t-init-\(uuid)")))
        XCTAssertFalse(UITestFolders.isRemovableName(temporaryFolderURL))
        XCTAssertFalse(UITestFolders.isRemovableName(
            temporaryFolderURL.appendingPathComponent("plantoir-state-\(uuid)").appendingPathComponent("cq4t-fixture-\(uuid)")
        ))
        XCTAssertFalse(UITestFolders.isRemovableName(
            temporaryFolderURL.deletingLastPathComponent().appendingPathComponent("cq4t-fixture-\(uuid)")
        ))
    }

    /// A link with a removable name, pointing at a folder holding a locked
    /// file, is left alone and so is everything it points at.
    func testALinkWithARemovableNameIsNotFollowed() throws {
        let targetURL: URL = try makeScratchFolder()
        let lockedURL: URL = targetURL.appendingPathComponent("locked.txt")
        try writeLockedFile(at: lockedURL, text: "keep")
        let linkURL: URL = temporaryFolderURL.appendingPathComponent("cq4t-fixture-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: linkURL.path)
        }

        UITestFolders.unlockAndRemove(linkURL)

        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), "The link itself was removed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedURL.path), "A file behind the link was removed.")
        XCTAssertNotEqual(flagsOf(lockedURL) & UInt32(UF_IMMUTABLE), 0, "A file behind the link was unlocked.")
    }

    /// A real fixture folder is removed, locked entries and all, and a link
    /// inside it goes as a link: the locked file it points at stays, locked.
    func testAFixtureGoesAndALinkInsideItGoesAsALink() throws {
        let outsideURL: URL = try makeScratchFolder()
        let outsideFileURL: URL = outsideURL.appendingPathComponent("weights.gguf")
        try writeLockedFile(at: outsideFileURL, text: "weights")

        let fixtureURL: URL = temporaryFolderURL.appendingPathComponent("cq4t-fixture-\(UUID().uuidString)")
        let innerURL: URL = fixtureURL.appendingPathComponent("courses/EXC2O")
        addTeardownBlock {
            UITestFolders.unlockAndRemove(fixtureURL)
        }
        try FileManager.default.createDirectory(at: innerURL, withIntermediateDirectories: true)
        try writeLockedFile(at: innerURL.appendingPathComponent("locked.md"), text: "page")
        XCTAssertEqual(chflags(innerURL.path, UInt32(UF_IMMUTABLE)), 0)
        try FileManager.default.createSymbolicLink(
            at: fixtureURL.appendingPathComponent("models-link.gguf"), withDestinationURL: outsideFileURL
        )
        try FileManager.default.createSymbolicLink(
            at: fixtureURL.appendingPathComponent("folder-link"), withDestinationURL: outsideURL
        )

        UITestFolders.unlockAndRemove(fixtureURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtureURL.path), "The fixture was not removed.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFileURL.path), "The file a link pointed at was removed.")
        XCTAssertNotEqual(flagsOf(outsideFileURL) & UInt32(UF_IMMUTABLE), 0, "The file a link pointed at was unlocked.")
    }

    /// A folder with any other name is never removed, even when handed in.
    func testAnotherNameIsNeverRemoved() throws {
        let otherURL: URL = try makeScratchFolder()
        UITestFolders.unlockAndRemove(otherURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherURL.path))
    }
    /// The preferences folder is built by the app's rule from the state
    /// folder, and only that exact shape under `/private/tmp` is removable.
    func testThePreferencesFolderIsTheAppsShapeAndOnlyThatIsRemovable() {
        let stateURL: URL = temporaryFolderURL.appendingPathComponent("plantoir-state-\(UUID().uuidString)")
        let preferencesURL: URL = UITestFolders.preferencesFolder(forStateDirectory: stateURL)
        XCTAssertEqual(preferencesURL.deletingLastPathComponent().path, "/private/tmp")
        XCTAssertTrue(preferencesURL.lastPathComponent.hasPrefix("plantoir-state-preferences-"))
        XCTAssertTrue(UITestFolders.isRemovableName(preferencesURL))
        XCTAssertNotEqual(preferencesURL, UITestFolders.preferencesFolder(
            forStateDirectory: temporaryFolderURL.appendingPathComponent("plantoir-state-\(UUID().uuidString)")
        ))

        let tmp: URL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        XCTAssertFalse(UITestFolders.isRemovableName(tmp))
        XCTAssertFalse(UITestFolders.isRemovableName(tmp.appendingPathComponent("plantoir-state-preferences-0123456789ABCDEF")))
        XCTAssertFalse(UITestFolders.isRemovableName(tmp.appendingPathComponent("plantoir-state-preferences-0123456789abcde")))
        XCTAssertFalse(UITestFolders.isRemovableName(tmp.appendingPathComponent("plantoir-state-preferences-0123456789abcdef0")))
        XCTAssertFalse(UITestFolders.isRemovableName(tmp.appendingPathComponent("cq4t-fixture-\(UUID().uuidString)")))
        XCTAssertFalse(UITestFolders.isRemovableName(
            temporaryFolderURL.appendingPathComponent("plantoir-state-preferences-0123456789abcdef")
        ))
        XCTAssertFalse(UITestFolders.isRemovableName(
            tmp.appendingPathComponent("x").appendingPathComponent("plantoir-state-preferences-0123456789abcdef")
        ))
    }

    /// A process is matched by a launch folder in its arguments, as the
    /// folder itself or a path inside it, never by a longer name that only
    /// starts the same way.
    func testAProcessIsMatchedOnlyByTheLaunchsOwnFolder() {
        let stateURL: URL = temporaryFolderURL.appendingPathComponent("plantoir-state-\(UUID().uuidString)")
        let modelArgument: String = stateURL.path + "/Library/Application Support/Plantoir/models/small.gguf"
        XCTAssertTrue(LaunchProcesses.argumentsName(["llama-server", "--model", modelArgument], folder: stateURL.path))
        XCTAssertTrue(LaunchProcesses.argumentsName(["Plantoir", "--state-dir", stateURL.path], folder: stateURL.path))
        XCTAssertFalse(LaunchProcesses.argumentsName(["llama-server", "--model", stateURL.path + "X/m.gguf"], folder: stateURL.path))
        XCTAssertFalse(LaunchProcesses.argumentsName(
            ["llama-server", "--model", "/Users/teacher/Library/Application Support/Plantoir/models/small.gguf"],
            folder: stateURL.path
        ))
    }

    /// The runner can read a process's arguments from the kernel: its own,
    /// at least, which is what the matching above is fed.
    func testTheRunnerCanReadAProcesssArguments() {
        let ownArguments: [String] = LaunchProcesses.arguments(ofProcess: getpid())
        XCTAssertFalse(ownArguments.isEmpty, "KERN_PROCARGS2 gave nothing for this runner")
        XCTAssertFalse(LaunchProcesses.processIdentifiersOfThisAccount().isEmpty)
        XCTAssertEqual(LaunchProcesses.processes(naming: [temporaryFolderURL.appendingPathComponent("plantoir-state-\(UUID().uuidString)").path]), [])
    }
}
