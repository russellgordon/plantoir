import Foundation

/// The protection state for a folder or file row in list editors:
/// ordinary (can remove immediately), consequential (confirm before removing),
/// or blocked (removal forbidden; shows info button explaining why and what switch to change).
enum ItemProtection: Equatable {
    case ordinary
    case consequential(title: String, message: String)
    case blocked(reason: String)
}

/// User-facing sentences, confirmation dialog texts, and explanations for special folders
/// and protected items. Authored in `contracts/shared-rules.json` → `specialNames`.
enum SpecialNames {

    // MARK: - Stored properties

    static let excludedFolderIndexNoteBody: String =
        "> [!NOTE]\n> This folder was removed in Course Settings and is excluded from your website. Its pages will not appear in previews or on your published site. To include it again, add it back in Course Settings."

    static let excludedFolderSentinelStart: String =
        "<!-- plantoir:excluded-folder-note:start -->"

    static let excludedFolderSentinelEnd: String =
        "<!-- plantoir:excluded-folder-note:end -->"

    static let curriculumFolderBlockedByCoverageSetting: String =
        "The curriculum coverage map needs this folder to show your expectations. To remove it, turn off “Publish the curriculum coverage map” in Settings first."

    static let curriculumFolderBlockedByCoverageMap: String =
        "This folder holds your curriculum expectations for the coverage map. To remove it, turn off “Include the curriculum coverage map” first."

    static let lastGradedFolderBlocked: String =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Publish the curriculum coverage map”."

    static let lastGradedFolderBlockedWizard: String =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Include the curriculum coverage map”."

    static let classFolderBlocked: String =
        "“All Classes” holds your class pages and lessons — the pages the next-class button and the schedule write to. It cannot be removed; other per-section folders can."

    static let lastPerSectionFolderBlocked: String =
        "Each section needs at least one folder for its class pages and lessons. Add another per-section folder first before removing this one."

    static let sectionIndexFileBlocked: String =
        "Every section needs an index.md page for its home page. Without it, the section cannot be published."

    static let removeGradedFolderMessage: String =
        "This folder holds work that counts for marks. Removing it will take it out of your course’s marks pool."

    static let removeCurriculumFolderMessage: String =
        "This folder holds your curriculum expectations. Removing it means expectations will not be available if you later enable curriculum coverage."

    static let renameFolderExplanation: String =
        "This renames the folder on your Mac — in every section that has one — and points your pages’ links at the new name. It happens straight away, so Cancel in Settings will not undo it."

    static let renameFolderProblemEmpty: String =
        "Type the folder’s new name."

    static let renameFolderProblemUnchanged: String =
        "That is already this folder’s name."

    static let renameFolderProblemHasSeparator: String =
        "A folder’s name cannot contain “/” or “:”."

    static let renameFolderProblemIsHidden: String =
        "A name starting with a dot makes the folder hidden, and Plantoir would stop finding it."

    static let renameFolderProblemIsMedia: String =
        "Plantoir looks after the Media folder itself, so nothing else can be called Media."

    // MARK: - Functions

    static func curriculumFolderBlockedByCurriculumPages(jurisdiction: String) -> String {
        return "This folder holds your curriculum expectations. To remove it, turn off “Include \(jurisdiction) curriculum pages” first."
    }

    static func removeGradedFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    static func removeCurriculumFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    static func renameFolderTitle(for name: String) -> String {
        return "Rename “\(name)”"
    }

    static func renameFolderProblemAlreadyUsed(name: String) -> String {
        return "This course already has a folder called “\(name)”."
    }

    static func renameFolderProblemLooksLikeASection(name: String) -> String {
        return "“\(name)” is what Plantoir calls a section’s own folder, so it cannot be used here."
    }

    static func renameFolderProblemDestinationExists(name: String) -> String {
        return "There is already something called “\(name)” beside it. Move or rename that first."
    }

    static let renameFolderNothingWasThere: String =
        "There was no folder by that name on your Mac, so only this course’s settings changed. Make it in Obsidian when you need it."

    static func renameFolderDone(from oldName: String, to newName: String) -> String {
        return "“\(oldName)” is now “\(newName)”."
    }

    /// What the rename did to the teacher's links, worded for the number it
    /// actually found. Three sentences rather than one with a count in
    /// brackets: "1 pages" is the sort of thing a teacher notices and stops
    /// trusting, and "no page linked into it" is worth saying out loud rather
    /// than leaving as silence that could equally mean nothing was checked.
    static func renameFolderRelinked(pages: Int) -> String {
        if pages == 0 {
            return "No page linked into it by name, so nothing else needed changing."
        }
        if pages == 1 {
            return "One page had links pointing into it, and they now point at the new name."
        }
        return "\(pages) pages had links pointing into it, and they now point at the new name."
    }

    static func addCreatesTheFolderMessage(name: String) -> String {
        return "Plantoir made the folder “\(name)” for you. Open it in Obsidian to put pages in it."
    }

    static func removeLeavesTheFolderOnDiskMessage(name: String) -> String {
        return "“\(name)” and everything in it stays on your Mac — this only takes it off your website. Add it back here to include it again."
    }
}

/// Determines which folder holds a course's curriculum expectation pages.
///
/// Matches `_find_curriculum_folder` in `scripts/build_site.py`:
/// if `curriculum_folder` is configured and present, it is used;
/// otherwise the alphabetically first folder containing 'curriculum' (case-insensitive) is used.
enum CurriculumFolderRule {

    // MARK: - Functions

    /// Resolves the curriculum folder name from the configured `curriculum_folder` (if present and in the list)
    /// or by scanning the available folder names sorted alphabetically for the first one
    /// containing "curriculum" (case-insensitive).
    static func resolvedCurriculumFolder(
        configured: String?,
        in folders: [String]
    ) -> String? {
        if let configured = configured, !configured.isEmpty {
            for folder in folders {
                if folder == configured {
                    return folder
                }
            }
        }
        var candidates: [String] = []
        for folder in folders {
            if folder.lowercased().contains("curriculum") {
                candidates.append(folder)
            }
        }
        candidates.sort()
        return candidates.first
    }

    /// Resolves the curriculum folder name for a course.
    static func resolvedCurriculumFolder(for course: Course) -> String? {
        return resolvedCurriculumFolder(
            configured: course.configuration.curriculumFolder,
            in: course.configuration.sharedFolders
        )
    }
}
