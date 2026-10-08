import Foundation
import Observation

/// File ▸ Open Recent: the working folders a teacher has OPENED, newest
/// first (#457, `contracts/shared-rules.json` → `openRecent`).
///
/// **Recorded on OPEN, never on focus.** `rememberAsTheLastWorkingFolder()`
/// runs every time a window comes to the front — every app switch — and the
/// plan first recorded recents there. The plan review measured what that
/// does with two windows on two folders: the list reorders on every switch,
/// and because this list is observed by the menu bar, every reorder is a
/// menu-bar rebuild. So a folder joins the list when it is chosen with Open
/// Working Folder…, chosen from Open Recent, or reopened by the app — and
/// opening the folder already at the top writes nothing at all.
///
/// **Not `NSDocumentController`'s recents.** Those list only what the app
/// claims as a document type, and claiming folders would put Plantoir in
/// Finder's Open With menu for every folder on the Mac.
///
/// A folder that has gone is not filtered out here: the menu is drawn from
/// this list, and asking the disk while the menu bar is drawn is the trap
/// Canopy recorded. Choosing one says why it could not be opened
/// (`OpenRecentWording`).
@Observable
final class RecentWorkingFolders {

    // MARK: - Stored properties

    /// The app's one list, read by File ▸ Open Recent.
    @MainActor static let shared: RecentWorkingFolders = RecentWorkingFolders(defaults: PlantoirDefaults.shared)

    /// Where the list is kept.
    static let storageKey: String = "recentWorkingFolders"

    /// How many folders the menu holds (`openRecent.cap`).
    static let cap: Int = 10

    /// The folders, newest first.
    private(set) var entries: [RememberedFolder] = []

    /// Injected so a test never writes the teacher's real preferences.
    @ObservationIgnored private let defaults: UserDefaults

    /// How many times the list has been written — so a test can see that
    /// opening the folder already at the top writes nothing.
    @ObservationIgnored private(set) var writeCount: Int = 0

    // MARK: - Initializer

    init(defaults: UserDefaults) {
        self.defaults = defaults
        entries = RecentWorkingFolders.load(from: defaults)
    }

    // MARK: - Functions

    /// A folder was opened: put it at the top, unless it is already there.
    func noteOpened(_ folder: RememberedFolder) {
        if WindowFolderMemory.mayNotTouch(defaults) {
            return
        }
        let result: (list: [RememberedFolder], changed: Bool) = RecentWorkingFolders.adding(folder, to: entries)
        if !result.changed {
            return
        }
        entries = result.list
        save()
    }

    #if DEBUG
    /// Tests only: the list as the menu reads it, without touching any store.
    /// The app's own list is never read or written under the hosted suite
    /// (`mayNotTouch`), so without this a test of the menu would only ever
    /// see an empty Open Recent.
    func replaceEntriesForTests(_ folders: [RememberedFolder]) {
        entries = folders
    }
    #endif

    /// File ▸ Open Recent ▸ Clear Menu.
    func clear() {
        if WindowFolderMemory.mayNotTouch(defaults) {
            return
        }
        if entries.isEmpty {
            return
        }
        let count: Int = entries.count
        entries = []
        save()
        ActivityTrail.note(
            .recentWorkingFoldersCleared,
            "cleared File ▸ Open Recent (" + String(count) + (count == 1 ? " folder)" : " folders)")
        )
    }

    private func save() {
        var stored: [[String: String]] = []
        for entry in entries {
            stored.append([
                "path": entry.path,
                "bookmark": entry.bookmark?.base64EncodedString() ?? "",
            ])
        }
        defaults.set(stored, forKey: RecentWorkingFolders.storageKey)
        writeCount += 1
    }

    /// The stored list, or — the first time, before anything has been
    /// recorded — the folders this Mac already knows about, so the menu is
    /// not empty on the first launch after the update.
    static func load(from defaults: UserDefaults) -> [RememberedFolder] {
        if WindowFolderMemory.mayNotTouch(defaults) {
            return []
        }
        if let stored = defaults.array(forKey: storageKey) {
            var loaded: [RememberedFolder] = []
            for element in stored {
                if let pair = element as? [String: String], let path = pair["path"], !path.isEmpty {
                    loaded.append(RememberedFolder(path: path, bookmark: WindowFolderMemory.bookmark(fromStored: pair["bookmark"])))
                }
            }
            return loaded
        }
        var seeded: [RememberedFolder] = []
        if let last = WindowFolderMemory.lastWorkingFolder(defaults: defaults) {
            seeded.append(last)
        }
        if let windows = defaults.array(forKey: WindowFolderMemory.storageKey) {
            for element in windows {
                if let pair = element as? [String: String], let path = pair["path"], !path.isEmpty {
                    let folder: RememberedFolder = RememberedFolder(
                        path: path, bookmark: WindowFolderMemory.bookmark(fromStored: pair["bookmark"])
                    )
                    var isListed: Bool = false
                    for existing in seeded where FolderIdentity.isSameFolder(existing.path, path) {
                        isListed = true
                    }
                    if !isListed && seeded.count < cap {
                        seeded.append(folder)
                    }
                }
            }
        }
        return seeded
    }

