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
    /// copy anything: in this release there is nothing in Plantoir that
    /// copies pages between courses, and a sentence that sends them to do it
    /// by hand would be sending them somewhere the pages arrive locked.
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

    /// The one line about a page taken out by hand.
    ///
    /// Here because in this release nothing in Plantoir copies pages between
    /// courses, so a teacher who wants one does it in Finder — and it arrives
    /// locked, with no explanation, which is the fault that gets reported as
    /// "the app is broken". Said once, beside the sentence above.
    static let aCopyTakenOutStaysLocked: String =
        "A file you copy out of it stays locked until you untick Locked in Get Info."

    /// The title over the two sentences above, wherever they need one.
    static let pagesAreLockedTitle: String = "About this course's pages"

    // MARK: - The section window

    /// The section window's empty state, in place of "…or Deploy to put it
    /// online".
    static func neverDeployed(course: String) -> String {
        return "\(course) is kept for reference. Preview it to read its pages; it is never deployed."
    }
}
