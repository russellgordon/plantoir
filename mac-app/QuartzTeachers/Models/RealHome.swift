import Foundation

/// The ONE place Plantoir asks macOS where the home folder is (issue #264).
///
/// **Why one place.** Every folder Plantoir keeps things in hangs off the
/// home folder — `~/Library/Application Support/Plantoir` (builds, helper
/// programs, scheduled-publish notes, the assistant's weights),
/// `~/Library/Logs/Plantoir` (the trail), Obsidian's list of vaults, the
/// teacher's Desktop. Before this, 15 product files asked the system for it
/// directly — 27 lookups, each its own way — and the suite was protected
/// only where somebody had noticed a test reaching the real thing and
/// redirected that one resolver. #240's probe counted 482 reaches of the
/// real `~/Library` in one run before its fix and 101 left after it. A
/// resolver added next month would not have been redirected, and nothing
/// would have said so. Now there is one door, and a source-scan test
/// (`RealHomeTripwireTests`) fails the suite if any other file asks.
///
/// `forFiles` is the home for every path Plantoir reads, writes, or hands
/// to a child as text: the real home in the app, a throwaway folder for the
/// whole run while the unit suite is hosting this process. It needs no
/// allow-list, because it cannot reach a real folder under the suite — safe
/// by construction rather than by review.
///
/// **There is no second door for "the real home, even under the suite".**
/// One was built (an enum of named uses, each allowed only from listed
/// files) and deleted in review: with every lookup moved to `forFiles`, the
/// full suite needed none of them to answer the real value, so the door was
/// empty and could only ever have been called by nothing. If a test ever
/// genuinely needs one, it is a new function here and a line in the
/// tripwire, made in a diff somebody reviews.
///
/// **Three answers, in this order** (`home(isInsideTestBundle:stateDirectory:systemHome:)`):
/// the hosted unit suite gets a throwaway home keyed on XCTest being loaded
/// in THIS process; an app launched with `--state-dir <absolute path>` gets
/// that folder as its home (#154); everything else gets the real one. The
/// flag is how a UI test keeps the app it drives out of the teacher's trail,
/// preferences and Application Support: that app has no XCTest in it, so the
/// first answer never reaches it. The flag is EXPLICIT — `UITEST_WORKSPACE`
/// alone still gets the real home, because the marketing captures drive the
/// real toolchain and need it — and a source scan
/// (`UITestLaunchTripwireTests`) keeps every other UI test on the flag. The
/// opt-in rollover test used to rely on the real home to find the
/// assistant's weights; it now links them into the state folder one file at
/// a time instead (`IsolatedLaunch`).
///
/// Preferences cannot hang off this home — `cfprefsd` resolves the home
/// itself — so they have a sibling door, `PlantoirDefaults`, which reads the
/// SAME state folder. One flag, one root, two doors.
///
/// The three folders #240 moved for the UI-tested app — built websites,
/// scheduled-publish notes, the assistant's launch files — ask
/// `keepsTestStateInThrowawayFolders` before they get here: under a state
/// folder they answer the real rule inside it, so everything the app keeps
/// is under the one root a test can inspect.
///
/// **What this cannot see** is written down in `documentation/09-mac-app.md`
/// → "Testing: the real-home tripwire": a child process takes `HOME` from
/// its environment, not from here, and a path spelt out in full without any
/// home lookup is invisible to a scan.
nonisolated enum RealHome {

    // MARK: - Stored properties

    /// True when XCTest is loaded into this process — the unit suite, whose
    /// host IS the app. False in the app a UI test launches: XCTest is in
    /// the UI test's runner, a separate process, and not in the app it
    /// drives. The one definition; `WorkspaceModel.isRunningTests` and
    /// `ProblemReportStore.isRunningTests` ask it.
    static let isInsideTestBundle: Bool = NSClassFromString("XCTestCase") != nil

    /// The one throwaway home for a whole test run, so a test that writes
    /// through one resolver and reads back through another still finds what
    /// it wrote. Never created here: it exists only once something writes
    /// into it.
    static let homeWhileTesting: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "plantoir-home-under-test-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )

    /// The flag that hands the app a folder to use as its home (#154). The
    /// same word Windows' app answers, where it replaces one app folder;
    /// here it replaces the home, because the mac's state is spread across
    /// four `~/Library` folders.
    static let stateDirectoryFlag: String = "--state-dir"

    /// The folder `--state-dir` named, or nil when the flag was not given.
    /// A malformed flag never gets this far: `QuartzTeachersApp.init` asks
    /// `stateDirectory(fromArguments:)` first and exits 64, so a redirect
    /// that silently did not happen cannot report success.
    static let stateDirectory: URL? = try? stateDirectory(fromArguments: ProcessInfo.processInfo.arguments)

    /// True in the app a UI test launches — the ONE reading of
    /// `UITEST_WORKSPACE`. `WorkspaceModel`, `WindowFolderMemory` and
    /// `BuildOutputLocation.isRunningTests` all ask it, rather than each
    /// reading the environment in its own way.
    static let isUnderUITest: Bool = ProcessInfo.processInfo.environment["UITEST_WORKSPACE"] != nil

    /// What is wrong with a `--state-dir` that cannot be used.
    enum StateDirectoryProblem: Error, Equatable {
        case missingValue
        case notAbsolute(String)
        case givenMoreThanOnce

        /// The sentence a developer reads on stderr before the app exits.
        var explanation: String {
            switch self {
            case .missingValue:
                return "--state-dir needs a folder after it."
            case .notAbsolute(let value):
                return "--state-dir needs an absolute path (starting with /), not \"\(value)\"."
            case .givenMoreThanOnce:
                return "--state-dir was given more than once; pass one folder."
            }
        }
    }

    // MARK: - Computed properties

    /// The home folder for anything Plantoir reads, writes, or names to a
    /// child process: the real one in the app, the throwaway one under the
    /// unit suite.
    static var forFiles: URL {
        return home(isInsideTestBundle: isInsideTestBundle, stateDirectory: stateDirectory, systemHome: systemHome)
    }

    /// True when this process keeps its state anywhere but the real home:
    /// under the unit suite, or launched with `--state-dir`. What refuses
    /// the Mac-wide things a redirect cannot move — notifications, the
    /// updater — asks this.
    static var isRedirected: Bool {
        return isInsideTestBundle || stateDirectory != nil
    }

    /// Whether the folders #240 moved to a throwaway place should still be
    /// there, for this process.
    static var keepsTestStateInThrowawayFolders: Bool {
        return keepsTestStateInThrowawayFolders(
            isInsideTestBundle: isInsideTestBundle,
            isUnderUITest: isUnderUITest,
            stateDirectory: stateDirectory
        )
    }

    /// The system's answer, asked in exactly one line of the product.
    private static var systemHome: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Functions

    /// Reads `--state-dir <folder>` out of a command line.
    ///
    /// Absent is nil. A flag with nothing after it, a value that does not
    /// start with `/`, or the flag twice all throw: an ambiguous or relative
    /// redirect is refused rather than guessed at. `~` is NOT expanded —
    /// that would be a second way to ask for a home inside the one function
    /// that is supposed to replace it, and a harness passes absolute paths.
    static func stateDirectory(fromArguments arguments: [String]) throws -> URL? {
        var found: URL? = nil
        var index: Int = 0
        while index < arguments.count {
            if arguments[index] == stateDirectoryFlag {
                if found != nil {
                    throw StateDirectoryProblem.givenMoreThanOnce
                }
                let valueIndex: Int = index + 1
                if valueIndex >= arguments.count {
                    throw StateDirectoryProblem.missingValue
                }
                let value: String = arguments[valueIndex]
                if value.isEmpty || value.hasPrefix("-") {
                    throw StateDirectoryProblem.missingValue
                }
                if !value.hasPrefix("/") {
                    throw StateDirectoryProblem.notAbsolute(value)
                }
                found = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
                index = valueIndex
            }
            index += 1
        }
        return found
    }

    /// Which home a process uses — the rule `forFiles` applies, as a pure
    /// function. The unit suite wins over a state folder, so a hosted run
    /// that somehow carried the flag still cannot leave its throwaway home.
    static func home(isInsideTestBundle: Bool, stateDirectory: URL?, systemHome: URL) -> URL {
        if isInsideTestBundle {
            return homeWhileTesting
        }
        if let stateDirectory {
            return stateDirectory
        }
        return systemHome
    }

    /// The rule behind `keepsTestStateInThrowawayFolders`, as a pure
    /// function. The unit suite: always. A state folder: never — it IS the
    /// place for them, and the one a test inspects. A UI test without one
    /// (the marketing captures): yes, as #240 left it.
    static func keepsTestStateInThrowawayFolders(
        isInsideTestBundle: Bool,
        isUnderUITest: Bool,
        stateDirectory: URL?
    ) -> Bool {
        if isInsideTestBundle {
            return true
        }
        if stateDirectory != nil {
            return false
        }
        return isUnderUITest
    }

    /// A path a teacher (or Claude Code) typed, with a leading `~` meaning
    /// the home folder: `~` alone, or `~/` and the rest.
    ///
    /// Written out rather than `NSString.expandingTildeInPath`, so that
    /// under the suite a typed `~/Sites` lands in the throwaway home instead
    /// of the real one. The other form `expandingTildeInPath` accepts,
    /// `~name/…` for ANOTHER account's home, is left as typed: nobody
    /// publishes a class website into a colleague's home folder, and
    /// resolving one would be a second way to ask the system for a home.
    static func expandingTilde(in path: String) -> String {
        if path == "~" {
            return forFiles.path
        }
        if path.hasPrefix("~/") {
            return forFiles.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
