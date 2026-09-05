import Foundation

/// Which of a course's two folder lists a name belongs to. Shared folders sit
/// beside the course; per-section folders exist once inside EVERY section, so
/// renaming one is several moves rather than one.
enum FolderScope {

    case shared
    case perSection

    // MARK: - Computed properties

    /// The `course_config.json` key holding this scope's folder names.
    var configurationKey: String {
        switch self {
        case .shared:
            return "shared_folders"
        case .perSection:
            return "per_section_folders"
        }
    }

    /// The key this scope uses inside `excluded_items`.
    var exclusionKey: String {
        switch self {
        case .shared:
            return "shared"
        case .perSection:
            return "per_section"
        }
    }
}

/// What a rename actually did, so the teacher can be told rather than left to
/// guess.
struct FolderRenameOutcome {

    // MARK: - Stored properties

    /// How many folders moved on disk. One for a shared folder; one per
    /// section that HAD the folder, for a per-section one — which is not
    /// always every section, because a section a teacher never filled in may
    /// not have it.
    let foldersMoved: Int

    /// How many pages had a link pointing into the folder rewritten.
    let pagesRelinked: Int
}

/// Something that stopped a rename after it had started, or before it could.
struct FolderRenameProblem: LocalizedError {

    // MARK: - Stored properties

    let sentence: String

    // MARK: - Computed properties

    var errorDescription: String? { return sentence }
}

/// Renaming one of a course's folders from inside Plantoir — on disk, in every
/// section that has one, in the links that name it, and in every
/// `course_config.json` key that mentions it.
///
/// **Why this exists.** Until now the list editors changed the config and
/// nothing else: adding a name wrote an entry pointing at no folder, removing
/// one left a folder full of the teacher's work unreferenced, and renaming was
/// possible only in Obsidian — after which `preflight_update_course_config`
/// discovered the new name and APPENDED it, so the config ended up naming
/// both. Doing the rename here is the one place it can be WITNESSED, which is
/// what lets every key that names the folder be carried across in the same
/// breath instead of being discovered as a mismatch weeks later.
///
/// **It commits to disk immediately, and that is deliberate.** Course Settings
/// otherwise holds edits in memory until Save, with Cancel reverting them. A
/// folder that has really moved cannot be reverted by a Cancel, so pretending
/// otherwise would be a lie; the sheet says so before the teacher agrees. Only
/// the keys that name the folder are written, so their other unsaved edits
/// stay unsaved.
///
/// The sentences live in `contracts/shared-rules.json` → `specialNames.renameFolder`.
enum SpecialFolderRenamer {

    // MARK: - Stored properties

    /// Folders never walked when looking for pages to relink: build output,
    /// Obsidian's own settings, and the deploy markers. All are generated or
    /// private, and `.merged_output` in particular is a whole second copy of
    /// the course, so rewriting links in it would be both pointless and slow.
    static let foldersNeverWalked: Set<String> = [
        ".merged_output", "merged_output", ".obsidian", ".netlify_sites",
        ".toolchain", "node_modules", ".git",
    ]

    // MARK: - Functions

