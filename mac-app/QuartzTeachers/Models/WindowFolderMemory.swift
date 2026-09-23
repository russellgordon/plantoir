import Foundation

/// Remembers each open window's folder and frame, for windows macOS
/// reopens without their value.
///
/// macOS owns window restoration: it reopens the windows (when the system
/// setting keeps them) with their frames, and usually their values. When a
/// value comes back empty, the window finds its folder here — matched by
/// frame, since the reopening order is macOS's own.
@MainActor
enum WindowFolderMemory {

    // MARK: - Types

    struct Entry {
        let path: String
        let frame: String

        /// The sidebar as the teacher left it: which courses' disclosure
        /// triangles were open, and whether the Archived and Backups
        /// groups were. Restored with the folder, so a reopened window
        /// shows the same courses unfolded that were being worked on.
        var expandedCourses: [String] = []
        var archivedExpanded: Bool = false
        var backupsExpanded: Bool = false

        /// The "Reference Courses" group and each school-year group inside
        /// it, remembered the same way and for the same reason: a teacher
        /// who folded last year's shelf away should not find it open again
        /// every time they reopen the window.
        ///
        /// A year is its starting calendar year; "Other" is 0, which is not
        /// a year and never will be — the offered range starts at 2022.
        var referenceExpanded: Bool = false
        var expandedReferenceYears: [Int] = []

        /// The selected course, section, or archived item, in
        /// `SidebarSelection`'s storage form; empty for none.
        var selection: String = ""
    }

    // MARK: - Stored properties

    /// Where the list is kept between launches.
    static let storageKey: String = "openWindowFolders"

    /// Entries not yet taken by a window this launch.
    private static var unclaimed: [Entry] = []

    private static var hasLoaded: Bool = false

    /// Claims are a launch-time affair: after this moment, a window with
    /// no value simply starts fresh. Without a deadline, a window opened
    /// mid-session could inherit an entry left over from launch.
    static var claimsOpenUntil: Date = Date().addingTimeInterval(10)

    /// Lets a test decide what the system setting says, since the real one
    /// belongs to the machine the tests happen to run on.
    static var systemRestoresWindowsOverride: Bool?

    // MARK: - Computed properties

    /// Whether the teacher's system-wide setting asks for windows back.
    ///
    /// System Settings ▸ Desktop & Dock ▸ "Close windows when quitting an
    /// application" reaches apps as `NSQuitAlwaysKeepsWindows` — true means
    /// quitting KEEPS windows, so the toggle being on reads as false. An
    /// absent key is false, matching the system default of the toggle
    /// being on.
    static var systemRestoresWindows: Bool {
        if let overridden = systemRestoresWindowsOverride {
            return overridden
        }
        return UserDefaults.standard.bool(forKey: "NSQuitAlwaysKeepsWindows")
    }

    // MARK: - Functions

    /// The remembered window whose frame matches this one, when there is
    /// one. macOS reopens windows in an order of its own choosing, so the
    /// frame — which it restores faithfully — is what pairs each window
    /// with ITS folder.
    static func claimEntry(matchingFrame frame: String, defaults: UserDefaults = UserDefaults.standard) -> Entry? {
        if Date() > claimsOpenUntil {
            return nil
        }
        loadIfNeeded(defaults: defaults)
        for (index, entry) in unclaimed.enumerated() {
            if entry.frame == frame && !entry.frame.isEmpty && WorkspaceModel.folderExists(atPath: entry.path) {
                unclaimed.remove(at: index)
                return entry
            }
        }
        return nil
    }

    /// Whether any remembered windows are still waiting to be claimed.
    static func hasEntriesToClaim(defaults: UserDefaults = UserDefaults.standard) -> Bool {
        loadIfNeeded(defaults: defaults)
        return !unclaimed.isEmpty
    }

    /// True while a launching window might yet receive a remembered
    /// folder: claims are still open and entries remain unclaimed. While
    /// this holds, a window with no folder should wait quietly rather
    /// than flash the folder picker it is about to replace.
    static func aClaimMayStillArrive(asOf now: Date = Date(),
                                     defaults: UserDefaults = UserDefaults.standard) -> Bool {
        if now > claimsOpenUntil {
            return false
        }
        return hasEntriesToClaim(defaults: defaults)
    }

