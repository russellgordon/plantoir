import Foundation

/// Answers one question for the new-course wizard: what shape should a
/// course start in when no ready-made example content exists for its code?
///
/// Eighteen course codes have real example content. Every other Ontario
/// code — around 1,900 of them — gets a SKELETON instead: folders that suit
/// the subject, a semester of class pages to rename, a site tour, and
/// placeholder pages saying what belongs where. The pages live in the
/// bundled `support/skeletons/<family>/` folders and are installed by the
/// real setup wizard; the app only needs to know which family a code
/// belongs to, so the folder list it offers matches the pages that will
/// arrive.
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
    }

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
            expandable: list("expandable")
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
            expandable: list("expandable")
        )
    }

    /// The structure a course of this code should adopt, or nil when
    /// nothing should change: either the code has real example content
    /// (which chooses its own folders), or the teacher has edited the
    /// folder list and their edit must survive a change to the code.
    static func structureToAdopt(forCode code: String, currentSharedFolders: [String]) -> Family? {
        if ExampleContentCatalog.hasContent(forCode: code) {
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

    /// True when a skeleton would be offered for this code — which is only
    /// when there is no example content, since example content is better.
    static func hasSkeleton(forCode code: String) -> Bool {
        if ExampleContentCatalog.hasContent(forCode: code) {
            return false
        }
        return family(forCode: code) != nil
    }
}
