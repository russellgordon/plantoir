import Foundation
import XCTest
@testable import QuartzTeachers

/// Temporary folders a test makes, and their removal when the test ends
/// (#978).
///
/// A full run of the suite used to leave about 280 MB of `<prefix>-<UUID>`
/// folders in the user temp folder, because a test removed its folder only on
/// the happy path, or not at all, or tried to and failed on files a reference
/// lock had marked `uchg`. A folder made through `makeTemporaryFolder(prefix:)`
/// or handed to `removeWhenTestEnds(_:)` is removed by a teardown block, which
/// XCTest runs whether the test passed, failed or threw, and the removal
/// unlocks every locked file first.
extension XCTestCase {

    // MARK: - Functions

    /// Makes an empty `<prefix>-<UUID>` folder in the user temp folder and
    /// removes it, unlocking first, when this test ends.
    func makeTemporaryFolder(prefix: String) throws -> URL {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        removeWhenTestEnds(folderURL)
        return folderURL
    }

    /// Removes a folder something else made for this test (a
    /// `FixtureWorkspace.materialize()` copy, say) when this test ends,
    /// unlocking first.
    func removeWhenTestEnds(_ folderURL: URL) {
        addTeardownBlock {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
    }
}

/// The removal itself, and the sweep for folders made where no test case is
/// in reach.
enum TemporaryFolders {

    // MARK: - Functions

    /// Clears the user flags (`uchg` among them) on the folder and everything
    /// in it, then removes it. A locked file cannot be deleted, and neither
    /// can anything inside a locked folder, so the unlocking comes first.
    static func unlockAndRemove(_ folderURL: URL) {
        let fileManager: FileManager = FileManager.default
        var isFolder: ObjCBool = false
        if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isFolder) == false {
            return
        }
        lchflags(folderURL.path, 0)
        if isFolder.boolValue {
            if let enumerator = fileManager.enumerator(atPath: folderURL.path) {
                for case let relativePath as String in enumerator {
                    let entryPath: String = folderURL.appendingPathComponent(relativePath).path
                    lchflags(entryPath, 0)
                }
            }
        }
        try? fileManager.removeItem(at: folderURL)
    }

    /// For a helper with no test case to hand (`AssistFixture.makeRunner`,
    /// a static function): the folder is removed when the test that is
    /// running now finishes, by `TemporaryFolderSweeper`.
    static func removeWhenThisTestEnds(_ folderURL: URL) {
        TemporaryFolderSweeper.register()
        TemporaryFolderSweeper.shared?.add(folderURL)
    }
}

/// Removes what `TemporaryFolders.removeWhenThisTestEnds(_:)` was handed when
/// each test finishes, and at the end of the run the four throwaway folders
/// the app itself points at while it is a test host (#978).
///
/// Those four (`RealHome.homeWhileTesting`,
/// `BuildOutputLocation.buildsRootWhileTesting`,
/// `ClaudeCodeLauncher.supportDirectoryWhileTesting` and
/// `ProblemReportStore.throwawayFolderURL`) are deliberately one per RUN, so
/// a test that writes through one door and reads back through another finds
/// what it wrote; they can only go once the last test has finished. The app
/// names them but never removes them, and changing that would be app code
/// for a test-only concern, so the test bundle does it.
///
/// Registered from the bundle's principal class (`PlantoirTestBundleSetup`).
final class TemporaryFolderSweeper: NSObject, XCTestObservation {

    // MARK: - Stored properties

    /// The one observer, once registered.
    nonisolated(unsafe) static var shared: TemporaryFolderSweeper? = nil

    /// Guards `pendingFolders`, which a test may add to from any thread.
    let lock: NSLock = NSLock()

    /// Folders to remove when the running test finishes.
    nonisolated(unsafe) var pendingFolders: [URL] = []

    // MARK: - Functions

    /// Idempotent.
    static func register() {
        if shared != nil {
            return
        }
        let made: TemporaryFolderSweeper = TemporaryFolderSweeper()
        shared = made
        XCTestObservationCenter.shared.addTestObserver(made)
    }

    func add(_ folderURL: URL) {
        lock.lock()
        pendingFolders.append(folderURL)
        lock.unlock()
    }

    /// Removes everything added during the test that just finished.
    func removePendingFolders() {
        lock.lock()
        let folders: [URL] = pendingFolders
        pendingFolders = []
        lock.unlock()
        for folderURL in folders {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        removePendingFolders()
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        removePendingFolders()
        let runFolders: [URL] = [
            RealHome.homeWhileTesting,
            BuildOutputLocation.buildsRootWhileTesting,
            ClaudeCodeLauncher.supportDirectoryWhileTesting,
            ProblemReportStore.throwawayFolderURL,
        ]
        for folderURL in runFolders {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
    }
}
