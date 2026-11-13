import Foundation

/// What a maker's set-up changed in the teacher's home folder, as Plantoir saw
/// it before and after, so that Remove takes away exactly what Plantoir's
/// set-up added and nothing the teacher already had (#855, plan review H4).
///
/// **Measured, not parsed.** Plantoir never reads a set-up's output (it names
/// the home folder, and its wording changes with every release). It looks at
/// the disk instead: before the set-up starts, which of the recipe's
/// `removes` paths (and the folders above them) exist, and the bytes of every
/// shell start-up file; afterwards, the same again. A path that appeared is
/// Plantoir's to take away; one that was already there is the teacher's. A
/// start-up file that grew by an appended block records that exact block; a
/// file whose earlier bytes changed is recorded as changed in place and is
/// never edited by Remove.
///
/// **Written BEFORE the set-up starts** (`state: installing`, with the
/// before-snapshot inside it), completed after the signature check (review
/// M3). A quit, a crash or a power cut part way therefore leaves a record
/// saying what to compare against, and the next launch finishes the job
/// (`AssistantSetUpCentre.settleInterruptedSetUps`) rather than calling the
/// program the teacher's own and never offering to remove it.
nonisolated struct SetUpRecordEntry: Codable, Equatable, Sendable {

    // MARK: - Types

    enum State: String, Codable, Sendable {
        case installing
        case installed
    }

    // MARK: - Stored properties

    var key: String
    /// What kind of thing was set up ("assistant"), so the handout programs
    /// planned after #855 can share one record.
    var kind: String
    var state: State
    var started: Date
    var finished: Date?
    /// Kept while `installing`, so an interrupted set-up can still be
    /// compared; dropped once the changes are worked out.
    var before: SetUpSnapshot?
    /// Paths from the recipe's `removes` that this set-up created.
    var created: [String]
    /// Folders above those that this set-up created: taken away only when
    /// they are empty, deepest first.
    var createdFolders: [String]
    /// Blocks this set-up appended to a shell start-up file.
    var profileChanges: [SetUpProfileChange]
    /// Start-up files this set-up changed other than by appending. Recorded
    /// so a report can say so; Remove leaves them as they are.
    var changedInPlace: [String]
}

/// Which of the watched paths existed, and the bytes of every start-up file,
/// at one moment.
nonisolated struct SetUpSnapshot: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    /// Paths relative to the home folder that existed (as a file, a folder
    /// or a link, a dangling link included).
    var existing: [String]
    var profiles: [SetUpProfileFile]
}

/// One start-up file's bytes, or nil when it did not exist.
nonisolated struct SetUpProfileFile: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var path: String
    var contents: Data?
}

/// A block a set-up appended to one start-up file.
nonisolated struct SetUpProfileChange: Codable, Equatable, Sendable {

    // MARK: - Stored properties

    var path: String
    /// Exactly what was added at the end, decoded as UTF-8.
    var appended: String
    /// True when the file did not exist before: Remove deletes it once
    /// taking the block away leaves nothing but white space.
    var fileWasCreated: Bool
}

/// What Remove managed to take away.
nonisolated struct SetUpRemoval: Equatable, Sendable {

    // MARK: - Stored properties

    var removedPaths: Int = 0
    var removedFolders: Int = 0
    var profileBlocksRemoved: Int = 0
    /// Blocks that were no longer in their file as written (the teacher
    /// edited it): left alone.
    var profileBlocksNotFound: Int = 0
    /// Paths that could not be taken away.
    var failures: Int = 0
    /// Recorded paths refused because the recipe does not list them, or
    /// they lead outside the home folder: a damaged or edited record never
    /// deletes anything else.
    var refused: Int = 0

    // MARK: - Computed properties

    var finishedCleanly: Bool {
        return failures == 0 && refused == 0
    }
}