    /// The next remembered window, skipping folders that no longer exist.
    static func claimNextEntry(defaults: UserDefaults = UserDefaults.standard) -> Entry? {
        if Date() > claimsOpenUntil {
            return nil
        }
        loadIfNeeded(defaults: defaults)
        while !unclaimed.isEmpty {
            let entry: Entry = unclaimed.removeFirst()
            if WorkspaceModel.folderExists(atPath: entry.path) {
                return entry
            }
        }
        return nil
    }

    /// Records the open windows as folder-and-frame pairs, in order.
    static func record(_ entries: [Entry], defaults: UserDefaults = UserDefaults.standard) {
        if WorkspaceModel.isRunningTests && defaults == UserDefaults.standard {
            return
        }
        var stored: [[String: String]] = []
        for entry in entries {
            // Course codes never contain commas, so a joined list stores
            // safely in the same string-to-string shape as the rest.
            stored.append([
                "path": entry.path,
                "frame": entry.frame,
                "expanded": entry.expandedCourses.joined(separator: ","),
                "archived": entry.archivedExpanded ? "1" : "0",
                "backups": entry.backupsExpanded ? "1" : "0",
                "reference": entry.referenceExpanded ? "1" : "0",
                "referenceYears": WindowFolderMemory.joined(entry.expandedReferenceYears),
                "selection": entry.selection,
            ])
        }
        defaults.set(stored, forKey: storageKey)
    }

    /// The years as one string, in the same comma-joined shape the course
    /// codes already use — an absent key reads as none, so an entry written
    /// by an older build simply has no reference groups open.
    static func joined(_ years: [Int]) -> String {
        var spelled: [String] = []
        for year in years.sorted() {
            spelled.append(String(year))
        }
        return spelled.joined(separator: ",")
    }

    static func years(_ stored: String?) -> [Int] {
        guard let stored, !stored.isEmpty else {
            return []
        }
        var result: [Int] = []
        for piece in stored.components(separatedBy: ",") {
            if let year = Int(piece) {
                result.append(year)
            }
        }
        return result
    }

    private static func loadIfNeeded(defaults: UserDefaults) {
        if hasLoaded {
            return
        }
        hasLoaded = true
        // The hosted test suite must never replay the teacher's own
        // windows: the app's real window would adopt a remembered folder
        // mid-test and stomp whatever fixture the test had chosen.
        if WorkspaceModel.isRunningTests && defaults == UserDefaults.standard {
            unclaimed = []
            return
        }
        // The teacher asked for windows NOT to come back: the list is
        // still recorded (so toggling the setting later restores the most
        // recent session), but nothing is replayed from it.
        if !WindowFolderMemory.systemRestoresWindows {
            unclaimed = []
            return
        }
        var loaded: [Entry] = []
        if let stored = defaults.array(forKey: storageKey) {
            for element in stored {
                if let pair = element as? [String: String], let path = pair["path"] {
                    var expandedCourses: [String] = []
                    if let joined = pair["expanded"], !joined.isEmpty {
                        expandedCourses = joined.components(separatedBy: ",")
                    }
                    loaded.append(Entry(
                        path: path,
                        frame: pair["frame"] ?? "",
                        expandedCourses: expandedCourses,
                        archivedExpanded: pair["archived"] == "1",
                        backupsExpanded: pair["backups"] == "1",
                        referenceExpanded: pair["reference"] == "1",
                        expandedReferenceYears: WindowFolderMemory.years(pair["referenceYears"]),
                        selection: pair["selection"] ?? ""
                    ))
                }
                // An entry from the earlier format: a bare path string.
                if let path = element as? String {
                    loaded.append(Entry(path: path, frame: ""))
                }
            }
        }
        unclaimed = loaded
    }

    /// Starts again from a given list — for tests.
    static func reset(with entries: [Entry]) {
        unclaimed = entries
        hasLoaded = true
        claimsOpenUntil = Date().addingTimeInterval(10)
    }

    /// Empties the memory and forces the next claim to read from the given
    /// store — for tests exercising the load path itself.
    static func resetForLoading() {
        unclaimed = []
        hasLoaded = false
        claimsOpenUntil = Date().addingTimeInterval(10)
    }
}
