import Darwin
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
///
/// **Order, never a delay.** XCTest runs teardown blocks last-registered
/// first, and all of them BEFORE the class's own `tearDown`. So anything
/// that must stop pointing at a folder before it goes (the trail store, a
/// window) lets go in a block registered AFTER the removal, or in the same
/// block ahead of it: `useThrowawayTrail(prefix:)` and
/// `removeWhenTestEndsAfterTheWindowLetsGo(_:)` (#978 follow-ups).
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
    ///
    /// Runs before the class's `tearDown`. A folder something still points
    /// at until `tearDown` (the trail store, a window) needs one of the two
    /// helpers below instead.
    func removeWhenTestEnds(_ folderURL: URL) {
        addTeardownBlock {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
    }

    /// Points `ActivityTrail.store` at a fresh `<prefix>-<UUID>` folder for
    /// this test. When the test ends the previous store comes back FIRST and
    /// the folder goes after, so no late trail line can land in (and
    /// recreate) a folder that has just been removed.
    ///
    /// Two teardown blocks, registered removal first: XCTest runs them last
    /// registered first, so the restore runs before the removal whatever the
    /// test's outcome.
    @discardableResult
    func useThrowawayTrail(prefix: String) -> URL {
        let previousStore: ProblemReportStore = ActivityTrail.store
        let trailFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        removeWhenTestEnds(trailFolderURL)
        addTeardownBlock {
            ActivityTrail.store = previousStore
        }
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolderURL)
        return trailFolderURL
    }

    /// For a fixture shown in the app's own window
    /// (`WorkspaceModel.windowModels`): when this test ends, every window
    /// still showing it is first pointed at the run's resting folder, and
    /// only then is the fixture removed. One block, in that order, so the
    /// window never shows a folder that has gone.
    func removeWhenTestEndsAfterTheWindowLetsGo(_ folderURL: URL) {
        addTeardownBlock { @MainActor in
            let windowsLetGo: Bool = TemporaryFolders.pointWindowsAway(from: folderURL)
            if windowsLetGo {
                TemporaryFolders.unlockAndRemove(folderURL)
            } else {
                // No resting folder could be made, so a window may still
                // show this one: leave it for the end of the run.
                TemporaryFolders.removeWhenThisTestEnds(folderURL)
            }
        }
    }
}

/// The removal itself, and the sweep for folders made where no test case is
/// in reach.
enum TemporaryFolders {

    // MARK: - Stored properties

    /// The folder windows are pointed at when a test's fixture is about to
    /// go: a fixture copy of its own, made once per run on first need and
    /// removed with the run's other folders.
    @MainActor static var restingFolderURL: URL? = nil

    // MARK: - Functions

    /// Clears the user flags (`uchg` among them) on the folder and everything
    /// in it, then removes it. A locked file cannot be deleted, and neither
    /// can anything inside a locked folder, so the unlocking comes first.
    ///
    /// A symbolic link handed in is removed as a link: nothing in the folder
    /// it points at is unlocked, listed or removed. The link is examined
    /// with `lstat` semantics (`attributesOfItem` does not follow the last
    /// component), so a dangling link is removed too.
    static func unlockAndRemove(_ folderURL: URL) {
        let fileManager: FileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: folderURL.path) else {
            return
        }
        let entryType: FileAttributeType? = attributes[FileAttributeKey.type] as? FileAttributeType
        if entryType == FileAttributeType.typeSymbolicLink {
            lchflags(folderURL.path, 0)
            try? fileManager.removeItem(atPath: folderURL.path)
            return
        }
        lchflags(folderURL.path, 0)
        if entryType == FileAttributeType.typeDirectory {
            // The enumerator does not descend through a symbolic link inside
            // the folder, and `lchflags` on one changes the link itself.
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

    /// Points every window showing `folderURL` at the resting folder.
    /// False only when a window shows it and no resting folder could be
    /// made, in which case the window still shows it.
    @MainActor
    static func pointWindowsAway(from folderURL: URL) -> Bool {
        var windowsShowingIt: [WorkspaceModel] = []
        for model in WorkspaceModel.windowModels {
            if let shownURL = model.workspaceURL {
                if FolderIdentity.isSameFolder(shownURL.path, folderURL.path) {
                    windowsShowingIt.append(model)
                }
            }
        }
        if windowsShowingIt.isEmpty {
            return true
        }
        guard let restingURL = makeRestingFolderIfNeeded() else {
            return false
        }
        for model in windowsShowingIt {
            model.chooseWorkspace(at: restingURL)
        }
        return true
    }

    /// The run's resting folder, made on first need.
    @MainActor
    static func makeRestingFolderIfNeeded() -> URL? {
        if let restingFolderURL {
            return restingFolderURL
        }
        guard let fixtureURL = try? FixtureWorkspace.materialize() else {
            return nil
        }
        let restingURL: URL = TemporaryFolderSweeper.restingFolderURLForThisRun
        TemporaryFolders.unlockAndRemove(restingURL)
        do {
            try FileManager.default.moveItem(at: fixtureURL, to: restingURL)
        } catch {
            TemporaryFolders.unlockAndRemove(fixtureURL)
            return nil
        }
        restingFolderURL = restingURL
        return restingURL
    }
}

/// Removes what `TemporaryFolders.removeWhenThisTestEnds(_:)` was handed when
/// each test finishes, and the per-run folders: the four the app itself
/// points at while it is a test host (#978), and the resting folder windows
/// are pointed at between tests.
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
/// **No point inside a run is after the host's last write.** The test host
/// IS the app, and it keeps running (its timers, its tasks, a launcher it
/// started) after `testBundleDidFinish`, the last callback the bundle gets.
/// So the run's folders are removed there, which catches nearly everything,
/// AND named in a run record, `plantoir-run-record-under-test-<pid>`, which
/// is left behind on purpose. The next run, at its start, reads every record
/// whose process has gone (`kill(pid, 0)` answers `ESRCH`) and removes the
/// folders it names, then the record: by then the old host cannot write
/// anything. A run therefore leaves one record of a few hundred bytes, plus
/// whatever its host wrote after the bundle finished, until the next run on
/// the same Mac.
///
/// Registered from the bundle's principal class (`PlantoirTestBundleSetup`).
final class TemporaryFolderSweeper: NSObject, XCTestObservation {