    /// Why this new name cannot be used, or nil when it can.
    ///
    /// Pure, so the rules can be tested without a course on disk. The
    /// filesystem's own objection — something already sitting where the folder
    /// would go — cannot be answered here and is raised by `rename` instead.
    static func problem(
        renaming oldName: String,
        to rawNewName: String,
        existingNames: [String]
    ) -> String? {
        let newName: String = rawNewName.trimmingCharacters(in: .whitespaces)
        if newName.isEmpty {
            return SpecialNames.renameFolderProblemEmpty
        }
        if newName == oldName {
            return SpecialNames.renameFolderProblemUnchanged
        }
        if newName.contains("/") || newName.contains(":") {
            return SpecialNames.renameFolderProblemHasSeparator
        }
        if newName.hasPrefix(".") {
            return SpecialNames.renameFolderProblemIsHidden
        }
        if newName.lowercased() == "media" {
            return SpecialNames.renameFolderProblemIsMedia
        }
        if looksLikeASectionFolder(newName) {
            return SpecialNames.renameFolderProblemLooksLikeASection(name: newName)
        }
        for existing in existingNames {
            if existing == oldName {
                continue
            }
            if existing.caseInsensitiveCompare(newName) == .orderedSame {
                return SpecialNames.renameFolderProblemAlreadyUsed(name: newName)
            }
        }
        // There is deliberately NO refusal about the class folder keeping the
        // word "class" in its name. There was one for a day: `ClassFolder`
        // used to FIND that folder by looking for the word, so dropping it
        // handed the curriculum map a different folder with nothing said.
        // Russell's point (2026-09-01) was that the constraint was
        // Plantoir's vocabulary imposed on a teacher's — somebody who says
        // "Thread 2, Day 3" would sensibly call the folder "All Days" — so
        // the guess was replaced by a recorded `class_folder`, which
        // `renaming(_:to:scope:in:)` below writes as part of the rename.
        // A rule enforced because a lookup was weak is a rule to delete once
        // the lookup is fixed.
        return nil
    }

    /// Whether this folder was the class folder for a reason, rather than by
    /// being first in the list.
    ///
    /// `ClassFolder.name` answers "where does a class page go?" and always
    /// answers SOMETHING — falling back to the first per-section folder, and
    /// then to a literal, so that a course always has an answer. That fallback
    /// is a guess of convenience, and it must not be frozen into the
    /// configuration by an unrelated rename: a course whose folders are
    /// `["Tasks", "Homework"]` would otherwise come out of renaming `Tasks`
    /// with `class_folder: "Assessments"` recorded for good, after which
    /// adding a real `All Classes` folder would never take over and the
    /// renamed folder could no longer be removed.
    ///
    /// So the key is written only when the answer was CONFIDENT: the course
    /// had already recorded this folder, or the folder names itself. Found by
    /// adversarial review, 2026-09-01.
    static func wasSurelyTheClassFolder(
        _ name: String, in folders: [String], recorded: String?
    ) -> Bool {
        if let alreadyRecorded = ClassFolder.matching(recorded, in: folders) {
            return alreadyRecorded.caseInsensitiveCompare(name) == .orderedSame
        }
        if !name.lowercased().contains("class") {
            return false
        }
        return ClassFolder.name(inPerSectionFolders: folders)
            .caseInsensitiveCompare(name) == .orderedSame
    }

    /// Whether a name is one Plantoir gives a section's own folder.
    static func looksLikeASectionFolder(_ name: String) -> Bool {
        let lowercased: String = name.lowercased()
        if !lowercased.hasPrefix("section") {
            return false
        }
        let tail: Substring = lowercased.dropFirst("section".count)
        if tail.isEmpty {
            return false
        }
        for character in tail {
            if !character.isNumber {
                return false
            }
        }
        return true
    }

