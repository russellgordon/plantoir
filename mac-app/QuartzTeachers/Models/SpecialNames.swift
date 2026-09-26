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

    /// Asked, rather than refused, when the map is on and the course has
    /// another curriculum folder with a map (#128). It does not promise that
    /// another map stays: on a course whose second folder is still empty, it
    /// would not.
    nonisolated static let removeCurriculumFolderWithItsMapMessage: String =
        "This folder holds curriculum expectations with a coverage map of their own. Removing it takes that map off your website."

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

    /// Beside "Saved ✓" in Course Settings when a preview of this course is
    /// open (issue #265). A preview bakes every setting in when its build
    /// starts, so a Save changes nothing it shows until it is built again —
    /// measured: 20 s after a save, the served sidebar filter was unchanged.
    /// The Preview Again button beside it rebuilds the open preview. About
    /// EVERY setting, not only the sidebar: footer, colours and reading time
    /// are baked in the same way. `contracts/shared-rules.json` →
    /// `specialNames.settingsSavedWhilePreviewing`.
    nonisolated static let settingsSavedWhilePreviewing: String =
        "A preview of this course is still showing the settings it started with. Press Preview Again to see what you just saved."

    /// Beside "Saved ✓" when a publish of this course is running. The publish
    /// read the settings when its build began, so it sends the earlier ones.
    /// "Publish again" is TRUE advice: the next Publish compares the course
    /// with the time that build STARTED (`BuildFreshness.needsRebuild`), so a
    /// Save made during it makes the next one build afresh — before that
    /// fix it called the site up to date and sent the same build. Said
    /// rather than blocked: the Save itself is right.
    /// `specialNames.settingsSavedWhilePublishing`.
    nonisolated static let settingsSavedWhilePublishing: String =
        "This course is being published right now, and that publish uses the settings from before this save. Publish again once it has finished to send what you just saved."

    /// After a Save that found the sidebar list had ALSO been changed in the
    /// file since this window read it — another window on the same folder,
    /// most likely — and wrote this window's list over it (issue #265, the
    /// review's M2). The last Save wins, by the director's ruling for Russell,
    /// 2026-09-24: no merge of two lists, but never silently.
    /// `specialNames.settingsSaveReplacedSidebarChange`.
    nonisolated static let settingsSaveReplacedSidebarChange: String =
        "Which items the sidebar hides had also been changed somewhere else since this window read them — most likely in another Plantoir window. This save replaced that change with the switches shown here."

    /// In place of Preview Again when the preview that was open at the Save
    /// has stopped since, or its window has closed — the button would do
    /// nothing (issue #265, the review's L2).
    /// `specialNames.settingsPreviewAgainNothingOpen`.
    nonisolated static let settingsPreviewAgainNothingOpen: String =
        "That preview has stopped since, so there is nothing to preview again. Open the section and press Preview to see what you saved."

    /// Where a preview's progress appears, when it starts while Course
    /// Settings holds changes nobody saved — in ANY window on the folder, not
    /// only this one (the review's L1). A preview reads the saved file,
    /// so the switches on screen and the preview can disagree with nothing
    /// said. Not auto-saved (a half-typed setting would be written) and not
    /// blocked (previewing the saved settings may be the point).
    /// `specialNames.previewUsesSavedSettings`.
    nonisolated static let previewUsesSavedSettings: String =
        "Course Settings has changes you have not saved, so this preview uses the settings as they were last saved."

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

/// Which folders hold a course's curriculum expectation pages (#128).
///
/// A course can have SEVERAL — an Ontario and a College Board folder — and
/// each one that holds an expectation page gets a coverage map of its own. The
/// build decides which (`configured_curriculum_folders`, `plan_coverage_maps`
/// in `scripts/build_site.py`); this is the same rule, over the course's
/// SHARED folders, and both are pinned by `contracts/shared-rules.json` →
/// `specialNames.curriculumFoldersResolution`.
///
/// Three answers, because three questions are asked:
/// - `declaredFolders` — what the course has written down: `curriculum_folders`
///   in order, then the legacy `curriculum_folder`.
/// - `mappedFolders` — what the BUILD maps: every declared folder holding an
///   expectation page, or, when none does, the one folder the old scan finds.
/// - `resolvedFolders` — what the apps protect and name: `mappedFolders`, or
///   while no folder holds a page yet, the single folder the by-name rule
///   gives, so a course whose folders are still empty is protected exactly as
///   it was before.
enum CurriculumFolderRule {

