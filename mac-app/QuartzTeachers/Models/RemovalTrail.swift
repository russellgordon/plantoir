import Foundation

/// What the activity trail says when a teacher is told a folder or file
/// cannot be removed from one of a course's lists (GitHub issue #171).
///
/// The line names the COURSE and the SCREEN, in Windows' words:
///
///     new course SNC4M: could not remove “Tasks” from the shared folders — <reason>
///     SNC4M: could not remove “Tasks” from the shared folders — <reason>
///
/// The first is the New Course wizard, the second Course Settings. Before
/// #171 the line was "was told Tasks cannot be removed from <list title> —
/// …", which named no course, and whose list titles are the same on both
/// screens for three of the five lists — so a refusal in the wizard could
/// not be told from the same refusal in an existing course.
///
/// The editors take one of these as a REQUIRED parameter rather than an
/// optional with a course-less fallback: a new call site that leaves the
/// course out does not compile, so the defect cannot quietly come back.
///
/// The separator is the em dash every other trail line uses. Windows writes
/// " - " in these two places only; the words are otherwise its own.
struct RemovalTrail: Equatable {

    // MARK: - Stored properties

    /// Where the refusal happened.
    enum Place: Equatable {
        case courseSettings
        case newCourse
    }

    /// Which of a course's lists the item is in, and what the line calls it.
    enum List: Equatable {
        case sharedFolders
        case sharedFiles
        case perSectionFolders
        case perSectionFiles
        case marks
        /// The curriculum folders offered a coverage map each (#128).
        case curriculumFolders

        /// The list as the line names it — Windows' words.
        var words: String {
            switch self {
            case .sharedFolders:
                return "the shared folders"
            case .sharedFiles:
                return "the shared files"
            case .perSectionFolders:
                return "the per-section folders"
            case .perSectionFiles:
                return "the per-section files"
            case .marks:
                return "the marks list"
            case .curriculumFolders:
                return "the curriculum folders"
            }
        }
    }

    /// What the wizard's line names the course before a code has been typed.
    /// Windows prints nothing there ("new course : …").
    static let codeNotTypedYet: String = "(no code yet)"

    let place: Place
    let courseCode: String
    let list: List

    // MARK: - Functions

    /// A refusal in Course Settings, for a course that already exists.
    static func inCourseSettings(courseCode: String, list: List) -> RemovalTrail {
        return RemovalTrail(place: .courseSettings, courseCode: courseCode, list: list)
    }

    /// A refusal in the New Course wizard. The code is what the teacher has
    /// typed so far, trimmed and uppercased exactly as the wizard does when
    /// it creates the course (`NewCourseWizardView.startCreation`).
    static func inNewCourse(typedCode: String, list: List) -> RemovalTrail {
        let code: String = typedCode.trimmingCharacters(in: .whitespaces).uppercased()
        if code.isEmpty {
            return RemovalTrail(place: .newCourse, courseCode: RemovalTrail.codeNotTypedYet, list: list)
        }
        return RemovalTrail(place: .newCourse, courseCode: code, list: list)
    }

    /// The trail line for one refusal. `item` is the folder or file's name as
    /// the list holds it, and `reason` the sentence the teacher was shown.
    func line(item: String, reason: String) -> String {
        var line: String = ""
        if place == .newCourse {
            line += "new course "
        }
        line += courseCode + ": could not remove “" + item + "” from " + list.words + " — " + reason
        return line
    }
}
