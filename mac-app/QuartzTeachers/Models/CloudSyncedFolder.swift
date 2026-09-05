import Foundation

/// A working folder that a cloud service keeps in sync — iCloud Drive,
/// Dropbox, OneDrive, Google Drive and the like.
///
/// Teachers keep their notes in such folders ON PURPOSE: it is how the notes
/// reach an iPad and a second Mac. So Plantoir never refuses one. What it does
/// is SAY so, once, in plain words — because three things go wrong in a synced
/// folder that a teacher would otherwise meet as unexplained slowness:
///
/// 1. A build writes thousands of small files, and the sync app copies every
///    one of them to the cloud.
/// 2. A page the service has offloaded to save space has to be downloaded
///    before it can be read, and renaming a folder reads every page.
/// 3. A move or rename can fail while the service is busy copying that file.
///
/// The decision, made 2026-09-05 (see `TODO.md` for both sides of it): detect,
/// explain, let the teacher choose, and leave their content where they put it.
/// Refusing was rejected because a hard block is the one answer a teacher
/// cannot opt out of, and detection is not certain enough to block on.
nonisolated struct CloudSyncedFolder: Equatable, Sendable {

    // MARK: - Stored properties

    /// The service, in the words a teacher uses for it: "iCloud Drive",
    /// "Dropbox", "OneDrive", "Google Drive", "Box" — or, when the folder is
    /// recognisably synced but the service is not one Plantoir knows by name,
    /// "your cloud service".
    let serviceName: String

    /// The folder itself.
    let folderPath: String
}

