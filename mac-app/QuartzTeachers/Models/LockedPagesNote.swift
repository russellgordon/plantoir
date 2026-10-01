import Foundation

/// Which reference courses the teacher has already been told about their
/// pages being locked.
///
/// **Once per course, and then never again.** The note is a fact rather than
/// a warning, and a fact repeated every time a teacher opens a course they
/// deliberately kept for reference becomes a click to get past — which is how
/// a sentence that matters stops being read.
///
/// Kept in the app's own preferences rather than in the course, for two
/// reasons: writing it into the course would mean writing into a course the
/// product has just promised not to write into, and the note is about what
/// THIS teacher has seen rather than about the course.
@MainActor
enum LockedPagesNote {

    // MARK: - Stored properties

    /// Where the list is kept.
    static let storageKey: String = "referenceCoursesToldAboutLockedPages"

    /// Replaceable, so a test never writes into the teacher's own
    /// preferences — the same seam every other stored list here uses.
    static var defaults: UserDefaults = PlantoirDefaults.shared

    // MARK: - Functions

    /// Whether this course's note has been shown already.
    static func hasBeenShown(courseCode: String) -> Bool {
        let shown: [String] = defaults.stringArray(forKey: storageKey) ?? []
        for code in shown where code == courseCode {
            return true
        }
        return false
    }

    /// Remembers that it has.
    static func remember(courseCode: String) {
        var shown: [String] = defaults.stringArray(forKey: storageKey) ?? []
        for code in shown where code == courseCode {
            return
        }
        shown.append(courseCode)
        defaults.set(shown, forKey: storageKey)
    }

    /// Forgets everything. For tests, and for nothing else.
    static func forgetAll() {
        defaults.removeObject(forKey: storageKey)
    }
}