    /// Every place on disk this folder lives, in the order they will be moved.
    static func folderLocations(
        named name: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int]
    ) -> [URL] {
        switch scope {
        case .shared:
            return [courseDirectory.appendingPathComponent(name)]
        case .perSection:
            var locations: [URL] = []
            for number in sectionNumbers {
                locations.append(
                    courseDirectory
                        .appendingPathComponent("section\(number)")
                        .appendingPathComponent(name)
                )
            }
            return locations
        }
    }

    /// Moves the folder, then points every qualified link at its new name.
    ///
    /// Nothing is moved until EVERY destination has been checked, so a
    /// per-section rename cannot get half way through four sections and stop:
    /// either all of them move or none of them do. A move that fails after
    /// that check is a filesystem fault, and it is reported with the sections
    /// that had already moved named in the message rather than silently.
    @discardableResult
    static func rename(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        courseDirectory: URL,
        sectionNumbers: [Int],
        fileManager: FileManager = .default
    ) throws -> FolderRenameOutcome {
        let locations: [URL] = folderLocations(
            named: oldName, scope: scope,
            courseDirectory: courseDirectory, sectionNumbers: sectionNumbers
        )

        var moves: [(from: URL, to: URL)] = []
        for location in locations {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: location.path, isDirectory: &isDirectory) {
                continue
            }
            if !isDirectory.boolValue {
                continue
            }
            let destination: URL = location
                .deletingLastPathComponent()
                .appendingPathComponent(newName)
            // A rename that only changes capitalisation asks the filesystem to
            // move a folder onto itself. On a case-insensitive volume — which
            // is the default on a Mac — the destination "exists" because it IS
            // the source, so the check below would refuse a rename that is
            // perfectly reasonable.
            let isOnlyACapitalisationChange: Bool =
                oldName.caseInsensitiveCompare(newName) == .orderedSame
            if !isOnlyACapitalisationChange && fileManager.fileExists(atPath: destination.path) {
                throw FolderRenameProblem(
                    sentence: SpecialNames.renameFolderProblemDestinationExists(name: newName)
                )
            }
            moves.append((from: location, to: destination))
        }

        var moved: Int = 0
        for move in moves {
            do {
                try fileManager.moveItem(at: move.from, to: move.to)
                moved += 1
            } catch {
                throw FolderRenameProblem(
                    sentence: "Plantoir renamed \(moved) of \(moves.count) copies of “\(oldName)” "
                            + "and then could not rename the one in "
                            + "\(move.from.deletingLastPathComponent().lastPathComponent): "
                            + error.localizedDescription
                )
            }
        }

        let relinked: Int = relinkPages(
            in: courseDirectory, folderNamed: oldName, to: newName, fileManager: fileManager
        )
        return FolderRenameOutcome(foldersMoved: moved, pagesRelinked: relinked)
    }

    /// Rewrites every qualified link in the course's pages, returning how many
    /// pages changed.
    static func relinkPages(
        in courseDirectory: URL,
        folderNamed oldName: String,
        to newName: String,
        fileManager: FileManager = .default
    ) -> Int {
        var changed: Int = 0
        for pageURL in markdownPages(in: courseDirectory, fileManager: fileManager) {
            guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            if FolderPathRewriter.countReferences(to: oldName, in: text) == 0 {
                continue
            }
            let rewritten: String = FolderPathRewriter.rewriting(text, folderNamed: oldName, to: newName)
            if rewritten == text {
                continue
            }
            do {
                try rewritten.write(to: pageURL, atomically: true, encoding: .utf8)
                changed += 1
            } catch {
                // One unwritable page must not abandon the rest: the folder has
                // already moved, so stopping here would leave MORE links broken
                // than carrying on does.
                continue
            }
        }
        return changed
    }

    /// Every Markdown page under a course, skipping generated and private trees.
    static func markdownPages(in courseDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let walker = fileManager.enumerator(
            at: courseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var pages: [URL] = []
        for case let url as URL in walker {
            if foldersNeverWalked.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            if url.pathExtension.lowercased() == "md" {
                pages.append(url)
            }
        }
        return pages
    }

    /// The configuration with every key that named the old folder naming the
    /// new one instead.
    ///
    /// Pure and whole-dictionary, so it can be applied to the file and to the
    /// in-memory copy from the same code — the two cannot disagree about what
    /// a rename means. The keys are listed in the contract under
    /// `specialNames.renameFolder.carriesAcross`; a key added there and not
    /// here is what a reviewer should look for.
    static func renaming(
        _ oldName: String,
        to newName: String,
        scope: FolderScope,
        in values: [String: Any]
    ) -> [String: Any] {
        var updated: [String: Any] = values

        // Which special folder, if either, this WAS — worked out before the
        // list is rewritten, because both answers are derived from it.
        let perSectionFolders: [String] = values["per_section_folders"] as? [String] ?? []
        let sharedFolders: [String] = values["shared_folders"] as? [String] ?? []
        let wasTheClassFolder: Bool = (scope == .perSection) && wasSurelyTheClassFolder(
            oldName, in: perSectionFolders, recorded: values["class_folder"] as? String
        )
        let wasTheCurriculumFolder: Bool = (scope == .shared) && CurriculumFolderRule
            .resolvedCurriculumFolder(
                configured: values["curriculum_folder"] as? String, in: sharedFolders
            )?.caseInsensitiveCompare(oldName) == .orderedSame

        updated[scope.configurationKey] = renaming(
            oldName, to: newName, inList: values[scope.configurationKey] as? [String] ?? []
        )

        // **Materialised on rename, not merely carried across.** A course made
        // from scratch has `curriculum_folder: null` and no `class_folder` at
        // all, so both are found by guessing at the name — "curriculum" in it,
        // or "class" in it. Rename `Curriculum` to `Expectations` without
        // writing the key and the guess stops finding it, the map is built
        // from nothing, and nobody is told; the coverage check does not fire,
        // because from its point of view the folder was never there. Writing
        // the name down at the one moment Plantoir WITNESSES the rename is the
        // whole reason renaming belongs in the app.
        if wasTheClassFolder {
            updated["class_folder"] = newName
        }
        if wasTheCurriculumFolder {
            updated["curriculum_folder"] = newName
        }

        // Three flat lists that name folders from EITHER scope, so each is
        // rewritten whichever list the folder came from.
        //
        // **`hidden` is the one that matters, and it was missed until the real
        // app was driven on 2026-09-04.** It holds the folders and files kept
        // OUT of the built site. Leave it naming the old folder and a rename
        // silently UN-HIDES it: the very next publish puts pages the teacher
        // deliberately hid in front of students. The course this was found on
        // had "Curriculum" in that list. Publishing what a teacher hid is a
        // failure this project has already had once, from a different cause,
        // and it is the worst thing in this file's reach.
        for key in ["graded_folders", "hidden", "expandable"] {
            if let names = values[key] as? [String] {
                updated[key] = renaming(oldName, to: newName, inList: names)
            }
        }

        // **Scoped, both of them.** A shared folder and a per-section folder may
        // legitimately share a name — they are different folders in different
        // places, found by different scans — so renaming the shared `Tasks`
        // must not rewrite a course whose CLASS folder is a per-section
        // `Tasks`. The curriculum folder is shared and the class folder is
        // per-section, so each is carried only by a rename in its own scope.
        // Found by the suite on 2026-09-04, next door to a test that was
        // failing for a different reason.
        if scope == .shared, let curriculum = values["curriculum_folder"] as? String {
            if curriculum.caseInsensitiveCompare(oldName) == .orderedSame {
                updated["curriculum_folder"] = newName
            }
        }

        if scope == .perSection, let classFolder = values["class_folder"] as? String {
            if classFolder.caseInsensitiveCompare(oldName) == .orderedSame {
                updated["class_folder"] = newName
            }
        }

        // A folder that is excluded is not in the list a teacher can rename
        // from, so this is defence rather than a path anybody walks today. It
        // is here because the alternative — an exclusion silently attaching
        // itself to whatever folder is next called by the old name — is the
        // failure `excluded_items` was written to prevent.
        if let excluded = values["excluded_items"] as? [String: Any] {
            var rewritten: [String: Any] = excluded
            // This scope's list only, for the same reason as the two keys
            // above: `excluded_items` is keyed by scope precisely BECAUSE the
            // same bare name can exist in both, and rewriting the other
            // scope's entry would silently re-include a folder the teacher
            // excluded.
            if let names = excluded[scope.exclusionKey] as? [String] {
                rewritten[scope.exclusionKey] = renaming(oldName, to: newName, inList: names)
            }
            updated["excluded_items"] = rewritten
        }

        return updated
    }

    // MARK: - Private helpers

    /// One list of names with the old one replaced, keeping its position.
    private static func renaming(_ oldName: String, to newName: String, inList names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            if name.caseInsensitiveCompare(oldName) == .orderedSame {
                result.append(newName)
            } else {
                result.append(name)
            }
        }
        return result
    }
}
