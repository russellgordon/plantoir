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

    /// Whether a page is one of the section's class pages, given its path
    /// components RELATIVE to the content root (or the working folder).
    ///
    /// Two things this is deliberately careful about, both of which were real
    /// bugs:
    ///
    /// * **Folder segments only, never the file name.** The build's rule ran
    ///   over every component including the file name, so "How This Class
    ///   Works.md" — which ships in about twenty payloads — and ADA1O's
    ///   curriculum page "B3. Connections Beyond the Classroom.md" counted as
    ///   lessons, inflating what the course was judged to teach.
    /// * **Relative, never absolute.** Windows tested the whole directory
    ///   string, so a teacher whose working folder was `C:\Users\x\Classroom\`
    ///   made every page in every course a class page. Where a teacher keeps
    ///   their files is not a fact about their lessons.
    static func isClassPage(relativePathComponents components: [String], classFolder: String) -> Bool {
        guard let fileName = components.last else {
            return false
        }
        if fileName.lowercased() == "index.md" {
            return false
        }
        let wanted: String = classFolder.lowercased()
        for component in components.dropLast() {
            if component.lowercased() == wanted {
                return true
            }
        }
        return false
    }

    /// The same question asked of a relative path written as one string, with
    /// either separator — what the contract's cases carry.
    static func isClassPage(relativePath path: String, classFolder: String) -> Bool {
        var components: [String] = []
        for piece in path.split(whereSeparator: { character in
            return character == "/" || character == "\\"
        }) {
            components.append(String(piece))
        }
        return isClassPage(relativePathComponents: components, classFolder: classFolder)
    }
}
