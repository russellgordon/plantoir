import Foundation

/// Every sentence a teacher reads about setting up an outside assistant
/// (#855), as templates: `{tool}` is "Claude Code", "Codex" or "GitHub
/// Copilot", `{maker}` is Anthropic, OpenAI or GitHub, and `{menuItem}` the
/// assistant's item in Revise With ▸.
///
/// Each is a key in `contracts/app-rules.json` →
/// `outsideAgents.setUp.wording`, and `AssistantSetUpContractTests` holds the
/// two equal key by key. CLAUDE.md rule 1 binds every one: none says how the
/// set-up works inside ("installer", "script", "terminal", "PATH", "shell",
/// "binary", "signature"); each says what happens, in plain words. None
/// names a price or calls anything free on Plantoir's own authority: the
/// makers' own pages say which accounts include what (ruling 5, 2026-11-13).
nonisolated enum AssistantSetUpWording {

    // MARK: - Stored properties

    /// The Settings pane's tab.
    static let paneTitle: String = "Other Assistants"

    /// The pane's first line (the never-requires rule, 2026-11-12).
    static let paneIntro: String =
        "Plantoir works without any of these. If you have an account with one of them, "
        + "Plantoir can set it up for you here, and Revise With then offers it on your courses."

    /// Revise With ▸, last, after a divider (ruling 3). "Set Up an
    /// Assistant…", always (Russell, 2026-11-13 evening): "Another" read
    /// wrongly when none is set up, and a title that changes with the state
    /// was rejected. The same words as the Help menu's item.
    static let menuItem: String = "Set Up an Assistant…"

    /// Help ▸, beside Plantoir Help (ruling 3).
    static let helpMenuItem: String = "Set Up an Assistant…"

    static let setUpButton: String = "Set Up…"
    static let tryAgainButton: String = "Try Again"
    static let showMeHowButton: String = "Show Me How"
    static let stopButton: String = "Stop"
    static let signInButton: String = "Sign In…"
    static let signInAgainButton: String = "Sign In Again…"
    static let checkAgainButton: String = "Check Again"
    static let removeButton: String = "Remove…"

    static let notSetUp: String = "Not set up."
    static let setUpElsewhere: String =
        "Already set up, outside Plantoir. Plantoir uses it as it is and leaves it alone."
    static let recordUnreadable: String =
        "Already set up. Plantoir couldn’t read its note of what it had set up, so it uses {tool} "
        + "as it is and leaves it alone."
    /// Under a row's own line while another assistant is being set up: one
    /// at a time (review finding 1). `{other}` is that assistant's name.
    static let oneAtATime: String = "Plantoir is setting up {other} now. You can set this one up once that has finished."

    static let confirmTitle: String = "Set up {tool}?"
    static let confirmBody: String =
        "Plantoir downloads {tool} from {maker} and puts it in your home folder, where it keeps "
        + "itself up to date. Once it is in place, Plantoir checks that {maker} made it. You need an "
        + "account with {maker} that includes {tool}, and what {tool} reads from your courses goes "
        + "to {maker} under that account."
    static let confirmPlansLink: String = "Which accounts include {tool}"
    static let confirmEducation: String =
        "Teachers can apply to GitHub for its education benefits, which can include GitHub Copilot. "
        + "GitHub decides each application, and it can take some time."
    static let confirmEducationLink: String = "How to apply"
    static let confirmButton: String = "Download and Set Up"
    static let cancelButton: String = "Cancel"

    static let downloading: String = "Downloading {tool} from {maker}…"
    static let checking: String = "Checking that {maker} made {tool}…"

    static let failedNoConnection: String =
        "Plantoir couldn’t reach {maker}. If other websites open, your school’s network may be blocking {maker}."
    static let failedNotFromMaker: String =
        "Plantoir didn’t set up {tool}: what was downloaded wasn’t made by {maker}, so Plantoir took it away again."
    static let failedOther: String =
        "Plantoir couldn’t finish setting up {tool}, and took away what it had added. If your school "
        + "looks after this computer, it may not allow new programs: the people who look after it can tell you."
    static let failedTookTooLong: String =
        "Plantoir stopped setting up {tool} because it was taking far too long, and took away what it "
        + "had added. Try again later, or on another network."
    static let stopped: String = "Setting up {tool} was stopped. Plantoir took away what it had added."
    static let interrupted: String =
        "Plantoir didn’t finish setting up {tool} last time. Try again to finish it."

    static let installedSignedOut: String =
        "{tool} is set up. Sign in to your {maker} account to start using it."
    static let signingIn: String =
        "A window opened where {tool} signs you in. Your web browser opens too: sign in there, "
        + "then come back here and choose Check Again."
    static let signInNotConfirmed: String = "Plantoir couldn’t confirm that you’re signed in to {tool}."
    static let readySignedIn: String =
        "{tool} is set up and you’re signed in. Choose Revise With ▸ {menuItem} on a course to start. "
        + "If {maker} turns you away there, check which accounts include {tool}."
    static let readySignInFinished: String =
        "{tool} is set up and its sign-in finished. Choose Revise With ▸ {menuItem} on a course to start. "
        + "If {maker} turns you away there, your account may not include {tool} yet."

    static let removeTitle: String = "Remove {tool}?"
    static let removeBody: String =
        "Plantoir takes away the copy of {tool} it set up, and only that. Your sign-in and your {tool} "
        + "settings are kept, so setting it up again later picks up where you left off."
    static let removeConfirmButton: String = "Remove"
    static let removeIncomplete: String =
        "Plantoir couldn’t take away everything it set up for {tool}. Try again, or ask for help."

    /// The sign-in window's own words: its first line, and its last once the
    /// maker's sign-in has ended. It is the window's text, so rule 1 holds.
    static let signInWindowIntro: String =
        "Signing in to {tool}. Your web browser opens: sign in there, and answer anything asked here."
    static let signInWindowDone: String =
        "You can close this window now and go back to Plantoir."

    // MARK: - Functions

    /// `template` with the assistant's names put in.
    static func filled(_ template: String, for agent: AssistantSetUpAgent) -> String {
        return template
            .replacingOccurrences(of: "{tool}", with: agent.displayName)
            .replacingOccurrences(of: "{maker}", with: agent.maker)
            .replacingOccurrences(of: "{menuItem}", with: agent.menuItem)
    }

    /// The line a row shows in `state`, before it is filled.
    static func line(for state: AssistantSetUpState) -> String {
        switch state {
        case .notSetUp:
            return notSetUp
        case .setUpElsewhere:
            return setUpElsewhere
        case .recordUnreadable:
            return recordUnreadable
        case .downloading:
            return downloading
        case .checking:
            return checking
        case .failedNoConnection:
            return failedNoConnection
        case .failedNotFromMaker:
            return failedNotFromMaker
        case .failedOther:
            return failedOther
        case .failedTookTooLong:
            return failedTookTooLong
        case .stopped:
            return stopped
        case .interrupted:
            return interrupted
        case .installedSignedOut:
            return installedSignedOut
        case .signingIn:
            return signingIn
        case .signInNotConfirmed:
            return signInNotConfirmed
        case .readySignedIn:
            return readySignedIn
        case .readySignInFinished:
            return readySignInFinished
        }
    }

    /// Every sentence and title, by its contract key, for the contract test
    /// and the rule-1 scan.
    static var everyKey: [String: String] {
        return [
            "paneTitle": paneTitle,
            "paneIntro": paneIntro,
            "menuItem": menuItem,
            "helpMenuItem": helpMenuItem,
            "setUpButton": setUpButton,
            "tryAgainButton": tryAgainButton,
            "showMeHowButton": showMeHowButton,
            "stopButton": stopButton,
            "signInButton": signInButton,
            "signInAgainButton": signInAgainButton,
            "checkAgainButton": checkAgainButton,
            "removeButton": removeButton,
            "notSetUp": notSetUp,
            "setUpElsewhere": setUpElsewhere,
            "recordUnreadable": recordUnreadable,
            "oneAtATime": oneAtATime,
            "confirmTitle": confirmTitle,
            "confirmBody": confirmBody,
            "confirmPlansLink": confirmPlansLink,
            "confirmEducation": confirmEducation,
            "confirmEducationLink": confirmEducationLink,
            "confirmButton": confirmButton,
            "cancelButton": cancelButton,
            "downloading": downloading,
            "checking": checking,
            "failedNoConnection": failedNoConnection,
            "failedNotFromMaker": failedNotFromMaker,
            "failedOther": failedOther,
            "failedTookTooLong": failedTookTooLong,
            "stopped": stopped,
            "interrupted": interrupted,
            "installedSignedOut": installedSignedOut,
            "signingIn": signingIn,
            "signInNotConfirmed": signInNotConfirmed,
            "readySignedIn": readySignedIn,
            "readySignInFinished": readySignInFinished,
            "removeTitle": removeTitle,
            "removeBody": removeBody,
            "removeConfirmButton": removeConfirmButton,
            "removeIncomplete": removeIncomplete,
            "signInWindowIntro": signInWindowIntro,
            "signInWindowDone": signInWindowDone
        ]
    }
}
