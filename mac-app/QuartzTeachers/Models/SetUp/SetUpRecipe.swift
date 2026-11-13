import Foundation

/// Everything Plantoir needs to know to set up ONE program from its maker
/// (#855): where the maker's own set-up is fetched from, which hosts it may
/// lead to, what it must leave behind and whose signature that must carry,
/// and what Plantoir may take away again.
///
/// **General on purpose.** #855 sets up three assistants through it; the
/// owner has ruled that Plantoir also sets up the two programs a printed
/// handout needs, and that piece is planned to reuse this shape and
/// `SetUpRunner` unchanged: nothing here knows about signing in, menus or
/// assistants. What is assistant-only lives in `AssistantSetUp`.
///
/// Paths are written relative to the home folder ("`.local/bin/claude`"), so
/// a record written on one Mac never names a teacher's home, and a test can
/// hand the runner a scratch home without rewriting a single path.
nonisolated struct SetUpRecipe: Sendable, Equatable {

    // MARK: - Types

    /// One program the set-up must leave behind, and whose it must be.
    struct Program: Sendable, Equatable {

        // MARK: - Stored properties

        /// Relative to the home folder.
        let path: String
        let identifier: String
        let team: String
        /// False for a program a set-up writes only on some versions (Codex's
        /// `codex-code-mode-host`): checked when it is there, and not missed
        /// when it is not.
        let required: Bool
    }

    // MARK: - Stored properties

    /// The key the contract and the record use ("claude", "codex", "copilot").
    let key: String
    /// What a teacher reads ("Claude Code").
    let displayName: String
    /// Who makes it ("Anthropic").
    let maker: String
    /// The maker's own documented set-up address.
    let installerAddress: URL
    /// What runs the fetched set-up: `/bin/bash` or `/bin/sh`, as the maker's
    /// own instructions pipe it.
    let interpreter: String
    /// Every host the fetch of the set-up may pass through: the documented
    /// address redirects (measured, 2026-11-13), and a redirect anywhere else
    /// is refused (plan review L4).
    let allowedHosts: [String]
    /// The hosts the set-up downloads from, asked first so that "no
    /// connection" can be told apart from every other failure (review M2):
    /// the makers' set-ups exit 1 for nearly everything.
    let reachabilityHosts: [String]
    /// Added to the environment Plantoir builds (`SetUpRunner.childEnvironment`),
    /// never inherited: Codex's `CODEX_NON_INTERACTIVE=1`.
    let extraEnvironment: [String: String]
    /// What must be there afterwards, and whose.
    let programs: [Program]
    /// What Plantoir may take away again: only those of these that did NOT
    /// exist before Plantoir's set-up ran (`SetUpRecord`). The maker's own
    /// documented removal, read 2026-11-13.
    let removes: [String]
    /// What Plantoir never takes away: the teacher's sign-in and settings.
    let keeps: [String]

    // MARK: - Computed properties

    /// The host of `installerAddress`, which is always allowed.
    var installerHost: String {
        return installerAddress.host ?? ""
    }
}