    // MARK: - Functions

    /// The names a course declares: `curriculum_folders` (a list), then the
    /// legacy `curriculum_folder` when it is not already there. Non-strings,
    /// empty names, path-like names and repeats in any letter case are dropped
    /// — the build refuses the same ones, because each is used to build a path.
    nonisolated static func declaredFolders(list: Any?, legacy: Any?) -> [String] {
        var candidates: [Any] = []
        if let entries = list as? [Any] {
            for entry in entries {
                candidates.append(entry)
            }
        }
        if let legacy {
            candidates.append(legacy)
        }
        var names: [String] = []
        var seen: Set<String> = []
        for candidate in candidates {
            guard let name = candidate as? String, isSingleFolderName(name) else {
                continue
            }
            let key: String = name.lowercased()
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            names.append(name)
        }
        return names
    }

    /// The folders the build draws a coverage map from, primary first.
    ///
    /// `withPages` names the folders (as the LIST spells them) that hold at
    /// least one expectation page.
    nonisolated static func mappedFolders(declared: [String], in folders: [String], withPages: [String]) -> [String] {
        var mapped: [String] = []
        for name in declared {
            guard let folder = folderNamed(name, in: folders) else {
                continue
            }
            if mapped.contains(folder) || !withPages.contains(folder) {
                continue
            }
            mapped.append(folder)
        }
        if !mapped.isEmpty {
            return mapped
        }
        for candidate in foldersMentioningTheCurriculum(in: folders) {
            if withPages.contains(candidate) {
                return [candidate]
            }
        }
        return []
    }

    /// The folders the apps protect and name: the mapped ones, or — while no
    /// folder holds an expectation page — the ONE folder the by-name rule
    /// gives: the first declared name the course has, else the alphabetically
    /// first folder whose name mentions the curriculum.
    nonisolated static func resolvedFolders(declared: [String], in folders: [String], withPages: [String]) -> [String] {
        let mapped: [String] = mappedFolders(declared: declared, in: folders, withPages: withPages)
        if !mapped.isEmpty {
            return mapped
        }
        for name in declared {
            if let folder = folderNamed(name, in: folders) {
                return [folder]
            }
        }
        if let first = foldersMentioningTheCurriculum(in: folders).first {
            return [first]
        }
        return []
    }

    /// The title of each map over `mapped`, in order: the primary folder's map
    /// is "Curriculum Coverage", every other "<Folder> Coverage", and a title
    /// that would repeat an earlier one gets " (2)", " (3)"…
    /// `contracts/shared-rules.json` → `curriculumRules.coveragePageTitles`.
    nonisolated static func coveragePageTitles(for mapped: [String], primary: String?) -> [String] {
        var titles: [String] = []
        var taken: Set<String> = []
        for name in mapped {
            var title: String
            if let primary, name.lowercased() == primary.lowercased() {
                title = CurriculumFolderRule.primaryMapTitle
            } else {
                title = "\(name) Coverage"
            }
            let base: String = title
            var number: Int = 2
            while taken.contains(title.lowercased()) {
                title = "\(base) (\(number))"
                number += 1
            }
            taken.insert(title.lowercased())
            titles.append(title)
        }
        return titles
    }

    /// The primary folder: the first declared name, when any declared folder
    /// has a map; otherwise the one folder the scan found.
    nonisolated static func primaryFolder(declared: [String], mapped: [String]) -> String? {
        for folder in mapped {
            for name in declared {
                if name.lowercased() == folder.lowercased() {
                    return declared.first
                }
            }
        }
        return mapped.first
    }

    /// Every map's title for a course, from the declared names and the disk.
    nonisolated static func coveragePageTitles(declared: [String], in folders: [String], withPages: [String]) -> [String] {
        let mapped: [String] = mappedFolders(declared: declared, in: folders, withPages: withPages)
        return coveragePageTitles(for: mapped, primary: primaryFolder(declared: declared, mapped: mapped))
    }

    /// Which of `names` hold at least one expectation page anywhere inside —
    /// the same test the build makes (`_holds_expectation_pages`), recursive,
    /// with the same code rule (`AssistCurriculumMentions.isExpectationCode`).
    nonisolated static func foldersHoldingExpectationPages(in courseDirectory: URL, among names: [String]) -> [String] {
        var holding: [String] = []
        for name in names {
            let folder: URL = courseDirectory.appendingPathComponent(name, isDirectory: true)
            if folderHoldsAnExpectationPage(folder) {
                holding.append(name)
            }
        }
        return holding
    }

