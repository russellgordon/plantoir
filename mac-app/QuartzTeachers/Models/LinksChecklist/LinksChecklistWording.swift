import Foundation

/// Every sentence the links checklist says to a teacher (#379).
///
/// Retyped from `contracts/shared-rules.json` → `linksChecklist.wording` and
/// pinned against it key by key (`LinksChecklistTests`), the arrangement
/// `StartOfYearWording` and `CopyPageWording` use: these are the app's own
/// sentences, said beside the act. The one sentence an outside assistant
/// meets is `AssistWording.linksIntoHiddenPagesWillBeOffered`.
///
/// **The parameters are Strings** so the pin can call each one with its
/// `{placeholder}` and get the contract's template back. `{pages}` is the
/// word "page" or "pages" that agrees with `{count}`.
nonisolated enum LinksChecklistWording {

    // MARK: - Functions

    /// "page" or "pages", to agree with a count.
    static func pageWord(_ count: Int) -> String {
        return count == 1 ? "page" : "pages"
    }

    // MARK: - Where it is found

    static let menuItem: String = "Publish Pages That Links Lead To…"

    // MARK: - The sheet

    static func sheetTitle(course: String, section: String) -> String {
        return "Links to Hidden Pages in \(course) Section \(section)"
    }

    static let intro: String =
        "Pages students can see link to these pages, which are still hidden. The ticked pages will be published."

    static let fromAClassHeading: String = "Used by a class students can see"

    static let notReachedHeading: String = "Linked from other pages students can see"

    static let classesHeading: String = "Classes not yet published"

    // MARK: - A row's second line

    static func datedLike(class className: String) -> String {
        return "will have the same date as “\(className)”"
    }

    static func alreadyDatedLike(class className: String) -> String {
        return "has the same date as “\(className)”"
    }

    static let keepsItsDate: String = "was published before, so it keeps its date"

    static let keepsTheDateItHas: String = "keeps the date it has"

    static func datedAsTheFirstClass(first: String) -> String {
        return "will have the date of “\(first)”, the first class of the year"
    }

    static func firstUsedIn(class className: String) -> String {
        return "first used in “\(className)” — it will come with that class"
    }

    static let classRow: String = "a class of its own — tick it to publish it now"

    static func comesWith(count: String, pages: String) -> String {
        return "brings \(count) more \(pages) with it"
    }

    static func linkedFrom(page: String) -> String {
        return "linked from “\(page)”"
    }

    static func linkedFromSeveral(page: String, count: String) -> String {
        return "linked from “\(page)” and \(count) more"
    }

    // MARK: - Under the list

    static let frontPageStaysPut: String =
        "Publishing a class here does not change which class the front page shows."

    static let nothingChangesUntilYouDeploy: String = "Nothing changes for students until you deploy."

    // MARK: - The buttons

    static func publishButton(count: String, pages: String) -> String {
        return "Publish \(count) \(pages)"
    }

    static let publishNothingTicked: String = "Publish"

    static let notNow: String = "Not Now"

    // MARK: - Refusals and results

    static func deployUnderWay(course: String) -> String {
        return "\(course) is being published just now. Try again when that has finished."
    }

    static func needsAPreviewFirst(course: String, section: String) -> String {
        return "Pages in \(course) have changed since Section \(section) was last previewed or published. "
             + "Preview it again, and this list will be up to date."
    }

    static let nothingLeftToPublish: String =
        "Those pages have all been published or removed since the website was made."

    static func pageChangedSince(page: String) -> String {
        return "“\(page)” changed since it was checked, so it was left as it is."
    }

    static func published(count: String, pages: String) -> String {
        return "\(count) \(pages) will be on the website the next time you deploy."
    }
}
