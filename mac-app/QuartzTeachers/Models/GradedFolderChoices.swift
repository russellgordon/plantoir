import Foundation

/// Which folders the Marks checklist may OFFER — as opposed to the rule in
/// `build_site.py` that decides which folders COUNT.
///
/// **The interaction between those two is the bug this exists for.** The build
/// matches a graded folder segment at ANY depth, and an ABSENT `graded_folders`
/// key means the teacher has never been asked, so the historical substring rule
/// still applies. A checklist offering only the course's TOP-LEVEL folders
/// therefore hands a teacher a list narrower than what the build is already
/// counting — and **the first tick freezes it**. From that tick onwards,
/// anything the build counted and the list omitted loses its marks without a
/// word: every expectation that folder addressed reads as never evaluated on
/// the Curriculum Coverage map, permanently, and nothing says so. A teacher who
/// files assessed work in `Portfolios/Tasks` is exactly that teacher.
///
/// Pinned by `contracts/shared-rules.json` → `gradedFolders.choices`, and run
/// against a real directory tree by `GradedFolderChoicesTests` here and
/// `GradedFolderChoicesTests` on Windows. Windows' half is
/// `Plantoir.Core/Models/GradedFolderChoices.cs`; the names here match it
/// deliberately, so the two files can be read against each other.
enum GradedFolderChoices {

    // MARK: - Stored properties

    /// How far below the course folder the walk goes. The course folder's
    /// immediate children are level 1, so levels 1 to 4 are offered and level
    /// 5 is not.
    ///
    /// **An affordability judgement rather than completeness**, and it is
    /// honest about that: a graded folder buried five levels down is still
    /// absent from the list. Four is far more complete than the top-level lists
    /// alone — which is what the case that mattered needed — and it is what
    /// keeps this cheap on a course of a few thousand pages. The number must
    /// keep matching Windows': a different cap on one platform would mean the
    /// two apps offer different pools for the same course, so a teacher's tick
    /// would freeze a different answer depending on which app they happened to
    /// be sitting at.
    nonisolated static let maxDepth: Int = 4

    /// Folders that are never offered, and are never walked INTO either.
    ///
    /// Build output, Plantoir's own bookkeeping, and `Media`. `Media` is
    /// defensible either way — a teacher grading video portfolios might want
    /// it — and stays out because media is not assessed work in either app
    /// today, and differing here would change what the coverage map says. The
    /// two build-output names are skipped even though built websites now live
    /// outside the course folder, so a folder left behind from before that move
    /// cannot turn up in the list.
    ///
    /// Matched EXACTLY, case included: a teacher's own folder called `media` is
    /// theirs, and is offered.
    nonisolated static let skippedFolders: Set<String> = [
        ".merged_output", "merged_output", ".internal", ".obsidian",
        "node_modules", "Media", ".git",
    ]

    // MARK: - Functions

    /// Whether a name is one of a course's section folders — `section1`,
    /// `section2` and so on.
    ///
    /// A section folder is not somewhere work lives: its CONTENTS are merged
    /// into the site and its own name never appears in a page's path there, so
    /// ticking it would count nothing. Its children are still walked, because a
    /// graded folder inside a section certainly does count.
    nonisolated static func isSectionFolder(_ name: String) -> Bool {
        let prefix: String = "section"
        guard name.lowercased().hasPrefix(prefix) else {
            return false
        }
        let digits: Substring = name.dropFirst(prefix.count)
        guard !digits.isEmpty else {
            return false
        }
        for character in digits {
            if !character.isASCII || !character.isNumber {
                return false
            }
        }
        return true
    }

