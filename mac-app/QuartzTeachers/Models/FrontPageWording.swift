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
    /// Alerts page, read that night); OK, the default, since it is
    /// informational, with Show in Finder beside it.
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

    /// The alert's second button (Russell's second ruling of 2026-11-20,
    /// night): a verb phrase naming its result, title-style, the words this
    /// action has everywhere else in the app (the HIG's Alerts page, read
    /// that night). OK stays the default, on the trailing side.
    static let showKept: String = "Show in Finder"

    /// What Show in Finder says instead when a kept file it was to show is
    /// no longer there (U3c review 3, LOW 2, fixed in U4a: Finder was
    /// brought forward on an unrelated window and nothing was said). One
    /// sentence per name; an informational alert with OK.
    static func keptGone(_ keptNames: [String]) -> String {
        var sentences: [String] = []
        for name in keptNames {
            sentences.append(keptGoneSentence(kept: name))
        }
        return sentences.joined(separator: " ")
    }

    static func keptGoneSentence(kept name: String) -> String {
        return "“\(name)” is no longer there, so there is nothing to show."
    }
}
