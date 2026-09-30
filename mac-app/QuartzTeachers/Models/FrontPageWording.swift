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

    static let notToday: String = "Not Today"

    // MARK: - When nothing was changed

    static let notChangedTitle: String = "The Front Page Was Not Changed"

    static func noLongerOffered(noun: String) -> String {
        return "The front page or today’s \(noun) changed while you were deciding, so it was left as it is."
    }

    static func couldNotSave(shown: String) -> String {
        return "The front page could not be saved, so it still shows \(shown)."
    }
}
