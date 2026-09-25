import Foundation

/// Answers one question for the new-course wizard: what shape should a
/// course start in when it is not taking ready-made example content?
///
/// Thirty-eight course codes have real example content written for them.
/// Every other Ontario code — around 1,900 of them — has a SKELETON
/// instead: folders that suit the subject, a semester of class pages to
/// rename, a site tour, and placeholder pages saying what belongs where.
/// The pages live in the bundled `support/skeletons/<family>/` folders and
/// are installed by the real setup wizard; the app only needs to know which
/// family a code belongs to, so the folder list it offers matches the pages
/// that will arrive.
///
/// A code with example content has a skeleton too, and gets it the moment
/// the teacher turns the example content down — see
/// `hasSkeleton(forCode:takingExampleContent:numbered:)`, which is the one place
/// that rule lives.
///
/// The mapping is by three-letter prefix — ADA is drama, AMU is music, SCH
/// is chemistry, MCV is calculus — falling back to a generic skeleton for
/// club and custom codes.
enum SkeletonCatalog {

    // MARK: - Types

    /// One subject family's shape, as its manifest describes it.
    struct Family {
        let name: String
        let label: String
        let sharedFolders: [String]
        let sharedFiles: [String]
        let perSectionFolders: [String]
        let perSectionFiles: [String]
        let hidden: [String]
        let expandable: [String]
        let curriculumFolder: String?
        let gradedFolders: [String]
    }

    // MARK: - Stored properties

    /// The family a code with no subject of its own falls back to — club
    /// codes, custom codes, and any prefix the map does not carry. Named
    /// here because its own label ("This Course") is written for the
    /// skeleton's PAGES rather than for a sentence, so the wizard has a
    /// sentence of its own for it (`WizardWording.skeletonToggleLabel`).
    nonisolated static let generalFamilyName: String = "general"

    // MARK: - Functions

    /// The family name for a course code, from the bundled prefix map.
    static func familyName(forCode code: String) -> String? {
        let normalized: String = code.trimmingCharacters(in: .whitespaces).uppercased()
        if normalized.isEmpty {
            return nil
        }
        guard let mapURL = Bundle.main.url(
            forResource: "families", withExtension: "json", subdirectory: "support/skeletons"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: mapURL),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let map = decoded as? [String: Any] else {
            return nil
        }
        if let prefixes = map["prefixes"] as? [String: String] {
            let prefixLengths: [Int] = [5, 4, 3, 2]
            for length in prefixLengths {
                if normalized.count >= length {
                    let prefix: String = String(normalized.prefix(length))
                    if let name = prefixes[prefix] {
                        return name
                    }
                }
            }
        }
        return map["default"] as? String
    }

    /// The shape a course of this code should start in, or nil when no
    /// skeleton is bundled.
    static func family(forCode code: String) -> Family? {
        guard let name = familyName(forCode: code) else {
            return nil
        }
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest", withExtension: "json",
            subdirectory: "support/skeletons/\(name)"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let manifest = decoded as? [String: Any] else {
            return nil
        }
        func list(_ key: String) -> [String] {
            return (manifest[key] as? [String]) ?? []
        }
        return Family(
            name: name,
            label: (manifest["label"] as? String) ?? "this subject",
            sharedFolders: list("shared_folders"),
            sharedFiles: list("shared_files"),
            perSectionFolders: list("per_section_folders"),
            perSectionFiles: list("per_section_files"),
            hidden: list("hidden"),
            expandable: list("expandable"),
            curriculumFolder: manifest["curriculum_folder"] as? String,
            gradedFolders: list("graded_folders")
        )
    }

    /// Every bundled family name, so the wizard can tell one of its own
    /// offered folder lists from a list the teacher has edited.
    static func everyFamilyName() -> [String] {
        guard let mapURL = Bundle.main.url(
            forResource: "families", withExtension: "json", subdirectory: "support/skeletons"
        ) else {
            return []
        }
        guard let data = try? Data(contentsOf: mapURL),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let map = decoded as? [String: Any],
              let prefixes = map["prefixes"] as? [String: String] else {
            return []
        }
        return Array(Set(prefixes.values)).sorted()
    }

    /// A family by name, for the same reason.
    static func family(named name: String) -> Family? {
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest", withExtension: "json",
            subdirectory: "support/skeletons/\(name)"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let manifest = decoded as? [String: Any] else {
            return nil
        }
        func list(_ key: String) -> [String] {
            return (manifest[key] as? [String]) ?? []
        }
        return Family(
            name: name,
            label: (manifest["label"] as? String) ?? "this subject",
            sharedFolders: list("shared_folders"),
            sharedFiles: list("shared_files"),
            perSectionFolders: list("per_section_folders"),
            perSectionFiles: list("per_section_files"),
            hidden: list("hidden"),
            expandable: list("expandable"),
            curriculumFolder: manifest["curriculum_folder"] as? String,
            gradedFolders: list("graded_folders")
        )
    }

