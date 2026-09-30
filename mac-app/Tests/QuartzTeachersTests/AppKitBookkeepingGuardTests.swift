import AppKit
import XCTest
@testable import QuartzTeachers

/// A run a test drives puts AppKit's own preference keys back the moment they
/// change (#361): the unit gate used to leave the teacher's main window at
/// `InAppUserInterfaceTests`' 1100×720, and a UI run moved it again.
@MainActor
final class AppKitBookkeepingGuardTests: XCTestCase {

    // MARK: - Stored properties

    private static let prefixes: [String] = PlantoirDefaults.appKitOwnedKeyPrefixes

    // MARK: - The decision

    /// Armed for the unit suite, a UI test's isolated launch and a marketing
    /// capture — and NEVER for a teacher, whose every window move would
    /// otherwise be undone the moment it was saved.
    func testOnlyARunATestDrivesIsGuarded() {
        for inside in [false, true] {
            for underUITest in [false, true] {
                for stateDirectory in [false, true] {
                    let guarded: Bool = PlantoirDefaults.guardsAppKitBookkeeping(
                        isInsideTestBundle: inside, isUnderUITest: underUITest, hasStateDirectory: stateDirectory
                    )
                    let expected: Bool = inside || underUITest || stateDirectory
                    XCTAssertEqual(guarded, expected, "inside \(inside), UI test \(underUITest), state \(stateDirectory)")
                }
            }
        }
        XCTAssertFalse(
            PlantoirDefaults.guardsAppKitBookkeeping(isInsideTestBundle: false, isUnderUITest: false, hasStateDirectory: false),
            "A teacher's own run must never put their window frames back"
        )
    }

    // MARK: - The repairs

    func testAChangedFrameIsPutBackAnAddedKeyRemovedAndTheTeachersSettingsLeftAlone() {
        let snapshot: [String: Any] = [
            "NSWindow Frame main-AppWindow-1": "1711 46 1100 720 1512 -98 1920 1049 ",
            "NSTableView Columns x": ["a", "b"],
            "assistantAsksBeforeChanging": true,
        ]
        let current: [String: Any] = [
            "NSWindow Frame main-AppWindow-1": "40 60 1512 948 1512 -98 1920 1049 ",
            "NSTableView Columns x": ["a", "b"],
            "NSSplitView Subview Frames main-AppWindow-1, SidebarNavigationSplitView": ["0 0 200 700"],
            "assistantAsksBeforeChanging": false,
            "somethingNew": 3,
        ]
        let needed: (putBack: [String: Any], remove: [String]) = PlantoirDefaults.repairs(
            snapshot: snapshot, current: current, prefixes: AppKitBookkeepingGuardTests.prefixes
        )
        XCTAssertEqual(needed.putBack.keys.sorted(), ["NSWindow Frame main-AppWindow-1"])
        XCTAssertEqual(needed.putBack["NSWindow Frame main-AppWindow-1"] as? String, "1711 46 1100 720 1512 -98 1920 1049 ")
        XCTAssertEqual(needed.remove, ["NSSplitView Subview Frames main-AppWindow-1, SidebarNavigationSplitView"])
    }

    func testAnAppKitKeyThatWasRemovedIsWrittenBackAndNothingChangedMeansNothingToDo() {
        let snapshot: [String: Any] = ["NSNavLastRootDirectory": "/Users/teacher/Documents"]
        let removed: (putBack: [String: Any], remove: [String]) = PlantoirDefaults.repairs(
            snapshot: snapshot, current: [:], prefixes: AppKitBookkeepingGuardTests.prefixes
        )
        XCTAssertEqual(removed.putBack["NSNavLastRootDirectory"] as? String, "/Users/teacher/Documents")
        let unchanged: (putBack: [String: Any], remove: [String]) = PlantoirDefaults.repairs(
            snapshot: snapshot, current: snapshot, prefixes: AppKitBookkeepingGuardTests.prefixes
        )
        XCTAssertTrue(unchanged.putBack.isEmpty)
        XCTAssertTrue(unchanged.remove.isEmpty)
    }

    // MARK: - The wiring, against a store of its own

