import Foundation

/// Every sentence a teacher reads while copying a page from one course into
/// another — written once, here.
///
/// Retyped from `contracts/shared-rules.json` →
/// `copyingAPageBetweenCourses.wording` and pinned against it by
/// `CoursePageCopyTests`, the same arrangement `ReferenceWording` and
/// `ScheduledDeployCleanup` already use. They are NOT in `AssistWording`: the
/// assistant never says any of these — the feature is deterministic code
/// reached from a menu and is deliberately on no tool surface — and putting
/// them there would move a generated contract for no reason.
///
/// **The register.** Plain words for the things a teacher can see: pages,
/// pictures and files, folders, courses. Never a word about how it is done —
/// no "frontmatter", no "Media folder", no "wikilink", no "walk". A site is
/// DEPLOYED and a page is PUBLISHED (Russell, 2026-09-20), and these follow
/// that.
///
/// The word for hidden is the app's own: `AssistWording.theCopyStartsHidden`
/// already says "The copy starts hidden, so nothing changes on the site until
/// you publish it", and the sentences here keep that word rather than
/// inventing a second one.
nonisolated enum CopyPageWording {

    // MARK: - Stored properties

    /// The sidebar's menu item. On EVERY course row, live and kept for
    /// reference alike: reading a course is what a reference course is for,
    /// and this only ever reads the one it is invoked on.
    static let menuItem: String = "Copy a Page from This Course…"

    /// The field labels, which are nouns rather than questions: the sheet's
    /// own title already asks.
    static let whichPage: String = "Page"
    static let whichCourse: String = "Copy into"
    static let whichFolder: String = "Folder"

    /// SHORT, because the field is narrow — it sits in a form's trailing
    /// column with 34pt of it reserved for the chevron, and the row is
    /// already labelled "Page".
    static let pagePickerPrompt: String = "Search"

    /// What the list says when nothing matches what was typed.
    static let noPagesMatch: String = "No page of that name in this course."

    /// The promise the whole feature rests on, said where the teacher is
    /// deciding rather than afterwards.
    static let copiesStartHidden: String =
        "Copies start hidden, so nothing changes on any website until you publish them."

    /// Said once beside the summary, because a page copied from last year
    /// keeps last year's date and a teacher who publishes it without looking
    /// would meet that on the site.
    static let datesAreKept: String = "The pages keep the dates they had."

    /// Nothing is ever written over — the sentence that says so.
    static let nothingIsWrittenOver: String =
        "Nothing already in that course is changed or written over."

    static let nothingWasCopied: String = "Nothing was copied."

    static let copyAnother: String = "Copy another"

    static let thereIsNoCourseToCopyInto: String = "There is no other course to copy into yet"

    // MARK: - Functions

    static func sheetTitle(course: String) -> String {
        return "Copy a page from \(course)"
    }

    /// The calm wait while the destination is saved. Never a duration: it is
    /// about ten seconds on a real course and the honest thing to say is what
    /// is happening, not a number that will be wrong on somebody else's Mac.
    static func savingACopyFirst(course: String) -> String {
        return "Saving a copy of \(course) first…"
    }

    static func theBackupTaken(course: String, named: String) -> String {
        return "A copy of \(course) from before this is saved as \(named)."
    }

    static func copiedInto(pages: Int, course: String, folder: String) -> String {
        let pageWord: String = pages == 1 ? "page" : "pages"
        return "Copied \(pages) \(pageWord) into \(course), in \(folder)."
    }

    static func willBringPicturesAndFiles(count: Int, size: String) -> String {
        let word: String = count == 1 ? "picture or file" : "pictures and files"
        return "Brings \(count) \(word), \(size)."
    }

    static func picturesAlreadyThere(count: Int) -> String {
        if count == 1 {
            return "1 is already in this course and will be used as it is."
        }
        return "\(count) are already in this course and will be used as they are."
    }

    static func picturesBroughtInUnderANewName(count: Int) -> String {
        if count == 1 {
            return "1 has the same name as something different already here, so it comes in under a new name."
        }
        return "\(count) have the same name as something different already here, so they come in under a new name."
    }

    static func aPageOfThatNameIsAlreadyHere(page: String) -> String {
        return "“\(page)” is already in this course, so it was left as it is — links will lead to the one that is here."
    }

    static func theseLinksWillNotLeadAnywhereYet(names: String) -> String {
        return "These links will not lead anywhere yet: \(names)."
    }

    static func thatCourseIsDeployingRightNow(course: String) -> String {
        return "Available once \(course)’s deploy has finished"
    }

    static func thisCourseHasNoPagesToCopy(course: String) -> String {
        return "\(course) has no pages in shared folders to copy"
    }

    /// The refusal that follows the read-back guard: the page was written,
    /// could not be shown to be hidden in every section, and was taken away
    /// again.
    ///
    /// It says what was NOT done and where the way back is. A copy that
    /// turned up where students could read it is the failure this whole
    /// feature is arranged around, so the sentence is allowed to be long.
    static func theCopyCouldNotBeMadeHidden(page: String) -> String {
        return "“\(page)” was not copied: Plantoir could not be certain it would arrive hidden from students, and a copy must never turn up where students can read it."
    }

    /// The other refusal that deletes what it wrote: a picture had to come in
    /// under a new name, and the copied page could not be pointed at it with
    /// certainty.
    ///
    /// Direction of error: no page at all, rather than a page showing the
    /// teacher's own DIFFERENT picture under the name the copy wanted.
    static func thePicturesCouldNotBePointedAtTheirNewNames(page: String) -> String {
        return "“\(page)” was not copied: one of its pictures had to come in under a new name and Plantoir could not be certain the page would find it."
    }

    /// Something the file system refused, said without its own words.
    static func thePageCouldNotBeWritten(page: String) -> String {
        return "“\(page)” could not be copied."
    }

    static func aPictureCouldNotBeCopied(name: String) -> String {
        return "“\(name)” could not be copied, so the page that shows it will not find it."
    }
}
