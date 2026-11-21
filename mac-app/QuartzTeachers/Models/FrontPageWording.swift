import Foundation

/// What the section window says when it offers to show today's class on the
/// front page (#397).
///
/// Retyped from `contracts/class-planning.json` →
/// `todaysClassOnTheFrontPage.wording` and pinned key by key against it
/// (`TodaysClassOnTheFrontPageTests`), the arrangement `LinksChecklistWording`
/// uses. Plain words only (R14, Russell 2026-09-30): never "transclude",
/// "transclusion" or "embed" — the page every student lands on is "the front
/// page". `plainWordsCheck` in the contract lists the words, and a test scans
/// every filled sentence for them.
nonisolated enum FrontPageWording {

    // MARK: - The question

    static func question(class className: String) -> String {
        return "Show \(className) on the front page?"
    }

    static func because(noun: String, shown: String) -> String {
        return "Today’s \(noun) is published, but the front page still shows \(shown)."
    }

    static let show: String = "Show on Front Page"

    /// The answer that declines (#987, Russell's ruling Q2 on #975): "Not
    /// Now" on an offer Plantoir raised by itself, as this one is when the
    /// teacher presses Preview. It was "Not Today". The decline is still
    /// remembered for the day and the class (`frontPageNotToday`).
    static let notToday: String = "Not Now"

    // MARK: - When nothing was changed

    static let notChangedTitle: String = "The Front Page Was Not Changed"

    static func noLongerOffered(noun: String) -> String {
        return "The front page or today’s \(noun) changed while you were deciding, so it was left as it is."
    }

    static func couldNotSave(shown: String) -> String {
        return "The front page could not be saved, so it still shows \(shown)."
    }

    // MARK: - When it went in and what it held is kept

    /// The one alert when Show on Front Page went in but an edit made at
    /// the same instant could not be merged and is kept hidden beside the
    /// page (#899 U3c, Russell's ruling of 2026-11-20, night). A complete
    /// sentence, so sentence-style capitals and a full stop (the HIG's
    /// Alerts page, read that night); one OK, since it is purely
    /// informational.
    static func keptTitle(class className: String) -> String {
        return "The front page now shows \(className)."
    }

    /// `{kept}` is the hidden name, quoted; one sentence per name.
    static func kept(_ keptNames: [String]) -> String {
        var sentences: [String] = []
        for name in keptNames {
            sentences.append(keptSentence(kept: name))
        }
        return sentences.joined(separator: " ")
    }

    static func keptSentence(kept name: String) -> String {
        return "What the front page held a moment before is kept beside it, hidden, as “\(name)”."
    }
}
