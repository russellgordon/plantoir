import Foundation

/// The ONE place Plantoir picks its preferences store (#154).
///
/// **Why a door of its own.** Every other folder Plantoir keeps things in
/// hangs off `RealHome.forFiles`, so `--state-dir` moves them by moving the
/// home. Preferences do not: `cfprefsd` resolves the home itself, and
/// measured on 2026-09-26, `CFFIXED_USER_HOME` moved Foundation's home but a
/// preferences write still landed in the REAL `~/Library/Preferences`. What
/// does work, measured the same day, is a suite named by an absolute path:
/// `UserDefaults(suiteName: "/abs/…/ca.russellgordon.Plantoir")` writes
/// `/abs/…/ca.russellgordon.Plantoir.plist`, creating the folders on the
/// way, and still sees the argument domain (`-assistantAsksBeforeChanging
/// YES`) and the global domain (`NSQuitAlwaysKeepsWindows`).
///
/// So this door reads the SAME state folder `RealHome` does: one flag, one
/// root, two doors. Without the flag, `shared` IS `UserDefaults.standard`,
/// so every `=== UserDefaults.standard` guard in the product keeps its
/// meaning under the unit suite.
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

    /// The app's preferences domain.
    static let domainName: String = "ca.russellgordon.Plantoir"

    /// The store every product preference is read from and written to.
    ///
    /// `UserDefaults` is thread-safe (Apple documents it so) but not marked
    /// `Sendable` in this SDK; the value is set once and never replaced.
    nonisolated(unsafe) static let shared: UserDefaults = makeStore(stateDirectory: RealHome.stateDirectory)

    // MARK: - Functions

    /// `<state>/Library/Preferences/ca.russellgordon.Plantoir` — without
    /// `.plist`, which the path suite adds itself (measured).
    static func preferencesPath(inStateDirectory stateDirectory: URL) -> String {
        return stateDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent(domainName)
            .path
    }

    /// The store for a process: the standard one without a state folder, a
    /// preferences file inside the folder with one.
    static func makeStore(stateDirectory: URL?) -> UserDefaults {
        guard let stateDirectory else {
            return UserDefaults.standard
        }
        let path: String = preferencesPath(inStateDirectory: stateDirectory)
        if let store = UserDefaults(suiteName: path) {
            return store
        }
        // A path suite is refused only for the app's own bundle identifier,
        // which a path never is. Should it ever be refused, the real store is
        // NOT the fallback: a redirected run writing the teacher's
        // preferences is the failure this door exists to prevent.
        preconditionFailure("Plantoir could not open its preferences at \(path)")
    }
}
