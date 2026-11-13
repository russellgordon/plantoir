import Foundation

/// The three outside assistants Plantoir can set up for a teacher who asks
/// (#855): GitHub Copilot, Claude Code and Codex, in the order the Settings
/// pane lists them (the plan review's L1: GitHub Copilot first, because
/// GitHub's plans page says every plan includes it).
///
/// Every value here is in `contracts/app-rules.json` →
/// `outsideAgents.setUp.agents`, and `AssistantSetUpContractTests` compares
/// the two field by field, so a vendor's new address or team is changed in
/// one place a reviewer can read and the other app can copy.
nonisolated struct AssistantSetUpAgent: Sendable, Equatable {

    // MARK: - Stored properties

    let recipe: SetUpRecipe
    /// What starts the maker's own sign-in, after the program's path.
    let signInArguments: [String]
    /// What asks whether the teacher is signed in, by exit code only; nil
    /// for GitHub Copilot, which documents no such question (2026-11-13).
    let signedInCheckArguments: [String]?
    /// The exit code `signedInCheckArguments` gives when signed in.
    let signedInExitCode: Int32
    /// The maker's page that says which accounts include the tool.
    let plansPage: URL
    /// The item's title in Revise With ▸, for the ready sentence.
    let menuItem: String
    /// Help's page on GitHub's education benefits, for GitHub Copilot only
    /// (Russell, 2026-11-13: wherever Plantoir offers GitHub Copilot to a
    /// teacher who does not have it, it links that page).
    let educationHelpAnchor: String?

    // MARK: - Computed properties

    var key: String {
        return recipe.key
    }

    var displayName: String {
        return recipe.displayName
    }

    var maker: String {
        return recipe.maker
    }

    /// The program the doors start, relative to the home folder.
    var programPath: String {
        return recipe.programs[0].path
    }
}

/// The catalog and the one rule every view reads.
nonisolated enum AssistantSetUp {

    // MARK: - Stored properties

    /// What the record calls an assistant's set-up.
    static let recordKind: String = "assistant"

    /// Help's page about setting up an assistant (#839's outline).
    static let helpAnchor: String = "set-up-assistant"

    static let copilot: AssistantSetUpAgent = AssistantSetUpAgent(
        recipe: SetUpRecipe(
            key: "copilot",
            displayName: CopilotLauncher.displayName,
            maker: "GitHub",
            installerAddress: URL(string: "https://gh.io/copilot-install")!,
            interpreter: "/bin/bash",
            allowedHosts: ["gh.io", "raw.githubusercontent.com"],
            reachabilityHosts: ["github.com", "release-assets.githubusercontent.com"],
            extraEnvironment: [:],
            programs: [
                SetUpRecipe.Program(
                    path: ".local/bin/copilot",
                    identifier: CopilotLauncher.signedIdentifier,
                    team: CopilotLauncher.signedTeam,
                    required: true
                )
            ],
            removes: [".local/bin/copilot", "Library/Caches/copilot"],
            keeps: [".copilot", "the GitHub Copilot sign-in in the login keychain"]
        ),
        signInArguments: ["login"],
        signedInCheckArguments: nil,
        signedInExitCode: 0,
        plansPage: URL(string: "https://docs.github.com/en/copilot/get-started/plans")!,
        menuItem: CopilotLauncher.menuItemTitle,
        educationHelpAnchor: "github-education"
    )

    static let claude: AssistantSetUpAgent = AssistantSetUpAgent(
        recipe: SetUpRecipe(
            key: "claude",
            displayName: "Claude Code",
            maker: "Anthropic",
            installerAddress: URL(string: "https://claude.ai/install.sh")!,
            interpreter: "/bin/bash",
            allowedHosts: ["claude.ai", "downloads.claude.ai"],
            reachabilityHosts: ["downloads.claude.ai"],
            extraEnvironment: [:],
            programs: [
                SetUpRecipe.Program(
                    path: ".local/bin/claude",
                    identifier: "com.anthropic.claude-code",
                    team: "Q6L2SF6YDW",
                    required: true
                )
            ],
            removes: [".local/bin/claude", ".local/share/claude"],
            keeps: [".claude", ".claude.json", "the Claude Code sign-in in the login keychain"]
        ),
        signInArguments: ["auth", "login"],
        signedInCheckArguments: ["auth", "status"],
        signedInExitCode: 0,
        plansPage: URL(string: "https://code.claude.com/docs/en/setup")!,
        menuItem: ClaudeCodeLauncher.menuItemTitle,
        educationHelpAnchor: nil
    )

    static let codex: AssistantSetUpAgent = AssistantSetUpAgent(
        recipe: SetUpRecipe(
            key: "codex",
            displayName: "Codex",
            maker: "OpenAI",
            installerAddress: URL(string: "https://chatgpt.com/codex/install.sh")!,
            interpreter: "/bin/sh",
            allowedHosts: ["chatgpt.com", "releases.openai.com"],
            reachabilityHosts: ["releases.openai.com"],
            extraEnvironment: ["CODEX_NON_INTERACTIVE": "1"],
            programs: [
                SetUpRecipe.Program(path: ".local/bin/codex", identifier: "codex", team: "2DC432GLL2", required: true),
                SetUpRecipe.Program(
                    path: ".local/bin/codex-code-mode-host",
                    identifier: "codex-code-mode-host",
                    team: "2DC432GLL2",
                    required: false
                )
            ],
            removes: [".local/bin/codex", ".local/bin/codex-code-mode-host", ".codex/packages/standalone"],
            keeps: [".codex/auth.json", ".codex/config.toml", "everything else in .codex"]
        ),
        signInArguments: ["login"],
        signedInCheckArguments: ["login", "status"],
        signedInExitCode: 0,
        plansPage: URL(string: "https://learn.chatgpt.com/docs/pricing")!,
        menuItem: CodexLauncher.menuItemTitle,
        educationHelpAnchor: nil
    )

    /// In the pane's order.
    static let agents: [AssistantSetUpAgent] = [copilot, claude, codex]

    // MARK: - Functions

    static func agent(forKey key: String) -> AssistantSetUpAgent? {
        for agent in agents where agent.key == key {
            return agent
        }
        return nil
    }

    /// Whether the door already finds this assistant: the same search the
    /// Revise With item draws on (GitHub's own `copilot` only, #783).
    static func doorFindsIt(_ key: String) -> Bool {
        switch key {
        case "claude":
            return ClaudeCodeLauncher.findClaude() != nil
        case "codex":
            return CodexLauncher.findCodex() != nil
        case "copilot":
            return CopilotLauncher.findCopilot() != nil
        default:
            return false
        }
    }
}

