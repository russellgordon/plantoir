import Darwin
import XCTest

/// The folders a UI test makes, and their removal when the test ends
/// (#978, the UI target).
///
/// A UI test makes two kinds of folder in its runner's temp folder, which
/// is inside the runner's sandbox container
/// (`~/Library/Containers/ca.russellgordon.QuartzTeachersUITests.xctrunner/Data/tmp`):
/// `cq4t-fixture-<UUID>` working folders (`FixtureWorkspace.materialize()`,
/// about 68 MB each once the app has copied its website builder in) and
/// `IsolatedLaunch`'s `plantoir-state-<UUID>` state folders. Until this
/// file, nothing removed either: measured on the main Mac on 2026-11-18,
/// 717 and 151 of them, 1.9 GB.
///
/// **Order, never a delay.** The app under test is a separate process that
/// writes into both folders (the trail, the website builder it mirrors into
/// the working folder) until it ends. So when a test finishes, every copy of
/// the app it launched is quit first, and only when XCTest reports it
/// `.notRunning` are that test's folders removed. If the app will not
/// quit, its folders are left where they are, and the run says so on the
/// console, rather than being removed out from under a running app.
///
/// **What may be removed.** Only a folder this run registered, at a path
/// this code built, and only when, at removal time, it is still exactly
/// `<temp folder>/<one of the two prefixes>-<UUID>` and still a real folder,
/// examined without following a symbolic link. A path is never read back
/// from a file or the environment: the working folder named by
/// `UITEST_WORKSPACE` belongs to whoever set it and is never registered.
/// Inside a folder, nothing is followed: a link (the assistant's weights are
/// linked into a state folder one file at a time) is removed as a link, and
/// the file it points at is not touched.
///
/// The work happens in `testCaseDidFinish`, after the test's `tearDown`
/// (which reaps any stub launcher it started), whether the test passed,
/// failed, threw or skipped.
final class UITestFolders: NSObject, XCTestObservation {

    // MARK: - Stored properties

    /// The one observer, once registered.
    nonisolated(unsafe) static var shared: UITestFolders? = nil

    /// The prefixes a folder this file may remove starts with.
    static let fixturePrefix: String = "cq4t-fixture-"
    static let statePrefix: String = "plantoir-state-"

    /// How long a launched app is given to end once asked. A ceiling on a
    /// wait for a state XCTest reports, not a pause: the wait ends the
    /// moment the app has gone.
    static let quitTimeout: TimeInterval = 30

    /// Folders to remove when the running test finishes.
    var pendingFolders: [URL] = []

    /// Apps launched during the running test, quit before its folders go.
    var launchedApplications: [XCUIApplication] = []

    // MARK: - Computed properties

    /// The runner's temp folder, the only parent a removable folder has.
    static var temporaryFolderURL: URL {
        return FileManager.default.temporaryDirectory
    }

    // MARK: - Functions

    /// Idempotent. Registered on first use rather than from a principal
    /// class: the UI target has none, and a test that never launches or
    /// makes a fixture has nothing to remove.
    static func register() {
        if shared != nil {
            return
        }
        let made: UITestFolders = UITestFolders()
        shared = made
        XCTestObservationCenter.shared.addTestObserver(made)
    }

    /// A fresh `FixtureWorkspace` copy, removed when the running test ends.
    /// Every UI test makes its fixture through here rather than calling
    /// `FixtureWorkspace.materialize()` itself, which is shared with the unit
    /// target and registers nothing.
    static func makeFixture() throws -> URL {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        removeWhenThisTestEnds(fixtureURL)
        return fixtureURL
    }

    /// Registers a folder this run made for removal when the running test
    /// ends. One that is not a name this file may remove is refused here,
    /// loudly, so a mistake shows the day it is made.
    static func removeWhenThisTestEnds(_ folderURL: URL) {
        guard isRemovableName(folderURL) else {
            XCTFail("UITestFolders will not remove \(folderURL.path): only <temp>/\(fixturePrefix)<UUID> and <temp>/\(statePrefix)<UUID> folders this run made.")
            return
        }
        register()
        shared?.pendingFolders.append(folderURL)
    }

    /// Registers a launched app, to be quit before the running test's folders
    /// are removed.
    static func quitWhenThisTestEnds(_ application: XCUIApplication) {
        register()
        shared?.launchedApplications.append(application)
    }

    /// True when the folder sits directly in the runner's temp folder and its
    /// name is one of the two prefixes followed by an upper-case UUID and
    /// nothing else. Pure: it checks the spelling, not the disk.
    static func isRemovableName(_ folderURL: URL) -> Bool {
        let parentPath: String = folderURL.deletingLastPathComponent().standardizedFileURL.path
        if parentPath != temporaryFolderURL.standardizedFileURL.path {
            return false
        }
        let name: String = folderURL.lastPathComponent
        for prefix in [fixturePrefix, statePrefix] {
            if name.hasPrefix(prefix) {
                let rest: String = String(name.dropFirst(prefix.count))
                if let parsed = UUID(uuidString: rest), parsed.uuidString == rest {
                    return true
                }
            }
        }
        return false
    }

    /// True when the entry at the path is a real folder, examined with
    /// `lstat`, so a symbolic link (to a folder or not) is never one.
    static func isRealFolder(atPath path: String) -> Bool {
        var status: stat = stat()
        if lstat(path, &status) != 0 {
            return false
        }
        return (status.st_mode & S_IFMT) == S_IFDIR
    }

    /// Clears the user flags on the folder and everything in it, without
    /// following a link, then removes it. A locked (`uchg`) entry cannot be
    /// deleted, and the app's reference locks set that flag.
    static func unlockAndRemove(_ folderURL: URL) {
        let path: String = folderURL.path
        guard isRemovableName(folderURL), isRealFolder(atPath: path) else {
            return
        }
        lchflags(path, 0)
        // A directory enumerator lists a link as an entry and does not
        // descend through it; `lchflags` changes the link itself.
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let relativePath as String in enumerator {
                lchflags(folderURL.appendingPathComponent(relativePath).path, 0)
            }
        }
        // `removeItem` removes a link inside the folder as a link.
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            print("UITestFolders could not remove \(path): \(error.localizedDescription)")
        }
    }

    /// Quits every app this test launched, then, if they have all gone,
    /// removes this test's folders. On the main actor, where XCTest calls
    /// its observers and where `XCUIApplication` lives.
    @MainActor
    func quitThenRemove() {
        let applications: [XCUIApplication] = launchedApplications
        let folders: [URL] = pendingFolders
        launchedApplications = []
        pendingFolders = []

        var everyAppHasGone: Bool = true
        for application in applications {
            if application.state != .notRunning {
                application.terminate()
            }
            if application.wait(for: .notRunning, timeout: UITestFolders.quitTimeout) == false {
                everyAppHasGone = false
            }
        }
        if everyAppHasGone == false {
            var paths: [String] = []
            for folderURL in folders {
                paths.append(folderURL.path)
            }
            print("UITestFolders left \(folders.count) folder(s) because the app under test did not quit: \(paths)")
            return
        }
        for application in applications {
            if IsolatedLaunch.lastLaunched === application {
                // It has been quit; a later test has nothing of this one to end.
                IsolatedLaunch.lastLaunched = nil
            }
        }
        for folderURL in folders {
            UITestFolders.unlockAndRemove(folderURL)
        }
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        MainActor.assumeIsolated {
            UITestFolders.shared?.quitThenRemove()
        }
    }
}
