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

    static let lastPerSectionFolderBlocked: String =
        "Each section needs at least one folder for its class pages and lessons. Add another per-section folder first before removing this one."

    static let sectionIndexFileBlocked: String =
        "Every section needs an index.md page for its home page. Without it, the section cannot be published."

    static let removeGradedFolderMessage: String =
        "This folder holds work that counts for marks. Removing it will take it out of your course’s marks pool."

    static let removeClassFolderMessage: String =
        "This folder holds your daily lessons and class pages. If you remove it, another folder will be used for your class pages."

    static let removeCurriculumFolderMessage: String =
        "This folder holds your curriculum expectations. Removing it means expectations will not be available if you later enable curriculum coverage."

    // MARK: - Functions

    static func curriculumFolderBlockedByCurriculumPages(jurisdiction: String) -> String {
        return "This folder holds your curriculum expectations. To remove it, turn off “Include \(jurisdiction) curriculum pages” first."
    }

    static func removeGradedFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    static func removeClassFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    static func removeCurriculumFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
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
