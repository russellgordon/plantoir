import Foundation

/// Every sentence a teacher reads about a course kept for reference — written
/// once, here.
///
/// Retyped from `contracts/shared-rules.json` → `referenceCourses.wording` and
/// pinned against it by `ReferenceCourseTests`, the same arrangement
/// `ScheduledDeployCleanup`'s sentences use. They are NOT in `AssistWording`:
/// most of them are said by the app rather than by the assistant, and a
/// sentence belongs beside the act that produces it. The one the assistant
/// also says — the deploy refusal — lives in both, with a test asserting the
/// two are the same string, because the shared Python has to say it too and
/// `scripts/contracts.py` can read `shared-rules.json` and not
/// `assist-wording.json`.
///
/// **The register is calm.** A teacher who keeps a course for reference asked
/// for this; being told about it should read like a fact rather than a
/// warning. No "cannot", no "error", no icon — and never a word about how it
/// is done.
/// Thrown by an app-side write that a course kept for reference must not
/// meet.
///
/// A `LocalizedError` rather than a bare `Bool`, so whatever catches it shows
/// the sentence rather than the file system's own words — which is what a
/// teacher read before these guards existed: "couldn't be removed because you
/// don't have permission to access it."
struct ReferenceCourseIsFrozen: LocalizedError, Equatable {

    // MARK: - Stored properties

    /// The code a TEACHER reads.
    let displayCode: String

    // MARK: - Computed properties

    var errorDescription: String? {
        return ReferenceWording.staysAsItIs(course: displayCode)
    }
}

nonisolated enum ReferenceWording {

    // MARK: - Functions

    /// Why an act that would change the course is not available.
    ///
    /// Says what the course IS and stops. It does not tell the teacher to
    /// copy anything, and that stays true now that Plantoir HAS a way — "Copy
    /// a Page from This Course…", on this course's own row, added 2026-09-21
    /// with issue #207. The sentence is a refusal about CHANGING this course;
    /// naming a different feature inside it is a non-sequitur, and the menu
    /// item sits one line away in the menu they are already looking at.
    /// (Until #207 the reason was that nothing copied pages at all and a
    /// hand copy arrives locked. The second half of that is still true — see
    /// `aCopyTakenOutStaysLocked` — and the first half stopped being true in
    /// the same release, which is why the reason is written out again here
    /// rather than left to be believed.)
    static func staysAsItIs(course: String) -> String {
        return "\(course) is kept for reference, so it stays as it is."
    }

    // MARK: - The group, and the shelf

    /// What the sidebar calls the group. Russell's word.
    static let groupTitle: String = "Reference Courses"

    /// What a year sub-group with no year is called.
    static let otherYearTitle: String = SchoolYear.otherGroupName

    // MARK: - Keeping a copy

    /// The menu item on a course a teacher is teaching.
    static let keepACopyMenuItem: String = "Keep a Copy for Reference…"

    /// The menu item on a reference course, for changing which year it is
    /// filed under.
    static let setSchoolYearMenuItem: String = "Set School Year…"

    /// The sheet's title.
    static func keepACopyTitle(course: String) -> String {
        return "Keep a copy of \(course) for reference"
    }

    /// What the copy IS, said before the teacher presses the button.
    ///
    /// Three facts and no advice: it is a snapshot, the course they are
    /// teaching is untouched, and taking a fresher copy later means deleting
    /// this one first. That last is not politeness — the uniqueness rule
    /// refuses a second copy under the same code and year until the first is
    /// gone, so saying it here is the difference between an order of work and
    /// a refusal a teacher meets by surprise.
    static func copyIsASnapshot(course: String) -> String {
        return "This records \(course) as it is today. You can keep teaching it as usual — "
             + "nothing here changes. To take a fresher copy later, delete this one first, "
             + "then copy again."
    }

    // MARK: - The pages being locked

    /// The calm note, said when a copy is made and again before the teacher
    /// goes to read the course in Obsidian.
    ///
    /// **It claims no more than is true, and that is a measured limit rather
    /// than caution.** It does not say the pages CANNOT be changed: the lock
    /// is per-Mac, a folder kept in iCloud Drive has it cleared while files
    /// upload, and an edit arriving from another device is not blocked. And
    /// it does not promise the teacher will be TOLD when an edit fails —
    /// whether Obsidian says so or swallows what was typed is exactly what
    /// could not be measured.
    ///
    /// No warning icon anywhere it appears, and no "cannot" or "error": a
    /// teacher who kept a course for reference asked for this, so it reads as
    /// a fact rather than as an alarm.
    static let pagesAreLocked: String =
        "Plantoir keeps this course's pages locked, so they stay as they were."

    // A second sentence used to follow `pagesAreLocked` here — "A file you copy
    // out of it stays locked until you untick Locked in Get Info." — written on
    // the evening #207 was out of this release and a teacher's only way to
    // take a page out of a reference course was by hand in Finder. #207 came
    // back into the same release and its copies arrive UNLOCKED, so Russell
    // retired the sentence on 2026-09-22: a hand copy is unlikely, and "Get
    // Info" without "Finder" told a teacher nothing. The fact itself is still
    // true and is in documentation/09 for whoever meets it.

    /// The title over the two sentences above, wherever they need one.
    static let pagesAreLockedTitle: String = "About this course's pages"

    /// The year could not be written — a full disk, a folder gone read-only.
    static func couldNotSetSchoolYear(course: String) -> String {
        return "\(course)'s school year could not be saved. Try again in a moment."
    }

    /// The trail line for a year that moved.
    ///
    /// Names BOTH the code a teacher reads and the folder, because the two
    /// differ here on purpose and somebody reading a report months later
    /// needs to know which course on the shelf moved.
    static func schoolYearTrailLine(
        course: String, folderName: String, from previous: Int?, to next: Int?
    ) -> String {
        return "filed \(course) (\(folderName)) under \(schoolYearName(next)) "
             + "— it was \(schoolYearName(previous))"
    }

    /// "2025–26", or "no school year".
    static func schoolYearName(_ startingYear: Int?) -> String {
        guard let startingYear else {
            return "no school year"
        }
        return SchoolYear.label(forStartingYear: startingYear)
    }

    // MARK: - The section window

    /// The section window's empty state, in place of "…or Deploy to put it
    /// online".
    static func neverDeployed(course: String) -> String {
        return "\(course) is kept for reference. Preview it to read its pages; it is never deployed."
    }
}
