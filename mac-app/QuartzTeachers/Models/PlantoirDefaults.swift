import AppKit
import CryptoKit
import Foundation

/// The ONE place Plantoir picks its preferences store (#154).
///
/// **Why a door of its own.** Every other folder Plantoir keeps things in
/// hangs off `RealHome.forFiles`, so `--state-dir` moves them by moving the
/// home. Preferences do not: `cfprefsd` resolves the home itself, and
/// measured on 2026-09-26, `CFFIXED_USER_HOME` moved Foundation's home but a
/// preferences write still landed in the REAL `~/Library/Preferences`. What
/// does work is a suite named by an absolute path under `/private/tmp` — and
/// ONLY there (`honouredParent`): it writes `<path>.plist`, creating the
/// folders on the way, and still sees the argument domain
/// (`-assistantAsksBeforeChanging YES`) and the global domain
/// (`NSQuitAlwaysKeepsWindows`).
///
/// So this door reads the SAME flag `RealHome` does — one flag, two doors —
/// but its file lives beside the state folder rather than inside it, and a
/// note inside the state folder (`locationNoteName`) says where. Without the
/// flag, `shared` IS `UserDefaults.standard`, so every
/// `=== PlantoirDefaults.shared` guard in the product keeps its meaning under
/// the unit suite.
///
/// **What still writes the real domain** under a state folder is AppKit and
/// SwiftUI's own bookkeeping — window frames, split-view positions, open and
/// save panels — which goes to `UserDefaults.standard` directly, whatever
/// store we pick. Since #361 (v1.4.1) a run a test drives puts each of those
/// keys back the moment it changes (`AppKitBookkeepingGuard`, below), so the
/// teacher's main window no longer opens at the size the last test left.
/// `documentation/09-mac-app.md` → "Testing: the UI target keeps its state in
/// `--state-dir`" says what it covers and what was rejected.
///
/// A source scan (`PreferencesSeamTripwireTests`) fails the suite if any
/// other product file names `UserDefaults.standard`, opens a suite, or
/// declares an `@AppStorage` without `store: PlantoirDefaults.shared`.
nonisolated enum PlantoirDefaults {

    // MARK: - Stored properties

    /// Where the preferences of a state-folder run live: a folder in
    /// `/private/tmp` named after the state folder, NOT inside it.
    ///
    /// **Measured, 2026-09-26, and this is the trap.** A path suite is only
    /// honoured by the preferences daemon for SOME paths. Under
    /// `/private/tmp` it writes the file at the path. Under the home folder
    /// (a UI runner's temp folder is inside its container, inside the home)
    /// or under the per-user temp folder in `/var/folders`, it silently
    /// writes `~/Library/Preferences/<last component>.plist` instead — the
    /// REAL preferences folder — and when that last component is the app's
    /// own identifier it writes the teacher's real domain itself. The
    /// planner's probe used a path that happened to be honoured.
    static let honouredParent: String = "/private/tmp"

    /// The file this run's store leaves inside the state folder, naming where
    /// its preferences went, so a test can find them without re-deriving the
    /// rule.
    static let locationNoteName: String = "plantoir-preferences-location.txt"

    /// The store every product preference is read from and written to.
    ///
    /// `UserDefaults` is thread-safe (Apple documents it so) but not marked
    /// `Sendable` in this SDK; the value is set once and never replaced.
    nonisolated(unsafe) static let shared: UserDefaults = makeStore(stateDirectory: RealHome.stateDirectory)

    /// The preference keys AppKit and SwiftUI write for themselves, by
    /// prefix — measured by diffing the real domain's key set around a UI
    /// run (doc 09). Only these are ever put back by
    /// `AppKitBookkeepingGuard`: the teacher's own settings are not ours to
    /// undo.
    static let appKitOwnedKeyPrefixes: [String] = [
        "NSWindow Frame ",
        "NSSplitView Subview Frames ",
        "NSNavPanel",
        "NSNavLastRootDirectory",
        "NSOSPLastRootDirectory",
        "NSTableView ",
        "NSOutlineView ",
        "NSToolbar Configuration ",
    ]

    // MARK: - Functions

    /// Whether this run puts AppKit's own bookkeeping back (#361): when a test
    /// drives it — the unit suite (whose host IS the app), a UI test's
    /// isolated launch (`--state-dir`), or a marketing capture
    /// (`UITEST_WORKSPACE`). NEVER for a teacher: armed, every window move,
    /// split-view drag and open-panel folder would be undone the moment it
    /// was saved, and nothing would say so. A pure function, so a test pins
    /// "no flags → false" (`AppKitBookkeepingGuardTests`).
    static func guardsAppKitBookkeeping(isInsideTestBundle: Bool, isUnderUITest: Bool,
                                        hasStateDirectory: Bool) -> Bool {
        if isInsideTestBundle {
            return true
        }
        if isUnderUITest {
            return true
        }
        if hasStateDirectory {
            return true
        }
        return false
    }

    /// Whether a key is one AppKit keeps for itself.
    static func isOwnedByAppKit(_ key: String, prefixes: [String]) -> Bool {
        for prefix in prefixes {
            if key.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    /// What must be done to a preferences domain to put AppKit's keys back as
    /// they were: values to write again (changed or removed since), and keys
    /// to remove (added since). Keys outside `prefixes` are never named.
    static func repairs(snapshot: [String: Any], current: [String: Any],
                        prefixes: [String]) -> (putBack: [String: Any], remove: [String]) {
        var putBack: [String: Any] = [:]
        var remove: [String] = []
        for (key, value) in snapshot where isOwnedByAppKit(key, prefixes: prefixes) {
            if let now = current[key] {
                if !(now as AnyObject).isEqual(value) {
                    putBack[key] = value
                }
            } else {
                putBack[key] = value
            }
        }
        for (key, _) in current where isOwnedByAppKit(key, prefixes: prefixes) {
            if snapshot[key] == nil {
                remove.append(key)
            }
        }
        remove.sort()
        return (putBack: putBack, remove: remove)
    }

    /// `/private/tmp/plantoir-state-preferences-<16 hex of the state
    /// folder's path>/preferences` — without `.plist`, which the path suite
    /// adds itself. The hash keeps two state folders apart and keeps the
    /// name free of anything the daemon could read as an identifier.
    static func preferencesPath(inStateDirectory stateDirectory: URL) -> String {
        let digest: SHA256.Digest = SHA256.hash(data: Data(stateDirectory.standardizedFileURL.path.utf8))
        var hex: String = ""
        for byte in digest {
            hex += String(format: "%02x", byte)
        }
        let folder: String = honouredParent + "/plantoir-state-preferences-" + String(hex.prefix(16))
        return folder + "/preferences"
    }

    /// The store for a process: the standard one without a state folder, a
    /// preferences file inside the folder with one.
    static func makeStore(stateDirectory: URL?) -> UserDefaults {
        guard let stateDirectory else {
            return UserDefaults.standard
        }
        let path: String = preferencesPath(inStateDirectory: stateDirectory)
        if let store = UserDefaults(suiteName: path) {
            let noteFolder: URL = stateDirectory.appendingPathComponent("Library/Preferences", isDirectory: true)
            try? FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
            try? (path + ".plist").write(
                to: noteFolder.appendingPathComponent(locationNoteName), atomically: true, encoding: .utf8
            )
            return store
        }
        // A path suite is refused only for the app's own bundle identifier,
        // which a path never is. Should it ever be refused, the real store is
        // NOT the fallback: a redirected run writing the teacher's
        // preferences is the failure this door exists to prevent.
        preconditionFailure("Plantoir could not open its preferences at \(path)")
    }
}

/// Puts AppKit's own preference keys back the moment they change, in a run a
/// test drives (#361).
///
/// **Why.** `--state-dir` moves every preference Plantoir writes
/// (`PlantoirDefaults.shared`), but AppKit and SwiftUI write their window
/// frames, split-view positions and open-panel folders through
/// `UserDefaults.standard` themselves, into the app's REAL domain — the same
/// one a teacher's copy reads. The unit gate's `InAppUserInterfaceTests`
/// resized the teacher's main window to 1100×720 on every run, and a UI run
/// moved it again (#361, 2026-09-27). No public API points AppKit's writes
/// elsewhere, so this lets them happen and undoes them.
///
/// **How.** At launch — from `applicationWillFinishLaunching`, before any
/// window exists and so before AppKit's first write — it copies the AppKit
/// keys of the PERSISTENT domain (never `dictionaryRepresentation`, which
/// would take an argument-domain frame a test passed for the saved one). On
/// every `UserDefaults.didChangeNotification` for its store it compares again
/// and writes back what changed; our own write posts the notification again
/// and finds nothing to do. A last pass runs at `willTerminate`.
///
/// **Its honest limit.** The domain is shared with any other copy of Plantoir
/// running as the same user, so a frame the teacher's own copy saves WHILE a
/// test app runs is put back too, the next time anything in the test app
/// writes. Only AppKit's keys, only during that overlap.
@MainActor
final class AppKitBookkeepingGuard {

    // MARK: - Stored properties

    /// The guard this process armed, if any. Held so it lives as long as the app.
    static private(set) var armed: AppKitBookkeepingGuard?

    let store: UserDefaults
    let domainName: String
    let prefixes: [String]

    /// The AppKit keys as they were when the guard was armed.
    let snapshot: [String: Any]

    /// How many keys it has put back or removed, for a test to see that it
    /// acted rather than that nothing happened.
    private(set) var repairsMade: Int = 0

    private var isRepairing: Bool = false
    private var observers: [NSObjectProtocol] = []

    // MARK: - Initializer

    init(store: UserDefaults, domainName: String, prefixes: [String]) {
        self.store = store
        self.domainName = domainName
        self.prefixes = prefixes
        let domain: [String: Any] = store.persistentDomain(forName: domainName) ?? [:]
        var owned: [String: Any] = [:]
        for (key, value) in domain where PlantoirDefaults.isOwnedByAppKit(key, prefixes: prefixes) {
            owned[key] = value
        }
        self.snapshot = owned
    }

    // MARK: - Functions

    /// Arms the guard on the real domain when a test is driving this run.
    /// Idempotent.
    ///
    /// Called ONLY from `AppDelegate.applicationWillFinishLaunching`, never
    /// from `QuartzTeachersApp.init`: `RealHome.isInsideTestBundle` is a
    /// `static let`, worked out once on first read, and in the unit host
    /// XCTest may not be loaded yet at `init` — a read there could freeze it
    /// false for the whole process and point the unit suite at the real home
    /// (#361's plan review, S1). `applicationWillFinishLaunching` is where #212
    /// already relies on it, and it still runs before any window exists.
    static func armIfATestIsDrivingThisRun() {
        if armed != nil {
            return
        }
        let wanted: Bool = PlantoirDefaults.guardsAppKitBookkeeping(
            isInsideTestBundle: RealHome.isInsideTestBundle,
            isUnderUITest: RealHome.isUnderUITest,
            hasStateDirectory: RealHome.stateDirectory != nil
        )
        guard wanted, let identifier = Bundle.main.bundleIdentifier else {
            return
        }
        let made: AppKitBookkeepingGuard = AppKitBookkeepingGuard(
            store: UserDefaults.standard, domainName: identifier, prefixes: PlantoirDefaults.appKitOwnedKeyPrefixes
        )
        made.start()
        armed = made
    }

    /// Starts watching the store, and the app's quit.
    func start() {
        let center: NotificationCenter = NotificationCenter.default
        let changed: NSObjectProtocol = center.addObserver(
            forName: UserDefaults.didChangeNotification, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repairNow()
            }
        }
        observers.append(changed)
        let quitting: NSObjectProtocol = center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repairNow()
            }
        }
        observers.append(quitting)
    }

    /// Stops watching. For a test's own guard; the app's lives until it quits.
    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    /// Puts every changed AppKit key back as it was at launch.
    func repairNow() {
        if isRepairing {
            return
        }
        isRepairing = true
        defer { isRepairing = false }
        let current: [String: Any] = store.persistentDomain(forName: domainName) ?? [:]
        let needed: (putBack: [String: Any], remove: [String]) = PlantoirDefaults.repairs(
            snapshot: snapshot, current: current, prefixes: prefixes
        )
        for (key, value) in needed.putBack {
            store.set(value, forKey: key)
            repairsMade += 1
        }
        for key in needed.remove {
            store.removeObject(forKey: key)
            repairsMade += 1
        }
    }
}
