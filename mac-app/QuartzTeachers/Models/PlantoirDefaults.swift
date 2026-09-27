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
/// save panels — which goes to `UserDefaults.standard` directly. That is
/// written down in `documentation/09-mac-app.md` → "Testing: the UI target
/// keeps its state in `--state-dir`".
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

    // MARK: - Functions

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