    /// Everything the Marks checklist offers: the course's shared folders, then
    /// its per-section folders, then what is on disk — in that order,
    /// de-duplicated by exact name.
    ///
    /// The declared lists come first because they are what a teacher arranged
    /// deliberately; the walked names are the safety net underneath them.
    static func choices(for configuration: CourseConfiguration, nestedNames: [String]) -> [String] {
        var offered: [String] = []
        for folder in configuration.sharedFolders {
            offer(folder, into: &offered)
        }
        for folder in configuration.perSectionFolders {
            offer(folder, into: &offered)
        }
        for folder in nestedNames {
            offer(folder, into: &offered)
        }
        return offered
    }

    /// The same, walking the course folder itself.
    ///
    /// The exclusions are read here rather than asked of the caller, so the
    /// narrow pool cannot be had by writing nothing: a call site that forgot
    /// them would offer a teacher folders they had removed from the course.
    static func choices(for configuration: CourseConfiguration, courseDirectory: URL) -> [String] {
        let nestedNames: [String] = nestedFolderNames(
            inCourseDirectory: courseDirectory,
            excludedShared: configuration.excludedItems(forScope: FolderScope.shared.exclusionKey),
            excludedPerSection: configuration.excludedItems(forScope: FolderScope.perSection.exclusionKey)
        )
        return choices(for: configuration, nestedNames: nestedNames)
    }

    /// The folder names found inside a course, DEPTH-FIRST: each folder's
    /// children in case-insensitive name order, and a folder's children before
    /// its own next sibling. So `Alpha/Middle` comes before a top-level
    /// `Zebra`, and a name found in two places is kept where the walk first
    /// reaches it — which, the walk being depth-first, may be the deeper of the
    /// two.
    ///
    /// Includes the course's own top-level folders: a folder sitting on disk
    /// that is in neither copy list is added to `shared_folders` by the next
    /// build's preflight scan and counts for marks from then on, so offering it
    /// is right rather than premature.
    ///
    /// - Parameters:
    ///   - excludedShared: `excluded_items.shared`, and `excludedPerSection` is
    ///     `excluded_items.per_section`. A name the teacher has REMOVED from
    ///     the course is not offered back, and is not walked into. Without this
    ///     the removal confirmation's own promise — "Removing it will take it
    ///     out of your course's marks pool" — is broken on the very next
    ///     redraw, because the folder is still sitting on disk. Matched
    ///     exactly, case included, the same way `isExcluded(_:inScope:)` and
    ///     the build's preflight scan match.
    nonisolated static func nestedFolderNames(
        inCourseDirectory courseDirectory: URL,
        excludedShared: [String] = [],
        excludedPerSection: [String] = []
    ) -> [String] {
        var found: [String] = []
        walk(
            courseDirectory, depth: 1, scopeOfChildren: FolderScope.shared,
            found: &found, excludedShared: excludedShared, excludedPerSection: excludedPerSection
        )
        return found
    }

    // MARK: - The walk

    nonisolated private static func offer(_ name: String, into offered: inout [String]) {
        if name.isEmpty {
            return
        }
        if offered.contains(name) {
            return
        }
        offered.append(name)
    }

