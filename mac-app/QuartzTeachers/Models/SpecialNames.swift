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

    nonisolated static let excludedFolderIndexNoteBody: String =
        "> [!NOTE]\n> This folder was removed in Course Settings and is excluded from your website. Its pages will not appear in previews or on your published site. To include it again, add it back in Course Settings."

    nonisolated static let excludedFolderSentinelStart: String =
        "<!-- plantoir:excluded-folder-note:start -->"

    nonisolated static let excludedFolderSentinelEnd: String =
        "<!-- plantoir:excluded-folder-note:end -->"

    nonisolated static let curriculumFolderBlockedByCoverageSetting: String =
        "The curriculum coverage map needs this folder to show your expectations. To remove it, turn off “Publish the curriculum coverage map” in Settings first."

    nonisolated static let curriculumFolderBlockedByCoverageMap: String =
        "This folder holds your curriculum expectations for the coverage map. To remove it, turn off “Include the curriculum coverage map” first."

    nonisolated static let lastGradedFolderBlocked: String =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Publish the curriculum coverage map”."

    nonisolated static let lastGradedFolderBlockedWizard: String =
        "At least one folder must count for marks while the curriculum coverage map is enabled. To remove or uncheck this folder, choose another graded folder under Marks first, or turn off “Include the curriculum coverage map”."

    nonisolated static let classFolderBlocked: String =
        "“All Classes” holds your class pages and lessons — the pages the next-class button and the schedule write to. It cannot be removed; other per-section folders can."

    nonisolated static let lastPerSectionFolderBlocked: String =
        "Each section needs at least one folder for its class pages and lessons. Add another per-section folder first before removing this one."

    nonisolated static let sectionIndexFileBlocked: String =
        "Every section needs an index.md page for its home page. Without it, the section cannot be published."

    nonisolated static let removeGradedFolderMessage: String =
        "This folder holds work that counts for marks. Removing it will take it out of your course’s marks pool."

    nonisolated static let removeCurriculumFolderMessage: String =
        "This folder holds your curriculum expectations. Removing it means expectations will not be available if you later enable curriculum coverage."

    nonisolated static let renameFolderExplanation: String =
        "This renames the folder on your Mac — in every section that has one — and points your pages’ links at the new name. It happens straight away, so Cancel in Settings will not undo it."

    nonisolated static let renameFolderProblemEmpty: String =
        "Type the folder’s new name."

    nonisolated static let renameFolderProblemUnchanged: String =
        "That is already this folder’s name."

    nonisolated static let renameFolderProblemHasSeparator: String =
        "A folder’s name cannot contain “/” or “:”."

    nonisolated static let renameFolderProblemIsHidden: String =
        "A name starting with a dot makes the folder hidden, and Plantoir would stop finding it."

    nonisolated static let renameFolderNothingWasThere: String =
        "There was no folder by that name on your Mac, so only this course’s settings changed. Make it in Obsidian when you need it."

    nonisolated static let renameFolderProblemIsMedia: String =
        "Plantoir looks after the Media folder itself, so nothing else can be called Media."

    /// The caption under the four Content Structure lists in Course Settings.
    ///
    /// Both halves are load-bearing. The first is the promise that a teacher
    /// need not come here at all — preflight discovery appends anything new it
    /// finds at the top level, files as well as folders. The second is the one
    /// rule a teacher cannot infer and is told nowhere else on this page: an
    /// exclusion is by NAME and does not expire, so a folder or file removed
    /// here stays off the site even if it is deleted and made again in
    /// Obsidian, and only this page can undo it.
    ///
    /// Worded on Windows and chosen by Russell 2026-09-07; the mac's own
    /// sentence said the exception in a six-word bracket — "(unless you have
    /// removed them here)" — and named no remedy, which was rejected as
    /// under-weight for a permanent, silent rule with a single escape. The
    /// reasoning, the rejected alternatives and the one known edge (a name
    /// remade with different capitalisation is NOT still excluded) are in
    /// `contracts/shared-rules.json` → `specialNames.contentStructureTip.why`.
    nonisolated static let contentStructureTip: String =
        "Tip: you can also simply create new folders and files in Obsidian — they’re added to your site automatically the next time you preview. The exception is anything you remove here: it stays off your site, even if you make it again in Obsidian, until you add it back here."

    // MARK: - Functions

    nonisolated static func curriculumFolderBlockedByCurriculumPages(jurisdiction: String) -> String {
        return "This folder holds your curriculum expectations. To remove it, turn off “Include \(jurisdiction) curriculum pages” first."
    }

    nonisolated static func removeGradedFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    nonisolated static func removeCurriculumFolderTitle(for name: String) -> String {
        return "Remove “\(name)”?"
    }

    nonisolated static func renameFolderTitle(for name: String) -> String {
        return "Rename “\(name)”"
    }

    nonisolated static func renameFolderProblemAlreadyUsed(name: String) -> String {
        return "This course already has a folder called “\(name)”."
    }

    nonisolated static func renameFolderProblemLooksLikeASection(name: String) -> String {
        return "“\(name)” is what Plantoir calls a section’s own folder, so it cannot be used here."
    }

    nonisolated static func renameFolderProblemDestinationExists(name: String) -> String {
        return "There is already something called “\(name)” beside it. Move or rename that first."
    }

    nonisolated static func renameFolderDone(from oldName: String, to newName: String) -> String {
        return "“\(oldName)” is now “\(newName)”."
    }

    /// What the rename did to the teacher's links, worded for the number it
    /// actually found. Three sentences rather than one with a count in
    /// brackets: "1 pages" is the sort of thing a teacher notices and stops
    /// trusting, and "no page linked into it" is worth saying out loud rather
    /// than leaving as silence that could equally mean nothing was checked.
    nonisolated static func renameFolderRelinked(pages: Int) -> String {
        if pages == 0 {
            return "No page linked into it by name, so nothing else needed changing."
        }
        if pages == 1 {
            return "One page had links pointing into it, and they now point at the new name."
        }
        return "\(pages) pages had links pointing into it, and they now point at the new name."
    }

    nonisolated static func addCreatesTheFolderMessage(name: String) -> String {
        return "Plantoir made the folder “\(name)” for you. Open it in Obsidian to put pages in it."
    }

    nonisolated static func removeLeavesTheFolderOnDiskMessage(name: String) -> String {
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
    nonisolated static func resolvedCurriculumFolder(
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