    /// A write through the store is put back at once — by the change
    /// notification, not only at quit. Never `UserDefaults.standard`: a path
    /// suite under `/private/tmp`, the only place the daemon honours one.
    func testAWriteIsPutBackTheMomentItHappens() throws {
        let folder: String = PlantoirDefaults.honouredParent + "/plantoir-guard-test-\(UUID().uuidString)"
        let path: String = folder + "/preferences"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let store: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: path))
        store.set("1 2 300 400 0 0 1512 982 ", forKey: "NSWindow Frame test")
        store.set("left alone", forKey: "teacherSetting")

        let guardian: AppKitBookkeepingGuard = AppKitBookkeepingGuard(
            store: store, domainName: path, prefixes: AppKitBookkeepingGuardTests.prefixes
        )
        XCTAssertEqual(
            guardian.snapshot["NSWindow Frame test"] as? String, "1 2 300 400 0 0 1512 982 ",
            "The guard's snapshot should come from the store's persistent domain"
        )
        guardian.start()
        defer { guardian.stop() }

        store.set("9 9 999 999 0 0 1512 982 ", forKey: "NSWindow Frame test")
        store.set("changed by the teacher", forKey: "teacherSetting")
        store.set("new", forKey: "NSToolbar Configuration test")
        let restored: Bool = AppKitBookkeepingGuardTests.waitUntil(seconds: 2) {
            let domain: [String: Any] = store.persistentDomain(forName: path) ?? [:]
            return domain["NSWindow Frame test"] as? String == "1 2 300 400 0 0 1512 982 "
                && domain["NSToolbar Configuration test"] == nil
        }
        XCTAssertTrue(restored, "The frame was not put back, or the added key not removed: \(store.persistentDomain(forName: path) ?? [:])")
        XCTAssertGreaterThanOrEqual(guardian.repairsMade, 2)
        XCTAssertEqual(store.string(forKey: "teacherSetting"), "changed by the teacher", "A setting of ours was touched")
    }

    // MARK: - Step 0, measured in the app itself

    /// The unit host IS Plantoir, and its main window autosaves under the
    /// real `NSWindow Frame main-AppWindow-1`. Resizing it here is what used
    /// to leave 1100×720 in the teacher's preferences on every unit gate. The
    /// guard is armed for this process, so the saved value must come back to
    /// what it was — and `repairsMade` must grow, proving AppKit wrote and
    /// the guard answered (a resize that wrote nothing would pass the value
    /// check on its own).
    func testResizingTheHostsMainWindowLeavesTheRealFrameAsItWas() throws {
        let guardian: AppKitBookkeepingGuard = try XCTUnwrap(
            AppKitBookkeepingGuard.armed, "The unit host is a test run, so the guard should be armed"
        )
        var mainWindow: NSWindow? = nil
        for window in NSApp.windows where window.frameAutosaveName.hasPrefix("main-AppWindow") {
            mainWindow = window
        }
        guard let window = mainWindow else {
            throw XCTSkip("No main window in this host (a hidden or locked session, #315), so nothing to resize.")
        }
        let key: String = "NSWindow Frame " + window.frameAutosaveName
        let identifier: String = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let before: Any? = guardian.store.persistentDomain(forName: identifier)?[key]
        let repairsBefore: Int = guardian.repairsMade
        let original: NSRect = window.frame

        let changes: ChangeCounter = ChangeCounter()
        let observer: NSObjectProtocol = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: guardian.store, queue: nil
        ) { _ in
            changes.count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        window.setFrame(
            NSRect(x: original.minX + 13, y: original.minY, width: original.width + 37, height: original.height - 11),
            display: true
        )
        let actedAndRestored: Bool = AppKitBookkeepingGuardTests.waitUntil(seconds: 3) {
            let now: Any? = guardian.store.persistentDomain(forName: identifier)?[key]
            let same: Bool = (now == nil && before == nil) || (now as AnyObject?)?.isEqual(before) == true
            return guardian.repairsMade > repairsBefore && same
        }
        window.setFrame(original, display: true)
        print("#361 step 0: didChangeNotification posted \(changes.count) time(s); repairs \(repairsBefore) → \(guardian.repairsMade)")
        XCTAssertGreaterThan(changes.count, 0, "AppKit's frame save did not post didChangeNotification in-process")
        XCTAssertTrue(
            actedAndRestored,
            "The real \(key) was not put back while the app ran (repairs \(repairsBefore) → \(guardian.repairsMade))"
        )
    }

    // MARK: - Functions

    static func waitUntil(seconds: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}

/// Counts notifications from a closure the notification centre may call on
/// any thread.
final class ChangeCounter: @unchecked Sendable {

    // MARK: - Stored properties

    var count: Int = 0
}
