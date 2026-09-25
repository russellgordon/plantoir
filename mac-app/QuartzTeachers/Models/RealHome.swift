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
/// **Keyed on XCTest being loaded in THIS process**, not on
/// `BuildOutputLocation.isRunningTests`, which is also true inside the app a
/// UI test drives (it reads `UITEST_WORKSPACE`). That app has no XCTest in
/// it, and the opt-in `AssistantRolloverUITests` needs it to find the real
/// assistant weights, so moving its home would break the one test that
/// exercises a real model. The three folders that were already moved for the
/// UI-tested app too — built websites, scheduled-publish notes, the
/// assistant's launch files — keep doing that in their own resolvers, which
/// check `isRunningTests` before they get here.
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

    // MARK: - Computed properties

    /// The home folder for anything Plantoir reads, writes, or names to a
    /// child process: the real one in the app, the throwaway one under the
    /// unit suite.
    static var forFiles: URL {
        if isInsideTestBundle {
            return homeWhileTesting
        }
        return systemHome
    }

    /// The system's answer, asked in exactly one line of the product.
    private static var systemHome: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Functions

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