    /// The names worth looking inside: every declared folder the course has,
    /// and every folder whose name mentions the curriculum.
    nonisolated static func candidateFolders(declared: [String], in folders: [String]) -> [String] {
        var candidates: [String] = []
        for name in declared {
            if let folder = folderNamed(name, in: folders), !candidates.contains(folder) {
                candidates.append(folder)
            }
        }
        for folder in folders {
            if folder.lowercased().contains("curriculum") && !candidates.contains(folder) {
                candidates.append(folder)
            }
        }
        return candidates
    }

    /// The declared names of a course's configuration.
    static func declaredFolders(of configuration: CourseConfiguration) -> [String] {
        return configuration.curriculumFolders
    }

    /// The folders of `course` holding expectation pages, read from its folder.
    ///
    /// Asked once per row when Course Settings draws its folder lists, so the
    /// answer is kept for a moment per course and per candidate list: a walk of
    /// a hundred-page folder for each of a dozen rows on every redraw is work
    /// for nothing. The window is short because a teacher can add the first
    /// page in Obsidian while the window is open.
    static func foldersWithPages(for course: Course) -> [String] {
        let configuration: CourseConfiguration = course.configuration
        let candidates: [String] = candidateFolders(declared: declaredFolders(of: configuration),
                                                    in: configuration.sharedFolders)
        let key: String = course.directoryURL.path + "\u{0}" + candidates.joined(separator: "\u{0}")
        let now: Date = Date()
        if let remembered = recentlyRead[key], now.timeIntervalSince(remembered.when) < 2 {
            return remembered.holding
        }
        let holding: [String] = foldersHoldingExpectationPages(in: course.directoryURL, among: candidates)
        recentlyRead[key] = (when: now, holding: holding)
        return holding
    }

    /// See `foldersWithPages(for:)`.
    private static var recentlyRead: [String: (when: Date, holding: [String])] = [:]

    /// The curriculum folders of a course, for protection and the help sheet.
    static func resolvedFolders(for course: Course) -> [String] {
        let configuration: CourseConfiguration = course.configuration
        return resolvedFolders(declared: declaredFolders(of: configuration),
                               in: configuration.sharedFolders,
                               withPages: foldersWithPages(for: course))
    }

    // MARK: - Stored properties

    /// The one title every course with one map has always had.
    nonisolated static let primaryMapTitle: String = "Curriculum Coverage"

    // MARK: - Private helpers

    /// The folder in the list a name refers to: the exact spelling first, then
    /// in any letter case — and the LIST's spelling is returned, because
    /// everything downstream builds paths and titles from the answer.
    nonisolated private static func folderNamed(_ name: String, in folders: [String]) -> String? {
        for folder in folders where folder == name {
            return folder
        }
        for folder in folders where folder.lowercased() == name.lowercased() {
            return folder
        }
        return nil
    }

    nonisolated private static func foldersMentioningTheCurriculum(in folders: [String]) -> [String] {
        var candidates: [String] = []
        for folder in folders {
            if folder.lowercased().contains("curriculum") {
                candidates.append(folder)
            }
        }
        candidates.sort()
        return candidates
    }

    nonisolated private static func isSingleFolderName(_ name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." {
            return false
        }
        if name.contains("/") || name.contains("\\") {
            return false
        }
        return true
    }

    nonisolated private static func folderHoldsAnExpectationPage(_ folder: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() != "md" {
                continue
            }
            if AssistCurriculumMentions.isExpectationCode(url.deletingPathExtension().lastPathComponent) {
                return true
            }
        }
        return false
    }
}

/// What removing a curriculum folder does (#128): refused only when it would
/// take the course's LAST map away, asked first otherwise.
/// `contracts/shared-rules.json` → `specialNames.curriculumFolderProtection`.
enum CurriculumFolderProtection {

    // MARK: - Stored properties

    nonisolated enum Surface {
        case settings
        case wizard
    }

    // MARK: - Functions

