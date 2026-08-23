import Foundation

/// Whether a course code names a CLUB rather than a course.
///
/// It decides two things a teacher can see: whether the New Course wizard
/// offers a "Short label" field, and whether `custom_short_name` is written
/// into `course_config.json`. Both apps ask it, so it is a contract case
/// (`contracts/course-management.json` → `courseCode.clubDetection`) rather
/// than a private idea inside either wizard.
///
/// It used to be a private idea inside both wizards, and both had the same
/// bug. The rule was one line — "the fourth character of a course code is
/// its grade digit, so a code without one is a club" — which is true of
/// Ontario (ICS3U, MPM2D) and false of British Columbia, whose codes put a
/// letter or a dash there: MTEL-12, MMA--09, MCMPR11. So all 117 BC courses
/// were read as clubs, and a real course was offered a club's short-label
/// field (Russell, 2026-08-23, reporting the stray field; the misdetection
/// underneath it was found while looking, and `NewCourseDialog.IsClubCode`
/// on Windows has the identical line).
enum ClubCodeRule {

    // MARK: - Functions

    /// Whether `code` names a club.
    ///
    /// The catalog is asked FIRST and its answer is final: a code the app
    /// ships a name for is a course, whatever shape it happens to be. Only
    /// when the catalog has never heard of a code does the Ontario-shaped
    /// guess below get a say — which is what it was always for, a
    /// teacher-invented name like CODING or ROBOTICS where there is no
    /// entry to consult and the shape of the code is the only signal.
    static func isClub(_ code: String) -> Bool {
        let trimmed: String = code.trimmingCharacters(in: .whitespaces)
        if CourseNameCatalog.names(forCode: trimmed) != nil {
            return false
        }
        if trimmed.count < 4 {
            return false
        }
        let characters: [Character] = Array(trimmed)
        return !characters[3].isNumber
    }
}
