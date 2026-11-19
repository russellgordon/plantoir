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
    ///
    /// What this cannot close: a writer already past its read of the store.
    /// `ActivityTrail.note` reads `ActivityTrail.store` and then appends, so
    /// a note in progress on another thread when the store is put back can
    /// still append to this folder after it is removed, and make it again.
    /// The same goes for a launcher still running after the test, which was
    /// handed the folder's path as `PLANTOIR_TRAIL_DIR` by
    /// `HelperPrograms.environment`. None of the classes using this starts a
    /// launcher.
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
    /// window never shows a folder that has gone. If no resting folder can
    /// be made, the fixture is left in place and the test fails saying so.
    func removeWhenTestEndsAfterTheWindowLetsGo(_ folderURL: URL) {
        addTeardownBlock { @MainActor in
            let windowsLetGo: Bool = TemporaryFolders.pointWindowsAway(from: folderURL)
            if windowsLetGo {
                TemporaryFolders.unlockAndRemove(folderURL)
            } else {
                // No resting folder could be made, so a window still shows
                // this one. It is NOT removed (not now, not later in the
                // run, while the window may still show it): it is left
                // behind, and the test says so rather than leaking quietly.
                XCTFail(
                    "No resting folder could be made, so the fixture a window still shows was left in place: "
                        + folderURL.path
                )
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
    /// it points at is unlocked, listed or removed. Every entry is examined
    /// with `lstat` semantics (`attributesOfItem` does not follow the last
    /// component), so a dangling link is removed too.
    static func unlockAndRemove(_ folderURL: URL) {
        let fileManager: FileManager = FileManager.default
        guard let entryType = entryTypeWithoutFollowing(folderURL.path) else {
            return
        }
        if entryType == FileAttributeType.typeSymbolicLink {
            lchflags(folderURL.path, 0)
            try? fileManager.removeItem(atPath: folderURL.path)
            return
        }
        unlockWithoutFollowingLinks(folderURL.path, entryType: entryType)
        // `removeItem` removes a link inside the folder as a link.
        try? fileManager.removeItem(at: folderURL)
    }

    /// The type of the entry at `path`, the entry itself and not what a link
    /// points at; nil when nothing is there.
    static func entryTypeWithoutFollowing(_ path: String) -> FileAttributeType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[FileAttributeKey.type] as? FileAttributeType
    }

    /// Clears the flags on `path` and, if it is a real folder, on everything
    /// inside, by file descriptor (`UserFlagClearing`, shared with the UI
    /// target): the folder is opened once without following a link, and
    /// every entry inside is opened relative to it, a link as the link
    /// itself. No path is resolved twice, so an entry swapped for a link at
    /// any moment cannot lead the walk into the link's target.
    static func unlockWithoutFollowingLinks(_ path: String, entryType: FileAttributeType) {
        if entryType == FileAttributeType.typeDirectory {
            UserFlagClearing.clearFlags(inFolderAtPath: path)
            return
        }
        UserFlagClearing.clearFlags(onEntryAtPath: path)
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
/// and whatever the host makes again afterwards is removed by the NEXT run,
/// at its start, by name alone: every one of these folders ends with its
/// run's `RealHome.testRunIdentifier`, `<pid>-<UUID>`, and a folder whose
/// process has gone (`kill(pid, 0)` answers `ESRCH`) cannot be written by it
/// any more. The UUID is what makes a name belong to ONE run: a later run
/// given the same pid makes names with its own UUID, so it never writes
/// into, inherits or loses an earlier run's folders, and a folder it makes
/// while a sweep is going is not one the sweep listed.
/// Nothing is written to say what a run made, and nothing is read back.
///
/// Registered from the bundle's principal class (`PlantoirTestBundleSetup`).
final class TemporaryFolderSweeper: NSObject, XCTestObservation {

    // MARK: - Nested types

    /// One shape of run-folder name: a stem, the process id, and, when
    /// `endsWithUUID`, `-<UUID>` (every name this run makes, since the
    /// run's UUID went into all of them).
    struct RunFolderNameShape: Equatable {

        // MARK: - Stored properties

        let stem: String
        let endsWithUUID: Bool
    }

    // MARK: - Stored properties

    /// The one observer, once registered.
    nonisolated(unsafe) static var shared: TemporaryFolderSweeper? = nil

    /// Where this run's resting folder goes, named like the app's own
    /// per-run folders so it is attributable to its process.
    static let restingFolderURLForThisRun: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "plantoir-resting-folder-under-test-" + RealHome.testRunIdentifier,
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
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        removePendingFolders()
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        removePendingFolders()
        for folderURL in TemporaryFolderSweeper.runFolders {
            TemporaryFolders.unlockAndRemove(folderURL)
        }
        // Anything the host makes again after this point carries this
        // process's id in its name, and the next run removes it.
    }

    /// True when no process has this id any more. `EPERM` means one does,
    /// owned by somebody else, and any other answer means it could not be
    /// asked, so only `ESRCH` counts as gone.
    static func processHasGone(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return false
        }
        return errno == ESRCH
    }

    /// The ONE list of name shapes, read from this run's own folders
    /// (`runFolders`), which are where the names are made: so the shapes
    /// recognised can never drift from the names given. Each name is a
    /// stem, this process's id and `-<UUID>` (`RealHome.testRunIdentifier`).
    static func runFolderNameShapes() -> [RunFolderNameShape] {
        let ownProcessText: String = String(ProcessInfo.processInfo.processIdentifier)
        var shapes: [RunFolderNameShape] = []
        for folderURL in runFolders {
            var name: String = folderURL.lastPathComponent
            var endsWithUUID: Bool = false
            let uuidLength: Int = 36
            if name.count > uuidLength + 1 && isWellFormedUUID(String(name.suffix(uuidLength))) {
                name = String(name.dropLast(uuidLength))
                if name.hasSuffix("-") == false {
                    continue
                }
                name = String(name.dropLast())
                endsWithUUID = true
            }
            if name.hasSuffix("-" + ownProcessText) == false {
                continue
            }
            let stem: String = String(name.dropLast(ownProcessText.count))
            shapes.append(RunFolderNameShape(stem: stem, endsWithUUID: endsWithUUID))
        }
        return shapes
    }

    /// True for the upper-case form `UUID().uuidString` writes, and nothing
    /// else.
    static func isWellFormedUUID(_ text: String) -> Bool {
        guard let parsed = UUID(uuidString: text) else {
            return false
        }
        return parsed.uuidString == text
    }

    /// A process id written plainly: ASCII digits only, no sign, no leading
    /// zero, above 1. Nil for anything else.
    static func plainProcessIdentifier(_ text: String) -> Int32? {
        if text.isEmpty {
            return nil
        }
        for character in text {
            if character < "0" || character > "9" {
                return nil
            }
        }
        guard let processIdentifier = Int32(text) else {
            return nil
        }
        if processIdentifier <= 1 || String(processIdentifier) != text {
            return nil
        }
        return processIdentifier
    }

    /// The process id in `name` when the WHOLE name is one of the run-folder
    /// shapes; nil for anything else (`.`, `..`, a truncated name, extra
    /// text, a pid with a sign or a leading zero, an unrelated entry).
    static func processIdentifier(inRunFolderNamed name: String) -> Int32? {
        for shape in runFolderNameShapes() {
            if name.hasPrefix(shape.stem) == false {
                continue
            }
            let rest: String = String(name.dropFirst(shape.stem.count))
            if shape.endsWithUUID {
                guard let dashIndex = rest.firstIndex(of: "-") else {
                    continue
                }
                let processText: String = String(rest[rest.startIndex..<dashIndex])
                let uuidText: String = String(rest[rest.index(after: dashIndex)...])
                if isWellFormedUUID(uuidText) == false {
                    continue
                }
                if let processIdentifier = plainProcessIdentifier(processText) {
                    return processIdentifier
                }
            } else {
                if let processIdentifier = plainProcessIdentifier(rest) {
                    return processIdentifier
                }
            }
        }
        return nil
    }

    /// Removes every entry directly in `folder` whose NAME is a run-folder
    /// shape for a process that has gone. This process's own, and any whose
    /// process is alive (a run still going, or an unrelated process that
    /// has been given a reused pid) or cannot be asked about, are left.
    /// Nothing is read from any file; nothing but names is looked at; the
    /// entry is removed without following a link.
    ///
    /// Two runs going at once under one account (a gate and another test
    /// run) each leave the other's folders, because the other is alive. A
    /// new run given a dead run's pid after the check below makes names
    /// with its own UUID, which are not in the listing being worked through.
    static func removeWhatFinishedRunsLeft(inFolder folder: URL, exceptProcess ownProcess: Int32) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return
        }
        for name in names {
            guard let processIdentifier = processIdentifier(inRunFolderNamed: name) else {
                continue
            }
            if processIdentifier == ownProcess {
                continue
            }
            if processHasGone(processIdentifier) == false {
                continue
            }
            TemporaryFolders.unlockAndRemove(URL(fileURLWithPath: folder.path + "/" + name))
        }
    }
}
