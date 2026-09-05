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
    nonisolated static let fallbackName: String = "All Classes"

    // MARK: - Functions

    /// The class folder's name: the course's own `class_folder` FIRST, when it
    /// is set and still one of the per-section folders, and only then the old
    /// guess.
    ///
    /// **Why the key exists.** Guessing by the word "class" quietly decided
    /// what a teacher was allowed to call this folder. A teacher whose
    /// vocabulary is "Thread 2, Day 3" would sensibly call it "All Days" — and
    /// under the guess alone that folder is not found, so the first
    /// per-section folder is used instead and the curriculum map counts the
    /// wrong pages. The map does not FAIL when that happens: it falls back to
    /// counting every published page, which is a wrong map that reports
    /// success. Recording the answer is what makes the vocabulary the
    /// teacher's rather than Plantoir's.
    ///
    /// The guess is KEPT as the fallback rather than replaced, because every
    /// course made before this key existed has no `class_folder` and must go
    /// on working exactly as it did.
    ///
    /// Substring matching is safe HERE because the list is a short curated one
    /// the teacher chose. It is NOT safe against arbitrary paths, which is what
    /// `isClassPage(relativePathComponents:classFolder:)` is careful about.
    nonisolated static func name(inPerSectionFolders folders: [String], configured: String? = nil) -> String {
        if let recorded = ClassFolder.matching(configured, in: folders) {
            return recorded
        }
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
        return name(
            inPerSectionFolders: course.configuration.perSectionFolders,
            configured: course.configuration.classFolder
        )
    }

    /// The configured name as it is spelled in the folder list, or nil when
    /// nothing is configured or the configured name is no longer there.
    ///
    /// Returning the LIST's spelling rather than the configured one matters:
    /// the two can differ in case, and everything downstream builds file paths
    /// out of the answer.
    nonisolated static func matching(_ configured: String?, in folders: [String]) -> String? {
        let wanted: String = (configured ?? "").trimmingCharacters(in: .whitespaces)
        if wanted.isEmpty {
            return nil
        }
        for folder in folders {
            if folder.caseInsensitiveCompare(wanted) == .orderedSame {
                return folder
            }
        }
        return nil
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
    /// The class-mentioning folders are still counted when `class_folder` is
    /// set, and that is deliberate: dropping them would SHRINK what a course is
    /// seen to teach, which is the direction that produces the wrong map.
    /// Adding the configured folder can only widen it.
    nonisolated static func names(inPerSectionFolders folders: [String], configured: String? = nil) -> [String] {
        var counting: [String] = []
        if let recorded = ClassFolder.matching(configured, in: folders) {
            counting.append(recorded)
        }
        for folder in folders {
            if folder.lowercased().contains("class") && !counting.contains(folder) {
                counting.append(folder)
            }
        }
        if !counting.isEmpty {
            return counting
        }
        return [name(inPerSectionFolders: folders, configured: configured)]
    }

    static func names(for course: Course) -> [String] {
        return names(
            inPerSectionFolders: course.configuration.perSectionFolders,
            configured: course.configuration.classFolder
        )
    }

    /// Whether a per-section folder is the one a teacher can never remove
    /// (Russell, 2026-08-24) — the course's RECORDED class folder, or failing
    /// that the literal "All Classes". Compared without regard to case; every
    /// other name, class-mentioning or not, is removable.
    ///
    /// The recorded name is checked as well as the literal one, and only as
    /// well: a course made before `class_folder` existed has no recorded name
    /// and keeps exactly the rule it had. Without the addition, renaming
    /// "All Classes" to "All Days" would leave the course's class folder
    /// removable — and removing it takes every lesson off the site while the
    /// coverage map quietly starts counting every published page instead.
    nonisolated static func isTheAllClassesFolder(_ folder: String, configured: String? = nil) -> Bool {
        if let recorded = configured?.trimmingCharacters(in: .whitespaces), !recorded.isEmpty {
            if folder.caseInsensitiveCompare(recorded) == .orderedSame {
                return true
            }
        }
        return folder.lowercased() == fallbackName.lowercased()
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
    nonisolated static func isClassPage(relativePathComponents components: [String], classFolders: [String]) -> Bool {
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
    nonisolated static func isClassPage(relativePath path: String, classFolders: [String]) -> Bool {
        var components: [String] = []
        for piece in path.split(whereSeparator: { character in
            return character == "/" || character == "\\"
        }) {
            components.append(String(piece))
        }
        return isClassPage(relativePathComponents: components, classFolders: classFolders)
    }
}