    /// - Parameter scopeOfChildren: which `excluded_items` scope this
    ///   directory's children are discovered into, or nil where the build
    ///   discovers nothing — the shared scope directly inside the course, the
    ///   per-section scope directly inside a section folder, and nothing
    ///   anywhere deeper.
    nonisolated private static func walk(
        _ directory: URL, depth: Int, scopeOfChildren: FolderScope?,
        found: inout [String], excludedShared: [String], excludedPerSection: [String]
    ) {
        if depth > maxDepth {
            return
        }
        // A folder that cannot be read is skipped rather than allowed to lose
        // the whole list: a course folder that is not there must still offer
        // what the course declares.
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            // Skips a folder whose name begins with a dot AND one the platform
            // marks hidden — both, which is what the contract asks for.
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        // Sorted so the list a teacher reads is the same one every time, and so
        // the contract can pin an ORDER at all. Directory enumeration order is
        // the filesystem's business and is promised by neither platform.
        let sorted: [URL] = children.sorted { left, right in
            return sortsBefore(left.lastPathComponent, right.lastPathComponent)
        }
        for child in sorted {
            let name: String = child.lastPathComponent
            let values: URLResourceValues? = try? child.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            // A symbolic link is not followed, and is not offered: what it
            // points at is not part of this course. (`isDirectory` is already
            // false for a link on this platform; the test is written out so
            // that it stays true of the code rather than of Foundation.)
            if values?.isSymbolicLink == true {
                continue
            }
            guard values?.isDirectory == true else {
                continue
            }
            if skippedFolders.contains(name) {
                continue
            }
            if let scope = scopeOfChildren,
               isExcluded(name, inScope: scope,
                          excludedShared: excludedShared, excludedPerSection: excludedPerSection) {
                continue
            }
            let isSection: Bool = isSectionFolder(name)
            if !isSection && !found.contains(name) {
                found.append(name)
            }
            walk(
                child, depth: depth + 1,
                scopeOfChildren: isSection ? FolderScope.perSection : nil,
                found: &found, excludedShared: excludedShared, excludedPerSection: excludedPerSection
            )
        }
    }

    /// Whether one folder name sorts before another, ORDINALLY and
    /// case-insensitively — the same answer C#'s `OrdinalIgnoreCase` gives, so
    /// that the two apps offer a teacher the same list in the same order.
    ///
    /// Written out rather than handed to Foundation, because every shorter way
    /// of asking is measurably a different question, and each of them looks
    /// right:
    ///
    /// - `localizedStandardCompare` is Finder order. It puts `Unit 2` before
    ///   `Unit 10`; Windows puts `Unit 10` first. Pinned by a contract case.
    /// - `compare(_:options: [.caseInsensitive])` folds to LOWER case, and C#
    ///   folds to UPPER. The six ASCII characters between `Z` and `a` —
    ///   `[ \ ] ^ _ ` — therefore sort BEFORE the letters here and AFTER them
    ///   on Windows: measured on this Mac, `_Archive` came first where Windows
    ///   puts it last. `_Archive` and `~Old` are ordinary names for a folder a
    ///   teacher wants at one end of a list, so this is not a corner case.
    /// - Comparing `String`s with `<` uses canonical equivalence rather than
    ///   code units, which is a third order again.
    ///
    /// So: precompose (APFS hands back DECOMPOSED names — `École` arrives as
    /// `E` + a combining accent, which sorts before `Fun` rather than after
    /// `zeta` — while a name typed on Windows is precomposed), upper-case, and
    /// compare UTF-16 code units. **Best effort rather than a guarantee**: a
    /// course carried from this Mac to Windows may take decomposed bytes with
    /// it, and Swift's full-Unicode `uppercased()` is not character-by-character
    /// the way `ToUpperInvariant` is. Both differences need an accented or
    /// exotic folder name to show at all, where the `_Archive` one needed only
    /// an underscore.
    nonisolated static func sortsBefore(_ left: String, _ right: String) -> Bool {
        let leftUnits: [UInt16] = Array(
            left.precomposedStringWithCanonicalMapping.uppercased().utf16
        )
        let rightUnits: [UInt16] = Array(
            right.precomposedStringWithCanonicalMapping.uppercased().utf16
        )
        var index: Int = 0
        while index < leftUnits.count && index < rightUnits.count {
            if leftUnits[index] != rightUnits[index] {
                return leftUnits[index] < rightUnits[index]
            }
            index += 1
        }
        return leftUnits.count < rightUnits.count
    }

    nonisolated private static func isExcluded(
        _ name: String, inScope scope: FolderScope,
        excludedShared: [String], excludedPerSection: [String]
    ) -> Bool {
        let names: [String]
        switch scope {
        case .shared:
            names = excludedShared
        case .perSection:
            names = excludedPerSection
        }
        for excluded in names {
            if excluded == name {
                return true
            }
        }
        return false
    }
}