/// Recognises a synced folder from markers the system exposes, never from a
/// guess at a name — a teacher can have a folder literally called "Dropbox"
/// that is not one, and a wrong answer here is shown to them as fact.
///
/// The pure rule (`serviceName(forPath:homePath:)`) is what the contract
/// pins; `syncedFolder(at:)` adds the one check that needs the live file
/// system — iCloud's own flag on the item — which catches a Desktop or
/// Documents folder that iCloud syncs in place.
nonisolated enum CloudSyncDetector {

    // MARK: - Stored properties

    /// The name used when the folder is synced by a service not listed below.
    static let unknownServiceName: String = "your cloud service"

    /// Where macOS keeps every File Provider-based service's folders since
    /// macOS 12.3: `~/Library/CloudStorage/<Service>-<Account>/`. Dropbox,
    /// OneDrive, Google Drive and Box all live here now, which is what makes
    /// this detectable at all.
    static let cloudStorageFolderName: String = "Library/CloudStorage"

    /// iCloud Drive's real location; `~/iCloud Drive` in Finder is a view of it.
    static let iCloudFolderName: String = "Library/Mobile Documents"

    /// How a `~/Library/CloudStorage/` entry's prefix maps to the name a
    /// teacher knows. The prefix is the part before the first hyphen:
    /// `OneDrive-Personal`, `GoogleDrive-name@gmail.com`, `Dropbox`,
    /// `Box-Box`.
    static let serviceNamesByFolderPrefix: [String: String] = [
        "OneDrive": "OneDrive",
        "GoogleDrive": "Google Drive",
        "Dropbox": "Dropbox",
        "Box": "Box",
    ]

    // MARK: - Functions

    /// The service syncing this folder, or nil when no marker says one does.
    ///
    /// Symlinks are resolved FIRST. Dropbox and OneDrive both leave a link
    /// at the old place (`~/Dropbox` → `~/Library/CloudStorage/Dropbox`), and
    /// a path arriving through it matches no rule while the folder behind it
    /// matches Dropbox's. Resolving also makes one folder one key for the
    /// acknowledgement, whichever spelling it arrived by.
    static func syncedFolder(at folderURL: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> CloudSyncedFolder? {
        let resolvedURL: URL = folderURL.standardizedFileURL.resolvingSymlinksInPath()
        let folderPath: String = resolvedURL.path
        let homePath: String = homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        if let serviceName = CloudSyncDetector.serviceName(forPath: folderPath, homePath: homePath) {
            return CloudSyncedFolder(serviceName: serviceName, folderPath: folderPath)
        }
        if CloudSyncDetector.iCloudFlagIsTrusted(forPath: folderPath, homePath: homePath) && CloudSyncDetector.isInICloud(resolvedURL) {
            return CloudSyncedFolder(serviceName: "iCloud Drive", folderPath: folderPath)
        }
        return nil
    }

    /// Where the item's own iCloud flag is believed: under `~/Desktop` and
    /// `~/Documents`, the two folders "Desktop & Documents Folders" syncs in
    /// place without moving them. Nowhere else — the flag is set for ANY
    /// File Provider item, a Dropbox or OneDrive folder included (checked on
    /// a real `~/Library/CloudStorage/Dropbox`), so trusting it everywhere
    /// would call a Dropbox folder "iCloud Drive" to the teacher's face.
    static func iCloudFlagIsTrusted(forPath path: String, homePath: String) -> Bool {
        let home: String = CloudSyncDetector.withoutTrailingSlash(homePath)
        for folderName in ["Desktop", "Documents"] {
            let root: String = home + "/" + folderName
            if path == root || path.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    /// The pure rule: which service, from the path alone.
    ///
    /// Answers for the two locations macOS reserves for synced folders, and
    /// nothing else. A folder called "Dropbox" on the Desktop is NOT matched:
    /// the name proves nothing, and the File Provider location does.
    static func serviceName(forPath path: String, homePath: String) -> String? {
        let home: String = CloudSyncDetector.withoutTrailingSlash(homePath)
        let iCloudRoot: String = home + "/" + CloudSyncDetector.iCloudFolderName
        if path == iCloudRoot || path.hasPrefix(iCloudRoot + "/") {
            return "iCloud Drive"
        }

        let cloudStorageRoot: String = home + "/" + CloudSyncDetector.cloudStorageFolderName + "/"
        if !path.hasPrefix(cloudStorageRoot) {
            return nil
        }
        // `<Service>-<Account>/...` — the first component after the root.
        let remainder: String = String(path.dropFirst(cloudStorageRoot.count))
        var serviceFolderName: String = ""
        for character in remainder {
            if character == "/" {
                break
            }
            serviceFolderName.append(character)
        }
        if serviceFolderName.isEmpty {
            return nil
        }
        var prefix: String = ""
        for character in serviceFolderName {
            if character == "-" {
                break
            }
            prefix.append(character)
        }
        if let knownName = CloudSyncDetector.serviceNamesByFolderPrefix[prefix] {
            return knownName
        }
        return CloudSyncDetector.unknownServiceName
    }

    /// The item's own "ubiquitous" flag — the only way to see a Desktop or
    /// Documents folder that "Desktop & Documents Folders" syncs in place,
    /// since those stay at `~/Desktop` and `~/Documents` and match no path
    /// rule. Only meaningful where `iCloudFlagIsTrusted` says so.
    static func isInICloud(_ folderURL: URL) -> Bool {
        guard let values = try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey]) else {
            return false
        }
        return values.isUbiquitousItem ?? false
    }

    static func withoutTrailingSlash(_ path: String) -> String {
        if path.hasSuffix("/") && path.count > 1 {
            return String(path.dropLast())
        }
        return path
    }
}

/// What a teacher is told about a synced working folder — written once, here,
/// and pinned by `contracts/shared-rules.json` → `cloudSyncedFolders.wording`
/// so Windows says the same things.
///
/// The words are chosen to name EFFECTS a teacher can recognise ("building can
/// be slower", "renaming a folder can take a while") and never machinery. No
/// "sync client", no "file provider", no "dataless file".
nonisolated enum CloudSyncWording {

    // MARK: - Functions

    /// The headline, said first in both the picker and the notice.
    static func headline(service: String) -> String {
        return "This folder is kept in sync with \(service)."
    }

    /// The one-line version for the notice a window shows.
    static let summary: String =
        "Plantoir works here, but building can be slower and renaming folders can take a while. Your notes stay where they are."

    /// The reassurance, said before anything alarming.
    static let notesStayPut: String =
        "Your course notes stay exactly where they are. Plantoir never moves them."

    /// The build churn — the worst of the three on the mac, where the built
    /// site is written inside the working folder.
    static func buildFilesAreCopied(service: String) -> String {
        return "Building or previewing a website creates thousands of small files inside this folder, and \(service) will copy every one of them to the cloud. That can make building slower and take up storage space."
    }

    /// Offloaded pages: slow, not harmful.
    static func offloadedPagesAreSlow(service: String) -> String {
        return "If \(service) has moved some of your pages off this computer to save space, Plantoir has to download each one before it can read it. Renaming a folder reads every page, so it can take a while."
    }

    /// A move or rename can fail mid-sync; nothing is lost, and it can be
    /// tried again.
    static func syncingCanInterruptAMove(service: String) -> String {
        return "If \(service) is busy copying a file at the moment Plantoir needs to move or rename it, that step can fail. Plantoir checks before it moves anything, and you can try again once syncing has settled."
    }

    /// The choice, stated without pushing either way: a folder that is not
    /// synced avoids all of it; a folder that reaches other devices may
    /// matter more.
    static let whatToDo: String =
        "To avoid all of this, keep your working folder somewhere that is not synced — a folder inside your home folder, for example. If reaching your notes from other devices matters more, carry on: Plantoir will work, just more slowly at times."

    /// The button that goes ahead in the picker.
    static let useAnywayButton: String = "Use This Folder Anyway"

    /// The button that dismisses the in-window notice.
    static let dismissNoticeButton: String = "Got It"

    /// The picker's other button — the same words it has always used, named
    /// here so the contract carries them beside the choice they complete.
    static let chooseDifferentFolderButton: String = "Choose a Different Folder…"

    /// The notice's button that opens the full explanation in place, and
    /// what it says once the explanation is open.
    static let showDetailsButton: String = "Show Details"
    static let hideDetailsButton: String = "Hide Details"

    /// The full explanation, in the order it is shown.
    static func explanation(service: String) -> [String] {
        return [
            CloudSyncWording.notesStayPut,
            CloudSyncWording.buildFilesAreCopied(service: service),
            CloudSyncWording.offloadedPagesAreSlow(service: service),
            CloudSyncWording.syncingCanInterruptAMove(service: service),
            CloudSyncWording.whatToDo,
        ]
    }
}