    // MARK: - Stored properties

    /// The one observer, once registered.
    nonisolated(unsafe) static var shared: TemporaryFolderSweeper? = nil

    /// The name every run record starts with; the process id follows.
    static let runRecordPrefix: String = "plantoir-run-record-under-test-"

    /// Where this run's resting folder goes, named like the app's own
    /// per-run folders so it is attributable to its process.
    static let restingFolderURLForThisRun: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "plantoir-resting-folder-under-test-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )

    /// Guards `pendingFolders`, which a test may add to from any thread.
    let lock: NSLock = NSLock()

    /// Folders to remove when the running test finishes.
    nonisolated(unsafe) var pendingFolders: [URL] = []

    // MARK: - Computed properties

    /// Every folder that belongs to this run as a whole.
    static var runFolders: [URL] {
        return [
            RealHome.homeWhileTesting,
            BuildOutputLocation.buildsRootWhileTesting,
            ClaudeCodeLauncher.supportDirectoryWhileTesting,
            ProblemReportStore.throwawayFolderURL,
            restingFolderURLForThisRun,
        ]
    }

    /// This run's record.
    static var runRecordURL: URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(runRecordPrefix + String(ProcessInfo.processInfo.processIdentifier))
    }

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

    func testBundleWillStart(_ testBundle: Bundle) {
        TemporaryFolderSweeper.removeWhatFinishedRunsLeft(
            inFolder: FileManager.default.temporaryDirectory,
            exceptProcess: ProcessInfo.processInfo.processIdentifier
        )
        TemporaryFolderSweeper.writeRunRecord(
            naming: TemporaryFolderSweeper.runFolders,
            to: TemporaryFolderSweeper.runRecordURL
        )
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        removePendingFolders()
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        removePendingFolders()
        for folderURL in TemporaryFolderSweeper.runFolders {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
        // The run record stays: the next run removes anything the host
        // writes after this point, once this process has gone.
    }

    /// Writes one path per line.
    static func writeRunRecord(naming folders: [URL], to recordURL: URL) {
        var text: String = ""
        for folderURL in folders {
            text += folderURL.path + "\n"
        }
        try? text.write(to: recordURL, atomically: true, encoding: .utf8)
    }

    /// True when no process has this id any more. `EPERM` means one does,
    /// owned by somebody else, so only `ESRCH` counts as gone.
    static func processHasGone(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return false
        }
        return errno == ESRCH
    }

    /// Removes, for every run record in `folder` whose process has gone,
    /// the folders it names and then the record. A record names only
    /// folders directly inside `folder`; any other line is ignored.
    static func removeWhatFinishedRunsLeft(inFolder folder: URL, exceptProcess ownProcess: Int32) {
        let fileManager: FileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return
        }
        for name in names {
            if name.hasPrefix(runRecordPrefix) == false {
                continue
            }
            let processText: String = String(name.dropFirst(runRecordPrefix.count))
            guard let processIdentifier = Int32(processText) else {
                continue
            }
            if processIdentifier == ownProcess {
                continue
            }
            if processHasGone(processIdentifier) == false {
                continue
            }
            let recordURL: URL = folder.appendingPathComponent(name)
            let recordText: String = (try? String(contentsOf: recordURL, encoding: .utf8)) ?? ""
            let folderPath: String = folder.standardizedFileURL.path
            for line in recordText.components(separatedBy: "\n") {
                if line.isEmpty {
                    continue
                }
                let namedURL: URL = URL(fileURLWithPath: line)
                if namedURL.deletingLastPathComponent().standardizedFileURL.path != folderPath {
                    continue
                }
                TemporaryFolders.unlockAndRemove(namedURL)
            }
            try? fileManager.removeItem(at: recordURL)
        }
    }
}
