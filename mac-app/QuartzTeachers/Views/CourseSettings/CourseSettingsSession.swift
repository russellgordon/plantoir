import Foundation
import Observation

/// What a course's settings form says and remembers beyond the settings
/// themselves, kept by the course's page so it outlives the form (#708).
///
/// The page draws the form ONLY while its Settings tab is chosen: with
/// Planning chosen the form is not in the window at all, so nothing in it can
/// hold the keyboard, be reached by Tab, or be read by VoiceOver (708 fix
/// review, H1). What the teacher typed and has not saved is the course's
/// `configuration`, a model the course owns, so it was never the form's to
/// lose. What WAS the form's, as `@State`, and moved here:
///
/// - `saveNotice`: what the last Save could not reach (issue #265). It stays
///   until the next Save, Preview Again, or leaving the course, so a look at
///   the plan must not clear it.
/// - `saveProblem`: why the last Save did not happen.
/// - `howITeachProblem`: why the How I Teach page could not be made (#329).
/// - `unitWordNotice`: what the last unit-word rename did.
/// - `didJustSave`: "Saved ✓", which fades after three seconds, so a Save
///   made with ⌘S from the Planning tab still says so if the teacher comes
///   straight back.
/// - `heldBackWasNoted`: whether `settings save held back` has been written
///   on this visit to the course (#373), so a switch of tabs does not count
///   as a new visit and write it twice.
///
/// It starts afresh for each course: the page is rebuilt per course
/// (`.id(code)` in `MainWindowView`), and so is this.
@Observable
final class CourseSettingsSession {

    // MARK: - Stored properties

    var saveNotice: SettingsSaveNotice? = nil
    var saveProblem: String? = nil
    var howITeachProblem: String? = nil
    var unitWordNotice: String? = nil
    var didJustSave: Bool = false
    var heldBackWasNoted: Bool = false
}