    /// The structure a course of this code should adopt, or nil when
    /// nothing should change: either no skeleton is offered for it at all
    /// (`hasSkeleton(forCode:takingExampleContent:numbered:)` — the example content
    /// the teacher is TAKING chooses its own folders), or the teacher has
    /// edited the folder list and their edit must survive a change to the
    /// code.
    static func structureToAdopt(forCode code: String,
                                 takingExampleContent: Bool,
                                 numbered: Bool,
                                 currentSharedFolders: [String]) -> Family? {
        if !hasSkeleton(forCode: code, takingExampleContent: takingExampleContent, numbered: numbered) {
            return nil
        }
        guard let candidate = family(forCode: code) else {
            return nil
        }
        if candidate.sharedFolders == currentSharedFolders {
            return nil
        }
        if !isOffered(currentSharedFolders) {
            return nil
        }
        return candidate
    }

    /// Which of a skeleton's folders count for marks when the wizard adopts
    /// it: the manifest's own `graded_folders` where it names any, and
    /// otherwise the historical rule read off the family's own folders.
    ///
    /// The manifest wins for a reason a teacher would notice — the
    /// mathematics family ships `Thinking Tasks` rather than `Tasks`, and the
    /// generic rule finds it only because it says "task" at all. Windows'
    /// `SkeletonCatalog.AdoptedGradedFolders` is the same function under the
    /// same name, so the same code opens with the same marks pool on both
    /// platforms.
    static func adoptedGradedFolders(for family: Family) -> [String] {
        if !family.gradedFolders.isEmpty {
            return family.gradedFolders
        }
        return GradedFolderRule.inferredPool(
            from: family.sharedFolders + family.perSectionFolders
        )
    }

    /// True when a folder list is still one the app offered, rather than
    /// one the teacher has changed.
    static func isOffered(_ folders: [String]) -> Bool {
        if folders == WizardDefaults.sharedFolders || folders == WizardDefaults.lcsSharedFolders {
            return true
        }
        for name in everyFamilyName() {
            if let candidate = family(named: name), candidate.sharedFolders == folders {
                return true
            }
        }
        return false
    }

    /// The sidebar for a course built from a skeleton: what stays out of
    /// the explorer, and what carries a chevron.
    ///
    /// Expandability is structural rather than a fixed list, so a folder
    /// the teacher adds is a section like any other — every visible SHARED
    /// folder gets a chevron. The curriculum folder is never visible (the
    /// courses with real content hide it too, and a wall of expectation
    /// codes is not navigation), and the per-section All Classes stays a
    /// plain link to its listing.
    static func sidebar(for family: Family,
                        sharedFolders: [String],
                        sharedFiles: [String],
                        perSectionFolders: [String],
                        perSectionFiles: [String]) -> (hidden: [String], expandable: [String]) {
        var hidden: [String] = ["Media"]
        for item in family.hidden {
            let exists: Bool = sharedFolders.contains(item)
                || sharedFiles.contains(item)
                || perSectionFolders.contains(item)
                || perSectionFiles.contains(item)
            if exists && !hidden.contains(item) {
                hidden.append(item)
            }
        }
        var expandable: [String] = []
        for item in sharedFolders where !hidden.contains(item) {
            expandable.append(item)
        }
        return (hidden, expandable)
    }

    /// True when a skeleton is OFFERED for this code: a family exists for
    /// its prefix AND the teacher is not taking the example content written
    /// for it.
    ///
    /// The whole rule, in one place, because three surfaces ask it — the
    /// wizard's Starting Content section, the structure editor's adoption
    /// (`structureToAdopt`), and the config writer's `use_skeleton`. Three
    /// copies were what let them disagree.
    ///
    /// Example content is better than a skeleton, which is why it wins
    /// whenever a teacher is taking it. It is not better than a skeleton
    /// when they have just turned it DOWN, and until 2026-09-21 this
    /// returned false for all 38 payload codes whatever the teacher chose —
    /// so declining the ready-made pages gave EMPTY folders (measured: an
    /// ICS4U made that way has 18 pages against the skeleton's 47, and
    /// `course_config.json` said `use_skeleton: false` whatever the wizard
    /// had shown). GitHub issue #248; Windows'
    /// `SkeletonCatalog.HasSkeleton` takes the same parameter.
    ///
    /// `takingExampleContent:` has no default value on purpose: a call site
    /// that has not been made to think about the example-content toggle
    /// should fail to compile rather than quietly pick an answer.
    ///
    /// `numbered:` is a club (#267): its pages are "Week 1", "Week 2", and
    /// every skeleton's class pages are "Unit 1, Day 1" — which a numbered
    /// course does not read as class pages at all, so every planner would
    /// see nothing and the build would report success. No skeleton is
    /// offered, and no default either, for the same reason as above.
    static func hasSkeleton(forCode code: String, takingExampleContent: Bool, numbered: Bool) -> Bool {
        if numbered {
            return false
        }
        if takingExampleContent && ExampleContentCatalog.hasContent(forCode: code) {
            return false
        }
        return family(forCode: code) != nil
    }
}