    /// The protection for `folder`, or nil when it is not one of the
    /// `resolved` curriculum folders and the other rules (the marks pool)
    /// decide. `jurisdiction` words the wizard's pages sentence.
    nonisolated static func decide(
        folder: String,
        resolved: [String],
        coverageOn: Bool,
        pagesOn: Bool,
        declaredPayloadFolder: String?,
        surface: Surface,
        jurisdiction: String
    ) -> ItemProtection? {
        if !resolved.contains(folder) {
            return nil
        }
        if coverageOn && resolved.count == 1 {
            switch surface {
            case .settings:
                return .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageSetting)
            case .wizard:
                return .blocked(reason: SpecialNames.curriculumFolderBlockedByCoverageMap)
            }
        }
        if surface == .wizard && pagesOn && folder == declaredPayloadFolder {
            return .blocked(reason: SpecialNames.curriculumFolderBlockedByCurriculumPages(jurisdiction: jurisdiction))
        }
        if coverageOn {
            return .consequential(
                title: SpecialNames.removeCurriculumFolderTitle(for: folder),
                message: SpecialNames.removeCurriculumFolderWithItsMapMessage
            )
        }
        return .consequential(
            title: SpecialNames.removeCurriculumFolderTitle(for: folder),
            message: SpecialNames.removeCurriculumFolderMessage
        )
    }
}

/// The "Curriculum folders" checkboxes in Course Settings and the wizard
/// (#128): the apps OFFER to declare a folder; neither declares one silently.
/// `contracts/shared-rules.json` → `specialNames.curriculumFoldersOffer`.
enum CurriculumFoldersOffer {

    // MARK: - Stored properties

    nonisolated static let label: String = "Curriculum folders"

    nonisolated static let caption: String =
        "Tick each folder that holds curriculum expectations. Each one gets its own coverage map on your website."

    /// Why the last ticked folder cannot be unticked.
    nonisolated static let lastStaysTicked: String =
        "At least one curriculum folder stays ticked, so your course keeps its coverage map. Tick another folder first."

    // MARK: - Functions

    /// The folders offered as checkboxes, in the list's order: every folder
    /// whose name mentions the curriculum, and every declared folder — or none
    /// at all when there are fewer than two, since there is nothing to choose.
    nonisolated static func offered(folders: [String], declared: [String]) -> [String] {
        var offered: [String] = []
        for folder in folders {
            var isDeclared: Bool = false
            for name in declared where name.lowercased() == folder.lowercased() {
                isDeclared = true
            }
            if isDeclared || folder.lowercased().contains("curriculum") {
                offered.append(folder)
            }
        }
        if offered.count < 2 {
            return []
        }
        return offered
    }

    /// The folders shown ticked: the ones the build maps, or — while none
    /// holds a page — the declared folders the course has. Never a folder
    /// just because of its name.
    nonisolated static func ticked(folders: [String], declared: [String], mapped: [String]) -> [String] {
        if !mapped.isEmpty {
            return mapped
        }
        var ticked: [String] = []
        for name in declared {
            for folder in folders where folder.lowercased() == name.lowercased() && !ticked.contains(folder) {
                ticked.append(folder)
            }
        }
        return ticked
    }

    /// The `curriculum_folders` a tick writes: the folders already ticked, in
    /// their order, so the primary stays primary; then the new one.
    nonisolated static func ticking(_ folder: String, ticked: [String], folders: [String]) -> [String] {
        var written: [String] = ticked
        if !written.contains(folder) {
            written.append(folder)
        }
        return keepingOrder(written, resolvedFirst: ticked, folders: folders)
    }

    /// What an untick writes: the ticked folders without it — or nil when it
    /// is the last one, which stays ticked.
    nonisolated static func unticking(_ folder: String, ticked: [String]) -> [String]? {
        if !canUntick(folder, ticked: ticked) {
            return nil
        }
        var written: [String] = []
        for name in ticked where name != folder {
            written.append(name)
        }
        return written
    }

    nonisolated static func canUntick(_ folder: String, ticked: [String]) -> Bool {
        return ticked.contains(folder) && ticked.count > 1
    }

    /// The resolved folders in their own order, then everything else in the
    /// order the list shows it.
    nonisolated private static func keepingOrder(_ names: [String], resolvedFirst: [String], folders: [String]) -> [String] {
        var ordered: [String] = []
        for name in resolvedFirst where names.contains(name) {
            ordered.append(name)
        }
        for folder in folders where names.contains(folder) && !ordered.contains(folder) {
            ordered.append(folder)
        }
        for name in names where !ordered.contains(name) {
            ordered.append(name)
        }
        return ordered
    }
}