/// What a row in Settings ▸ Other Assistants shows, decided from facts
/// alone (`decide`), so the contract's `setUp.stateCases` run it.
nonisolated enum AssistantSetUpState: String, Sendable, CaseIterable {
    case notSetUp
    case setUpElsewhere
    case downloading
    case checking
    case failedNoConnection
    case failedNotFromMaker
    case failedOther
    case failedTookTooLong
    case stopped
    case interrupted
    case installedSignedOut
    case signingIn
    case signInNotConfirmed
    case readySignedIn
    case readySignInFinished

    // MARK: - Types

    /// Where a set-up is right now in this session.
    enum Activity: String, Sendable {
        case idle
        case downloading
        case checking
    }

    /// What the sign-in window has reported.
    enum SignIn: Equatable, Sendable {
        case notAsked
        case windowOpen
        case finished(Int32)
    }

    /// What the signed-in question answered.
    enum Status: String, Sendable {
        case notAsked
        case signedIn
        case notSignedIn
    }

    // MARK: - Functions

    /// The state from the facts.
    /// - Parameters:
    ///   - found: the door finds the program (anyone's).
    ///   - recorded: what the record says Plantoir set up, or nil.
    ///   - lastOutcome: how this session's last set-up of it ended, or nil.
    ///   - hasSignedInCheck: the maker documents a signed-in question.
    static func decide(
        found: Bool,
        recorded: SetUpRecordEntry.State?,
        activity: Activity,
        lastOutcome: SetUpOutcome?,
        signIn: SignIn,
        status: Status,
        hasSignedInCheck: Bool
    ) -> AssistantSetUpState {
        if activity == .downloading {
            return .downloading
        }
        if activity == .checking {
            return .checking
        }
        if recorded == .installing {
            return .interrupted
        }
        if recorded == .installed && found {
            switch signIn {
            case .windowOpen:
                return .signingIn
            case .finished(let code):
                if code != 0 {
                    return .signInNotConfirmed
                }
                if !hasSignedInCheck {
                    return .readySignInFinished
                }
                switch status {
                case .signedIn:
                    return .readySignedIn
                case .notSignedIn:
                    return .signInNotConfirmed
                case .notAsked:
                    return .signingIn
                }
            case .notAsked:
                if status == .signedIn {
                    return .readySignedIn
                }
                return .installedSignedOut
            }
        }
        if found {
            return .setUpElsewhere
        }
        if let lastOutcome {
            switch lastOutcome {
            case .finished:
                return .notSetUp
            case .noConnection:
                return .failedNoConnection
            case .notFromMaker:
                return .failedNotFromMaker
            case .tookTooLong:
                return .failedTookTooLong
            case .stopped:
                return .stopped
            case .couldNotFetch, .couldNotStart, .exited, .leftNothing, .couldNotRecord:
                return .failedOther
            }
        }
        return .notSetUp
    }
}
