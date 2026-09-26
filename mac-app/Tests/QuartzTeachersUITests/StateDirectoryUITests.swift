import XCTest
import AppKit

/// The redirect, proved through the real app (#154): a launch through
/// `IsolatedLaunch` fills its OWN state folder and leaves the teacher's real
/// trail, preferences, agents and Application Support exactly as they were.
///
/// **Both halves, because either alone passes vacuously.** "The real files
/// did not change" is trivially true of files this runner cannot read, or of
/// an app that wrote nothing at all. So the POSITIVE controls come first —
/// the redirected trail has lines, the redirected preferences hold the
/// setting the test just changed — and every read of a real file must
/// SUCCEED, or the test fails naming the path it could not read. (The runner
/// is sandboxed, but its entitlements carry a read-only exception for `/`;
/// that is measured here on every run rather than assumed.)
///
/// **What it tolerates, by name.** AppKit and SwiftUI write their own window
/// bookkeeping straight to `UserDefaults.standard` whatever the app does —
/// `realPreferenceKeysAppKitOwns` — so those keys may change and nothing else
/// may. That residual is written down in `documentation/09-mac-app.md`.
///
/// Not opt-in: it takes seconds and needs no model, the standing of its
/// neighbours. It SKIPS when another Plantoir is running, because that copy's
/// own writes to the trail could not be told apart from a leak — and it
/// never quits the teacher's copy to make room.
final class StateDirectoryUITests: XCTestCase {

    // MARK: - Stored properties

    /// Keys AppKit and SwiftUI write to the app's standard preferences
    /// themselves, by prefix. Measured by diffing the real domain's key set
    /// around a UI run; see doc 09.
    static let realPreferenceKeysAppKitOwns: [String] = [
        "NSWindow Frame ",
        "NSSplitView Subview Frames ",
        "NSNavPanel",
        "NSNavLastRootDirectory",
        "NSOSPLastRootDirectory",
        "NSTableView ",
        "NSOutlineView ",
        "NSToolbar Configuration ",
    ]

    /// The real folders compared by name and modification time.
    static let realFoldersWatched: [String] = [
        "Library/Logs/Plantoir/runs",
        "Library/Application Support/Plantoir/scheduled",
        "Library/Application Support/Plantoir/assist",
        "Library/Application Support/Plantoir/builds",
    ]

    // MARK: - The test

    func testALaunchKeepsItsStateInItsOwnFolder() throws {
        try requireNoOtherPlantoirIsRunning()

        let before: RealStateSnapshot = try RealStateSnapshot.take()

        // Without `-assistantAsksBeforeChanging`: an argument-domain value
        // would mask the write this test watches for.
        let launch: IsolatedLaunch = try IsolatedLaunch.launch()
        let application: XCUIApplication = launch.application
        let courseRow: XCUIElement = application.outlines.staticTexts["EXC2O"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 20), "The fixture course never appeared.")

        // A setting changed twice, so the teacher's value is never at stake
        // and the redirected file must hold the key.
        application.typeKey(",", modifierFlags: .command)
        let asks: XCUIElement = application.descendants(matching: .any)
            .matching(identifier: "assistantAsksBeforeChanging").firstMatch
        XCTAssertTrue(asks.waitForExistence(timeout: 15), "Settings never showed the assistant's ask-first switch.")
        let toggle: XCUIElement = asks.checkBoxes.firstMatch.exists ? asks.checkBoxes.firstMatch : asks
        toggle.click()
        toggle.click()
        application.typeKey("w", modifierFlags: .command)

        // A section selected, so a window has something to remember.
        courseRow.click()
        application.typeKey(.rightArrow, modifierFlags: [])
        let sectionRow: XCUIElement = application.outlines.staticTexts["Section 1"]
        if sectionRow.waitForExistence(timeout: 10) {
            sectionRow.click()
        }

        // ⌘Q rather than `terminate()`, so the app's own quit path runs —
        // the one that writes the open folders and would stop containers.
        application.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(
            application.wait(for: .notRunning, timeout: 30),
            "The app did not quit on ⌘Q, so its quit path was not exercised."
        )

        // POSITIVE controls — what makes the negative half able to fail.
        XCTAssertGreaterThanOrEqual(
            launch.trailLines().count, 1,
            "Nothing in the redirected trail at \(launch.trailURL.path): the app is not keeping its trail there."
        )
        let redirectedHasTheSetting: Bool = StateDirectoryUITests.waitUntil(seconds: 10) {
            return launch.preferences()["assistantAsksBeforeChanging"] != nil
        }
        XCTAssertTrue(
            redirectedHasTheSetting,
            "The redirected preferences at \(launch.preferencesURL.path) never held assistantAsksBeforeChanging: "
            + "the app is not keeping its preferences there."
        )

