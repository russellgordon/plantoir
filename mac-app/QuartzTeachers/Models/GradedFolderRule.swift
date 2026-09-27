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

    /// A pool somebody CHOSE — ticked in the wizard, or declared by a
    /// payload's manifest — reconciled against the folders the course
    /// actually ends up with, in the order it was chosen.
    ///
    /// A name they ticked and then took out of the course would otherwise be
    /// written into `graded_folders` matching nothing on disk: the file would
    /// say something untrue, and the two apps would write DIFFERENT files for
    /// the same clicks. (There is no second net: since GitHub issue #192
    /// `setup_course.py` writes a saved pool back as it was, so what the
    /// wizard writes is what the course keeps — contracts/shared-rules.json
    /// → `gradedFolders.rerunningSetup`.)
    ///
    /// **The command line's rule, to the letter** —
    /// `setup_course.graded_folders_for`, and Windows'
    /// `GradedFolderRule.Reconciled`, which already followed it: a blank
    /// goes; a name that is a folder EXACTLY is kept as written; otherwise a
    /// name that is a folder with case ignored takes the folder's own
    /// spelling — the LAST folder of that spelling when two differ only by
    /// case, as a Python dictionary built in order gives; any other name is
    /// dropped; and a name already kept is not kept again. Pinned by
    /// `gradedFolders.reconcilingAChosenPool`, which all three run.
    ///
    /// Until [issue #152](https://github.com/russellgordon/plantoir/issues/152)
    /// (from #85's second item) this matched EXACTLY and kept repeats, so a
    /// `tasks` chosen against a folder `Tasks` wrote an empty pool where the
    /// command line writes `["Tasks"]`. No shipped payload or skeleton shows
    /// the difference — every pool matches its own folders exactly — so this
    /// is one rule in one place, shared with `ExampleContentCatalog.marksPool`,
    /// rather than a fix a teacher will notice.
    nonisolated static func reconciled(_ declared: [String], toFolders folders: [String]) -> [String] {
        // The later folder wins the spelling, as it does in Python's
        // dictionary built the same way.
        var spellingIgnoringCase: [String: String] = [:]
        for folder in folders {
            if folder.isEmpty {
                continue
            }
            spellingIgnoringCase[folder.lowercased()] = folder
        }

        var kept: [String] = []
        for name in declared {
            if name.isEmpty {
                continue
            }
            var folderName: String? = nil
            if folders.contains(name) {
                folderName = name
            } else if let respelled = spellingIgnoringCase[name.lowercased()] {
                folderName = respelled
            }
            guard let matchedFolder = folderName else {
                continue
            }
            if !kept.contains(matchedFolder) {
                kept.append(matchedFolder)
            }
        }
        return kept
    }

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
