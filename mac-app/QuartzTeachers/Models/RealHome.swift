import Foundation

/// The ONE place Plantoir asks macOS where the home folder is (issue #264).
///
/// **Why one place.** Every folder Plantoir keeps things in hangs off the
/// home folder — `~/Library/Application Support/Plantoir` (builds, helper
/// programs, scheduled-publish notes, the assistant's weights),
/// `~/Library/Logs/Plantoir` (the trail), Obsidian's list of vaults, the
/// teacher's Desktop. Before this, sixteen files asked the system for it
/// directly, each its own way, and the suite was protected only where
/// somebody had noticed a test reaching the real thing and redirected that
/// one resolver (#240 found 101 such reaches in one run). A resolver added
/// next month would not have been redirected, and nothing would have said
/// so. Now there are two doors, and a source-scan test
/// (`RealHomeTripwireTests`) fails the suite if any other file asks.
///
/// - `forFiles` — the home for every path Plantoir reads, writes, or hands
///   to a child as text. The real home in the app; a throwaway folder for
///   the whole run while the unit suite is hosting this process. It needs no
///   allow-list, because it cannot reach a real folder under the suite:
///   safe by construction rather than by review.
/// - `real(for:)` — the real home, always. Only for a reach that a TEST
///   needs to see the real value of, each named by a `Use` case, and each
///   case allowed only from the files `RealHomeTripwireTests` lists beside
///   it. A new kind of real reach is therefore a new case AND a new line in
///   that table — a diff a reviewer sees.
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

    /// Why a caller needs the REAL home even while the unit suite is
    /// running. Each case is permitted only from the files named for it in
    /// `RealHomeTripwireTests.filesAllowedPerUse`; a case nothing uses fails
    /// that test as stale.
    ///
    /// **Empty, and that was measured rather than assumed.** On 2026-09-25
    /// all 27 home lookups in 15 product files were moved to `forFiles` and
    /// the full suite (1,890 tests) ran with every test outside the tripwire
    /// itself green: no test needed any of them to answer the real home. The plan had proposed ten cases, from
    /// "touches no file"; the review pointed out that the only reason for
    /// this door is a TEST that must see the real value, and there is none.
    /// So a future case is a decision somebody makes in a diff — add it
    /// here, return `systemHome` for it below, and name its files in the
    /// tripwire's table.
    enum Use: CaseIterable {
    }

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

    /// The REAL home, whoever is asking. See `Use` — which has no cases
    /// today, so nothing can call this yet, and the compiler says "will
    /// never be executed" about the `switch` below. That warning is the
    /// door being shut; it goes away with the first case, which returns
    /// `systemHome`.
    static func real(for use: Use) -> URL {
        switch use {
        }
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