        // NEGATIVE: the real state, polled for the same ten seconds, since
        // the preferences daemon writes to disk lazily.
        var after: RealStateSnapshot = try RealStateSnapshot.take()
        var differences: [String] = before.differences(from: after)
        let deadline: Date = Date().addingTimeInterval(10)
        while differences.isEmpty && Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            after = try RealStateSnapshot.take()
            differences = before.differences(from: after)
        }
        XCTAssertEqual(
            differences, [],
            "The app under test changed the teacher's REAL state. (A scheduled publish of the teacher's own that "
            + "fired during the run would also show here, as a changed file under scheduled/.)"
        )
    }

    // MARK: - Functions

    /// Skips when another Plantoir is running. Its writes to the real trail
    /// would read as a leak, and the teacher's copy is theirs to quit.
    func requireNoOtherPlantoirIsRunning() throws {
        let running: [NSRunningApplication] = NSRunningApplication.runningApplications(
            withBundleIdentifier: "ca.russellgordon.Plantoir"
        )
        if !running.isEmpty {
            throw XCTSkip(
                "Quit Plantoir first: its own writes to the trail cannot be told apart from the app under test."
            )
        }
    }

    /// Polls a condition for up to `seconds`.
    static func waitUntil(seconds: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }
}

/// The teacher's real state, by size, name and time — never contents, and
/// never attached to a result.
struct RealStateSnapshot {

    // MARK: - Stored properties

    /// Path → "size mtime", or "absent".
    var files: [String: String] = [:]

    /// The real preferences' keys and their values' descriptions, minus the
    /// keys AppKit owns.
    var preferences: [String: String] = [:]

    // MARK: - Functions

    /// Reads everything. A read that fails for any reason but "not there"
    /// throws, naming the path: an unreadable file would make "unchanged"
    /// trivially true.
    static func take() throws -> RealStateSnapshot {
        let home: URL = IsolatedLaunch.realHome()
        var snapshot: RealStateSnapshot = RealStateSnapshot()

        let trail: URL = home.appendingPathComponent("Library/Logs/Plantoir/activity.txt")
        snapshot.files[trail.path] = try describe(trail)

        for relative in StateDirectoryUITests.realFoldersWatched {
            let folder: URL = home.appendingPathComponent(relative)
            let entries: [String]
            do {
                entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            } catch let error as NSError where isMissing(error) {
                snapshot.files[folder.path] = "absent"
                continue
            } catch {
                throw RealStateUnreadable(path: folder.path, error: error)
            }
            snapshot.files[folder.path] = "\(entries.count) entries"
            for entry in entries {
                let entryURL: URL = folder.appendingPathComponent(entry)
                snapshot.files[entryURL.path] = try describe(entryURL)
            }
        }

        let agents: URL = home.appendingPathComponent("Library/LaunchAgents")
        let agentNames: [String]
        do {
            agentNames = try FileManager.default.contentsOfDirectory(atPath: agents.path)
        } catch {
            throw RealStateUnreadable(path: agents.path, error: error)
        }
        for name in agentNames where name.hasPrefix("ca.russellgordon.Plantoir") {
            let agentURL: URL = agents.appendingPathComponent(name)
            snapshot.files[agentURL.path] = try describe(agentURL)
        }

        let plist: URL = IsolatedLaunch.realPreferencesURL
        let data: Data
        do {
            data = try Data(contentsOf: plist)
        } catch {
            throw RealStateUnreadable(path: plist.path, error: error)
        }
        let parsed: Any = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dictionary: [String: Any] = (parsed as? [String: Any]) ?? [:]
        for (key, value) in dictionary {
            if isOwnedByAppKit(key) {
                continue
            }
            snapshot.preferences[key] = String(describing: value)
        }
        return snapshot
    }

    /// Everything that differs, as sentences that name the path or key but
    /// never a value's contents.
    func differences(from later: RealStateSnapshot) -> [String] {
        var result: [String] = []
        for (path, description) in files {
            let laterDescription: String = later.files[path] ?? "absent"
            if laterDescription != description {
                result.append("\(path): \(description) → \(laterDescription)")
            }
        }
        for (path, laterDescription) in later.files where files[path] == nil {
            result.append("\(path): new (\(laterDescription))")
        }
        for (key, value) in preferences {
            if later.preferences[key] != value {
                result.append("real preference \(key) changed")
            }
        }
        for (key, _) in later.preferences where preferences[key] == nil {
            result.append("real preference \(key) was added")
        }
        return result.sorted()
    }

    static func isOwnedByAppKit(_ key: String) -> Bool {
        for prefix in StateDirectoryUITests.realPreferenceKeysAppKitOwns {
            if key.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    static func describe(_ url: URL) throws -> String {
        do {
            let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: url.path)
            let size: Int = (attributes[.size] as? Int) ?? -1
            let modified: Double = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            return "\(size) bytes @ \(modified)"
        } catch let error as NSError where isMissing(error) {
            return "absent"
        } catch {
            throw RealStateUnreadable(path: url.path, error: error)
        }
    }

    static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return true
        }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return true
        }
        return false
    }
}

/// A real file the runner could not read, which fails the test rather than
/// letting "unchanged" pass for want of looking.
struct RealStateUnreadable: Error, CustomStringConvertible {
    let path: String
    let error: Error

    var description: String {
        return "Could not read \(path) (\(error.localizedDescription)); the comparison would be vacuous."
    }
}