/// Reads and writes the record, and works out and takes away a set-up's
/// changes. Every function takes the home folder, so a test hands it a
/// scratch one.
nonisolated enum SetUpRecord {

    // MARK: - Stored properties

    /// The shell start-up files a set-up may write: what Codex's
    /// `pick_profile` and Copilot's profile question choose from on a Mac
    /// (`.zprofile` for zsh, `.bash_profile` for bash, `.profile` for
    /// anything else, `.bash_login` and the rc files besides), read in both
    /// scripts on 2026-11-13.
    static let profileFiles: [String] = [
        ".zprofile",
        ".zshrc",
        ".bash_profile",
        ".bash_login",
        ".bashrc",
        ".profile"
    ]

    /// Where the record lives, under the home folder.
    static let relativeLocation: String = "Library/Application Support/Plantoir/set-up/record.json"

    // MARK: - Functions

    static func recordURL(home: URL) -> URL {
        return home.appendingPathComponent(relativeLocation)
    }

    /// Every entry, or none when there is no record or it cannot be read.
    static func load(home: URL) -> [SetUpRecordEntry] {
        guard let data = try? Data(contentsOf: recordURL(home: home)) else {
            return []
        }
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([SetUpRecordEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// The entry for `key`, or nil.
    static func entry(for key: String, home: URL) -> SetUpRecordEntry? {
        for entry in load(home: home) where entry.key == key {
            return entry
        }
        return nil
    }

    /// Writes `entries` in place of what was there.
    static func save(_ entries: [SetUpRecordEntry], home: URL) throws {
        let url: URL = recordURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder: JSONEncoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    /// Puts `entry` in place of any entry with its key.
    static func store(_ entry: SetUpRecordEntry, home: URL) throws {
        var entries: [SetUpRecordEntry] = []
        for existing in load(home: home) where existing.key != entry.key {
            entries.append(existing)
        }
        entries.append(entry)
        try save(entries, home: home)
    }

    /// Takes the entry for `key` out of the record.
    static func forget(_ key: String, home: URL) throws {
        var entries: [SetUpRecordEntry] = []
        for existing in load(home: home) where existing.key != key {
            entries.append(existing)
        }
        try save(entries, home: home)
    }

    /// Whether anything (a link that leads nowhere included) is at `path`.
    static func somethingIsThere(_ url: URL) -> Bool {
        var unused: stat = stat()
        return lstat(url.path, &unused) == 0
    }

    /// The recipe's `removes` paths and every folder above them inside the
    /// home folder, shallowest first, without repeats.
    static func watchedPaths(for recipe: SetUpRecipe) -> [String] {
        var paths: [String] = []
        for path in recipe.removes {
            var parts: [String] = path.components(separatedBy: "/")
            var ancestors: [String] = []
            while parts.count > 1 {
                parts.removeLast()
                ancestors.insert(parts.joined(separator: "/"), at: 0)
            }
            for ancestor in ancestors where !paths.contains(ancestor) {
                paths.append(ancestor)
            }
            if !paths.contains(path) {
                paths.append(path)
            }
        }
        return paths
    }

    /// What is there now.
    static func snapshot(of recipe: SetUpRecipe, home: URL) -> SetUpSnapshot {
        var existing: [String] = []
        for path in watchedPaths(for: recipe) {
            if somethingIsThere(home.appendingPathComponent(path)) {
                existing.append(path)
            }
        }
        var profiles: [SetUpProfileFile] = []
        for profile in profileFiles {
            let contents: Data? = try? Data(contentsOf: home.appendingPathComponent(profile))
            profiles.append(SetUpProfileFile(path: profile, contents: contents))
        }
        return SetUpSnapshot(existing: existing, profiles: profiles)
    }

    /// What changed between `before` and now, as a finished entry's fields:
    /// the recipe's paths that appeared, the folders above them that
    /// appeared, and what happened to each start-up file.
    static func changes(
        of recipe: SetUpRecipe,
        since before: SetUpSnapshot,
        home: URL
    ) -> (created: [String], createdFolders: [String], profileChanges: [SetUpProfileChange], changedInPlace: [String]) {
        let after: SetUpSnapshot = snapshot(of: recipe, home: home)
        var created: [String] = []
        var createdFolders: [String] = []
        for path in after.existing where !before.existing.contains(path) {
            if recipe.removes.contains(path) {
                created.append(path)
            } else {
                createdFolders.append(path)
            }
        }
        var profileChanges: [SetUpProfileChange] = []
        var changedInPlace: [String] = []
        for profileAfter in after.profiles {
            var contentsBefore: Data? = nil
            for profileBefore in before.profiles where profileBefore.path == profileAfter.path {
                contentsBefore = profileBefore.contents
            }
            if contentsBefore == profileAfter.contents {
                continue
            }
            guard let contentsAfter = profileAfter.contents else {
                // The set-up deleted a start-up file: not what any of the
                // three does, and never put back by Plantoir.
                changedInPlace.append(profileAfter.path)
                continue
            }
            let earlier: Data = contentsBefore ?? Data()
            let grewAtTheEnd: Bool = contentsAfter.count > earlier.count
                && contentsAfter.prefix(earlier.count) == earlier
            if grewAtTheEnd, let appended = String(data: contentsAfter.suffix(from: earlier.count), encoding: .utf8) {
                profileChanges.append(SetUpProfileChange(
                    path: profileAfter.path, appended: appended, fileWasCreated: contentsBefore == nil
                ))
            } else {
                changedInPlace.append(profileAfter.path)
            }
        }
        return (created, createdFolders, profileChanges, changedInPlace)
    }

    /// Whether `path` is one the recipe lets Plantoir take away (or a folder
    /// above one), and stays inside the home folder.
    static func mayTakeAway(_ path: String, recipe: SetUpRecipe, home: URL) -> Bool {
        if !watchedPaths(for: recipe).contains(path) {
            return false
        }
        if path.isEmpty || path.hasPrefix("/") || path.components(separatedBy: "/").contains("..") {
            return false
        }
        let homePath: String = home.standardizedFileURL.path
        let target: String = home.appendingPathComponent(path).standardizedFileURL.path
        return target.hasPrefix(homePath + "/")
    }

    /// Takes away what `entry` says this set-up added, and nothing else: the
    /// created paths (a link itself, never what it leads to), the appended
    /// start-up blocks (written back through a linked file, so a dotfile
    /// manager's link is kept), then the created folders that are empty.
    static func takeAway(_ entry: SetUpRecordEntry, recipe: SetUpRecipe, home: URL) -> SetUpRemoval {
        var removal: SetUpRemoval = SetUpRemoval()
        let fileManager: FileManager = FileManager.default
        for path in entry.created {
            if !mayTakeAway(path, recipe: recipe, home: home) || !recipe.removes.contains(path) {
                removal.refused += 1
                continue
            }
            let url: URL = home.appendingPathComponent(path)
            if !somethingIsThere(url) {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                removal.removedPaths += 1
            } catch {
                removal.failures += 1
            }
        }
        for change in entry.profileChanges {
            if !profileFiles.contains(change.path) {
                removal.refused += 1
                continue
            }
            switch takeAwayBlock(change, home: home) {
            case .removed:
                removal.profileBlocksRemoved += 1
            case .notFound:
                removal.profileBlocksNotFound += 1
            case .failed:
                removal.failures += 1
            }
        }
        var folders: [String] = entry.createdFolders
        folders.sort { (first: String, second: String) -> Bool in
            return first.count > second.count
        }
        for folder in folders {
            if !mayTakeAway(folder, recipe: recipe, home: home) {
                removal.refused += 1
                continue
            }
            let url: URL = home.appendingPathComponent(folder)
            let contents: [String]? = try? fileManager.contentsOfDirectory(atPath: url.path)
            if let contents, contents.isEmpty {
                do {
                    try fileManager.removeItem(at: url)
                    removal.removedFolders += 1
                } catch {
                    removal.failures += 1
                }
            }
        }
        return removal
    }

    /// What happened to one appended block.
    enum BlockOutcome {
        case removed
        case notFound
        case failed
    }

    /// Takes the LAST copy of `change.appended` out of its file, writing to
    /// the file a link leads to rather than replacing the link.
    static func takeAwayBlock(_ change: SetUpProfileChange, home: URL) -> BlockOutcome {
        let location: URL = home.appendingPathComponent(change.path)
        let target: URL = location.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target),
              let text = String(data: data, encoding: .utf8) else {
            return .notFound
        }
        guard let range = text.range(of: change.appended, options: .backwards) else {
            return .notFound
        }
        var remaining: String = text
        remaining.removeSubrange(range)
        do {
            if change.fileWasCreated && remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try FileManager.default.removeItem(at: location)
            } else {
                try Data(remaining.utf8).write(to: target)
            }
            return .removed
        } catch {
            return .failed
        }
    }
}
