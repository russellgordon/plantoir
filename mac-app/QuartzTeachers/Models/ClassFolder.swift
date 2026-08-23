import Foundation

/// Which folder holds a section's class pages, and whether a given page is one
/// of them.
///
/// **One rule, because there were four and they disagreed.** The mac app asked
/// the course's configured folder list; `AssistSectionGraph` sniffed a page's
/// immediate parent for the word "class"; the Windows app tested the whole
/// directory string; and `build_site.py` matched the exact strings
/// "all classes" and "classes" against every path segment INCLUDING the file
/// name. A teacher whose folder was called anything else got a different answer
/// from each — and the build's answer silently changed the Curriculum Coverage
/// map from "pages the course teaches" to "every published page", which is a
/// wrong map that reports success.
///
/// Pinned by `contracts/class-planning.json` → `classFolder`, which the Windows
/// suite and `scripts/test_class_folder.py` run against their own
/// implementations of the same rule.
enum ClassFolder {

    // MARK: - Stored properties

    /// The name used when a course has no per-section folders configured at
    /// all, so a section still has a predictable answer rather than an empty
    /// path.
    static let fallbackName: String = "All Classes"

    // MARK: - Functions

    /// The class folder's name, read from the course's own configured
    /// per-section folders rather than guessed from what is on disk.
    ///
    /// Substring matching is safe HERE because the list is a short curated one
    /// the teacher chose. It is NOT safe against arbitrary paths, which is what
    /// `isClassPage(relativePathComponents:classFolder:)` is careful about.
    static func name(inPerSectionFolders folders: [String]) -> String {
        for folder in folders {
            if folder.lowercased().contains("class") {
                return folder
            }
        }
        if let first = folders.first {
            return first
        }
        return fallbackName
    }

    /// The class folder's name for a course.
    static func name(for course: Course) -> String {
        return name(inPerSectionFolders: course.configuration.perSectionFolders)
    }

    /// WHICH FOLDERS COUNT as holding class pages — every configured
    /// per-section folder whose name mentions classes, and failing that the
    /// single name `name(inPerSectionFolders:)` chose.
    ///
    /// Naming and membership are the same question only when a course has ONE
    /// such folder. A course configured `["Class Resources", "All Classes"]`
    /// would otherwise resolve to "Class Resources" for both, match zero
    /// pages, and drop the coverage map back to "every published page" —
    /// reintroducing the exact silent failure this rule was written to close.
    /// Writing goes to one folder; counting looks at all of them.
    static func names(inPerSectionFolders folders: [String]) -> [String] {
        var mentioningClasses: [String] = []
        for folder in folders {
            if folder.lowercased().contains("class") {
                mentioningClasses.append(folder)
            }
        }
        if !mentioningClasses.isEmpty {
            return mentioningClasses
        }
        return [name(inPerSectionFolders: folders)]
    }

    static func names(for course: Course) -> [String] {
        return names(inPerSectionFolders: course.configuration.perSectionFolders)
    }

    /// Whether a page is one of the section's class pages, given its path
    /// components RELATIVE to the content root (or the section folder).
    ///
    /// **Relative, never absolute.** Every implementation had this wrong
    /// somewhere: `build_site.py` walked the segments of an ABSOLUTE path,
    /// Windows tested the whole directory string, and this app's own
    /// `AssistSectionPage.relativePath` returns the FULL ABSOLUTE PATH when
    /// `workspaceURL` is nil — which `SectionIndexPointer.repointIndex`
    /// passes. A teacher whose working folder was `~/Documents/All Classes`
    /// made every page in every course a class page. Where a teacher keeps
    /// their files is not a fact about their lessons.
    ///
    /// The file name is excluded as defence in depth rather than to fix an
    /// observed bug: under segment EQUALITY a file name cannot collide with a
    /// folder name, but a future change to prefix or substring matching must
    /// not silently start counting a page because of what it is CALLED.
    static func isClassPage(relativePathComponents components: [String], classFolders: [String]) -> Bool {
        guard let fileName = components.last else {
            return false
        }
        if fileName.lowercased() == "index.md" {
            return false
        }
        var wanted: Set<String> = []
        for folder in classFolders {
            wanted.insert(folder.lowercased())
        }
        for component in components.dropLast() {
            if wanted.contains(component.lowercased()) {
                return true
            }
        }
        return false
    }

    /// The same question asked of a relative path written as one string, with
    /// either separator — what the contract's cases carry, and what arrives
    /// from a platform that spells paths the other way.
    static func isClassPage(relativePath path: String, classFolders: [String]) -> Bool {
        var components: [String] = []
        for piece in path.split(whereSeparator: { character in
            return character == "/" || character == "\\"
        }) {
            components.append(String(piece))
        }
        return isClassPage(relativePathComponents: components, classFolders: classFolders)
    }
}