    /// `folder` brought to the top of `list`: the same folder however it is
    /// spelled is one entry, kept at the spelling just opened; at most `cap`.
    /// `changed` is false when it was already first, spelled the same way.
    static func adding(_ folder: RememberedFolder, to list: [RememberedFolder], cap: Int = RecentWorkingFolders.cap) -> (list: [RememberedFolder], changed: Bool) {
        if let first = list.first, first.path == folder.path {
            return (list, false)
        }
        var result: [RememberedFolder] = [folder]
        for entry in list {
            if FolderIdentity.isSameFolder(entry.path, folder.path) {
                continue
            }
            if result.count >= cap {
                break
            }
            result.append(entry)
        }
        return (result, true)
    }

    /// What each entry is called in the menu: its folder's name, and — when
    /// two entries share a name — the folder it is in as well, Xcode-style
    /// ("Courses — 2025"). When that still collides (`/A/2025/Courses` and
    /// `/B/2025/Courses`), more of the path is added until the titles differ
    /// ("Courses — A/2025", "Courses — B/2025"): two items with one title in
    /// a menu cannot be told apart (#457's implementation review).
    static func titles(for paths: [String]) -> [String] {
        var names: [String] = []
        var counts: [String: Int] = [:]
        for path in paths {
            let name: String = URL(fileURLWithPath: path).lastPathComponent
            names.append(name)
            counts[name, default: 0] += 1
        }
        var titles: [String] = []
        var index: Int = 0
        while index < paths.count {
            let name: String = names[index]
            if counts[name, default: 0] > 1 {
                var others: [String] = []
                var otherIndex: Int = 0
                while otherIndex < paths.count {
                    if otherIndex != index && names[otherIndex] == name {
                        others.append(paths[otherIndex])
                    }
                    otherIndex += 1
                }
                titles.append(name + " — " + distinguishingParent(of: paths[index], from: others))
            } else {
                titles.append(name)
            }
            index += 1
        }
        return titles
    }

    /// The fewest trailing folders of `path`'s parent that no path in
    /// `others` shares, joined with "/".
    static func distinguishingParent(of path: String, from others: [String]) -> String {
        let parents: [String] = URL(fileURLWithPath: path).deletingLastPathComponent().pathComponents
        var depth: Int = 1
        while depth <= parents.count {
            let suffix: String = trailing(depth, of: parents)
            var isShared: Bool = false
            for other in others {
                let otherParents: [String] = URL(fileURLWithPath: other).deletingLastPathComponent().pathComponents
                if trailing(depth, of: otherParents) == suffix {
                    isShared = true
                }
            }
            if !isShared {
                return suffix
            }
            depth += 1
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    /// The last `count` names of `components`, joined with "/" ("/" alone
    /// is dropped).
    static func trailing(_ count: Int, of components: [String]) -> String {
        var names: [String] = []
        var index: Int = max(0, components.count - count)
        while index < components.count {
            if components[index] != "/" {
                names.append(components[index])
            }
            index += 1
        }
        return names.joined(separator: "/")
    }
}

/// What a teacher is told when a folder chosen from File ▸ Open Recent cannot
/// be opened (`openRecent.wording`).
///
/// New sentences rather than `ReopenWording`'s, which say "the working folder
/// you had open LAST TIME … open Plantoir again" — wrong for a folder just
/// picked from a menu. The folder's name is in the title, so the sentence
/// does not repeat it. A folder out of the builder's reach has no sentence
/// here: it is refused with the picker's own words (`WorkingFolderReachWording`).
nonisolated enum OpenRecentWording {

    // MARK: - Functions

    static func title(folderName: String) -> String {
        return "“\(folderName)” could not be opened"
    }

    static let gone: String = "It can’t be found — if you moved it, choose it again with File ▸ Open Working Folder… from its new place."

    static let inTrash: String = "It is in the Trash — put it back and choose it again, or choose another folder."

    static let driveNotConnected: String = "It is on a drive that isn’t connected — connect the drive, then choose it again."

    static let unreadable: String = "You don’t have permission to read it — check who is allowed to open it, then choose it again."

    static let privacyDenied: String = "Plantoir isn’t allowed to open it — turn Plantoir on in System Settings ▸ Privacy & Security ▸ Files & Folders, then choose it again."

    /// The sentence for a reason, or nil for the two reasons the picker's
    /// own words cover.
    static func sentence(for reason: RememberedFolder.Reason) -> String? {
        switch reason {
        case .gone:
            return gone
        case .inTrash:
            return inTrash
        case .driveNotConnected:
            return driveNotConnected
        case .unreadable:
            return unreadable
        case .privacyDenied:
            return privacyDenied
        case .outsideHome, .coursesOutsideHome:
            return nil
        }
    }
}
