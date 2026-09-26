import Foundation

/// Every sentence "Get Ready for the Start of the Year" says to a teacher, in
/// the app's sheet and in the plan an outside assistant is shown (#96).
///
/// Retyped from `contracts/shared-rules.json` → `startOfYear.wording` and
/// pinned against it key by key (`StartOfYearPlannerTests`), the arrangement
/// `ReferenceWording` and `CopyPageWording` use: these are the app's own
/// sentences, said beside the act, so they belong with the act rather than in
/// `AssistWording` — which carries only the two refusals an outside assistant
/// meets (`startOfYearNeedsItsPlan`, `startOfYearPlanHasChanged`).
///
/// **The parameters are Strings** so the pin can call each one with its
/// `{placeholder}` and get the contract's template back. `{noun}` and
/// `{nouns}` are what the course calls one class page and several — "class"
/// and "classes", or "meeting" and "meetings" in a club (#267). `{pages}` is a
/// number with its word, "1 page" or "12 pages".
nonisolated enum StartOfYearWording {

    // MARK: - Functions

    /// "1 page", "12 pages".
    static func pages(_ count: Int) -> String {
        return count == 1 ? "1 page" : "\(count) pages"
    }

    /// "1 class", "85 classes" — or meetings, in a club.
    static func counted(_ count: Int, noun: ClassNoun) -> String {
        return "\(count) \(noun.counted(count))"
    }

    // MARK: - Where it is found

    static let menuItem: String = "Get Ready for the Start of the Year…"

    static let undoMenuItem: String = "Undo Getting Ready for the Start of the Year…"

    // MARK: - The sheet, before

    static func sheetTitle(course: String, section: String) -> String {
        return "Get \(course) Section \(section) Ready for the Start of the Year"
    }

    static func intro(first: String, noun: String, nouns: String) -> String {
        return "Every \(noun) after “\(first)” goes into draft, with the pages only later \(nouns) use. "
             + "Students keep “\(first)”, the pages it links to, your Key Links and the pages they list. "
             + "Nothing changes for students until you deploy."
    }

    static func classesHeading(classes: String) -> String {
        return "Going into draft: \(classes)"
    }

    static func pagesHeading(pages: String, nouns: String) -> String {
        return "Also going into draft: \(pages) only later \(nouns) use"
    }

    static func staysHeading(pages: String) -> String {
        return "Staying as they are: \(pages)"
    }

    static func alreadyInDraft(classes: String) -> String {
        return "Already in draft, and left as they are: \(classes)."
    }

    // MARK: - Why each page goes

    static func reasonLaterClass(first: String) -> String {
        return "comes after “\(first)”"
    }

    static func reasonFirstUsedIn(page: String) -> String {
        return "first used in “\(page)”"
    }

    static func reasonOnlyHiddenPagesLink(page: String) -> String {
        return "only “\(page)” links to it, and students will not see that page"
    }

    static func reasonOnlyAFolderLists(page: String) -> String {
        return "only the “\(page)” folder's own page lists it"
    }

    static let reasonNothingLinks: String = "nothing links to it"

    // MARK: - What stays

    static func staysFirstClass(first: String, pages: String) -> String {
        return "“\(first)”, and the \(pages) it links to"
    }

    static func staysKeyLinks(pages: String) -> String {
        return "Key Links, and the \(pages) it lists"
    }

    static let staysEverythingElse: String =
        "Every folder's own page, every curriculum page, and every page something students can "
      + "still see links to."

    // MARK: - Links left pointing at hidden pages

    static let linksLeftHeading: String =
        "After this, links on these pages will lead to pages students cannot see yet:"

    static func linksLeftLine(page: String, links: String) -> String {
        return "“\(page)”: \(links)"
    }

    /// The consequence the plan review's H3 found, said before Go and in the
    /// result — follow-up #333 is the fix.
    static func publishingFromNowOn(noun: String) -> String {
        return "From now on, each \(noun) you publish needs the pages it uses published with it. "
             + "Publishing through the assistant does that for you. Publishing a \(noun) by changing "
             + "its page in Obsidian does not, and would leave it with links students cannot follow."
    }

    // MARK: - Warnings

    static func alreadyTaught(classes: String) -> String {
        return "\(classes) going into draft are dated before today. If you have already taught them, "
             + "students will lose them when you next deploy."
    }

    static func scheduledDeploy(moment: String) -> String {
        return "This section is set to deploy on its own at \(moment). That will put these changes in "
             + "front of students."
    }

    static func firstClassIsHidden(first: String, noun: String) -> String {
        return "“\(first)” is in draft itself, so students will see no \(noun) until you publish it."
    }

    // MARK: - Pressing Go

    static let goButton: String = "Put These into Draft"

    static func nothingToDo(first: String, nouns: String) -> String {
        return "There is nothing to do: every one of the \(nouns) after “\(first)” is already in "
             + "draft, and so is every page only later \(nouns) use."
    }

    static func done(pages: String) -> String {
        return "\(pages) went into draft. Nothing has changed for students yet — that happens when "
             + "you deploy."
    }

    static func undoAvailable(backup: String) -> String {
        return "You can undo this from this section's menu until the section is next deployed, until "
             + "any of its pages is next published or put into draft, or until you quit Plantoir. "
             + "After that, the backup “\(backup)” is the way back."
    }

    static let changedSinceShown: String =
        "The section changed after this list was made, so nothing was changed. This is the list as "
      + "it stands now."

    static func backupFailed(course: String) -> String {
        return "Plantoir could not save a copy of \(course) first, so nothing was changed."
    }

    static func writeFailed(backup: String) -> String {
        return "Plantoir could not finish putting the pages into draft. The backup “\(backup)” holds "
             + "the course as it was before you pressed the button."
    }

    static func noFirstClass(course: String, section: String, noun: String) -> String {
        return "\(course) Section \(section) has no numbered \(noun) yet, so there is no first \(noun) "
             + "to keep. Nothing was changed."
    }

    // MARK: - Undoing it

    static func undoTitle(course: String, section: String) -> String {
        return "Undo Getting \(course) Section \(section) Ready?"
    }

    static func undoIntro(pages: String) -> String {
        return "\(pages) go back to how they were before you got this section ready for the start of "
             + "the year. Nothing changes for students until you deploy."
    }

    static func undoSkipped(pages: String) -> String {
        return "\(pages) changed after that, so they stay as they are:"
    }

    static let undoButton: String = "Put Them Back"

    static func undone(pages: String) -> String {
        return "\(pages) are back as they were."
    }

    static func undoLeftSome(pages: String, backup: String) -> String {
        return "\(pages) were left as they are, because they changed after the section was got "
             + "ready. The backup “\(backup)” holds them as they were."
    }

    static let undoEndsWhenYouQuit: String =
        "This undo is kept only while Plantoir is open. Quitting ends it."
}
