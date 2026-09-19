import Foundation

/// The rule a course is ALREADY working to when nobody has ever been asked
/// which folders count for marks: any folder whose name mentions tasks.
///
/// `graded_folders` absent in `course_config.json` does not mean "none" — it
/// means the question was never put, so the historical substring rule still
/// applies and the build counts what it always counted. Three places in this
/// app had to answer "what is this course counting right now?" and each had
/// written the substring out for itself; a fourth copy arrived with the
/// wizard's skeleton toggle, which is why the rule is now in one place.
///
/// Windows' half is `Plantoir.Core/Models/GradedFolderRule.cs`; the name here
/// matches its `InferredPool` deliberately, because
/// `contracts/shared-rules.json` compares the two apps' answers rather than
/// their code.
enum GradedFolderRule {

    // MARK: - Stored properties

    /// What a folder's name has to contain, case ignored, for the build to
    /// have been counting it before anybody was asked. Mirrors
    /// `setup_course.py`'s `graded_folders_for` fallback and
    /// `build_site.py`'s own test.
    nonisolated static let historicalSubstring: String = "task"

    // MARK: - Functions

    /// The pool a course that has never been asked is already working to,
    /// read off the folders it actually has — in the order they were given,
    /// each name once.
    ///
    /// De-duplicated by exact name, matching Windows' `InferredPool`: the
    /// same folder can reach this from two lists at once (a course's shared
    /// folders and its per-section folders), and offering a teacher the same
    /// name twice would tick one box and leave the other looking unticked.
    nonisolated static func inferredPool(from folderNames: [String]) -> [String] {
        var counted: [String] = []
        for name in folderNames {
            if name.isEmpty {
                continue
            }
            if !name.lowercased().contains(historicalSubstring) {
                continue
            }
            if counted.contains(name) {
                continue
            }
            counted.append(name)
        }
        return counted
    }
}
