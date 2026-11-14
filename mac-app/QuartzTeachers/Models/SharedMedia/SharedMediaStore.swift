import CryptoKit
import Darwin
import Foundation

/// The working folder's shared store of Media files, which lets a backup
/// Plantoir makes on its own keep each picture ONCE (#785).
///
/// **What it is for.** Every backup used to be a zip of the whole course,
/// Media included: 467 MB and 9.7 s for a real course with 487 MB of
/// pictures, and Plantoir saves one before every Section menu change, every
/// assistant conversation, and several other changes. Russell's ruling on
/// #785 (2026-11-13): every backup Plantoir makes on its own becomes small,
/// with each Media file kept once here; only a Back Up the teacher presses
/// stays a whole zip that can be carried anywhere.
///
/// **Where it is.** `courses/_backups/.shared-media/`, so it travels with
/// the working folder and is never part of a website:
///
/// ```
/// .shared-media/
///   .lock                       taken shared by a backup or a restore, and
///                               exclusively (never waiting) by a sweep
///   files/<aa>/<sha256>         the bytes, named by their checksum
///   lists/backup-<zip>.json     a copy of each small backup's list
///   lists/undo-<step>.json      a step on the Undo list that needs files
///   pending/<id>.json           a backup being written, kept a day after
///                               it finishes
///   sweep-<computer>.json       this computer's own sweep record
/// ```
///
/// The format is shared with Windows: `contracts/file-formats.json` →
/// `sharedMediaStore`. The rules are `contracts/course-management.json` →
/// `backups.sharedMedia`.
///
/// **What this piece (785a) is, and is not.** It is the store: writing a
/// small backup, putting a small backup's Media back, sweeping, and the
/// seam Undo (#899) keeps pictures through. Nothing in the app calls it yet,
/// so every backup is still a whole zip; 785b moves the automatic backups
/// onto it and teaches `BackupItem`, `CourseRestorer` and the sizes to read
/// what it writes.
nonisolated struct SharedMediaStore: Sendable {

    // MARK: - Types

    /// What went wrong, in words a teacher can be shown. Every one of them
    /// means nothing was published: no zip under its final name.
    enum Problem: LocalizedError, Equatable {
        case notASmallBackupName(String)
        case nameAlreadyTaken(String)
        case mediaUnreadable(String)
        case mediaChangedWhileBeingSaved(String)
        case storeCopyDidNotMatch(String)
        case mediaHasTooManyEntries(Int)
        case zipFailed(String)
        case notASmallBackup(String)
        case listUnreadable(String)
        case badUndoStepID(String)
        case mediaNotPutBack(String)

        var errorDescription: String? {
            switch self {
            case .notASmallBackupName(let name):
                return "\(name) is not the name of a backup that keeps its Media files once."
            case .nameAlreadyTaken(let name):
                return "A backup called \(name) is already there, so nothing was written over it."
            case .mediaUnreadable(let path):
                return "The backup could not read \(path) from the course's Media folder, so no backup was saved."
            case .mediaChangedWhileBeingSaved(let path):
                return "\(path) changed while the backup was being saved, so no backup was saved. Try again."
            case .storeCopyDidNotMatch(let path):
                return "The copy of \(path) did not match the original after it was saved, so no backup was saved."
            case .mediaHasTooManyEntries(let count):
                return "The course's Media folder holds more than \(count) files and folders, counting the ones its links lead to, so no small backup was saved."
            case .zipFailed(let reason):
                return "Could not write the backup: \(reason)"
            case .notASmallBackup(let name):
                return "\(name) does not say which Media files it keeps."
            case .listUnreadable(let name):
                return "The list of Media files in \(name) could not be read."
            case .badUndoStepID(let id):
                return "\(id) cannot name a step on the Undo list."
            case .mediaNotPutBack(let name):
                return "\(name) keeps its pictures with the other backups, and they were not put back, so nothing was changed."
            }
        }
    }

    /// Points a test can stop a backup at, to prove what a crash there
    /// leaves (`Hooks.tidiesUpAfterAFailure` false is a crash: nothing is
    /// tidied away).
    enum WritePoint: Equatable, Sendable {
        /// The pending list is written; nothing is in the store yet.
        case pendingWritten
        /// Every Media file the list names is in the store.
        case mediaStored
        /// The zip is whole under its temporary name, and the folder its
        /// list was added from is still there.
        case zipWritten
        /// The copy of the list is in `lists/`; the zip is not yet under its
        /// name.
        case listCopied
        /// The zip is under its final name; the pending list is not yet
        /// marked finished.
        case zipPublished
    }

    /// Where a test can step into a backup. `real` everywhere else.
    struct Hooks: Sendable {

        // MARK: - Stored properties

        /// Called at each `WritePoint`; a test throws to stop there.
        let reached: @Sendable (WritePoint) throws -> Void

        /// Called with a copy just made into the store, BEFORE it is checked
        /// and moved into place, so a test can damage it.
        let copiedIntoTheStore: @Sendable (URL) -> Void

        /// False makes a thrown hook behave like a crash: nothing written so
        /// far is removed.
        let tidiesUpAfterAFailure: Bool

        // MARK: - Computed properties

        static var real: Hooks {
            return Hooks(
                reached: { (_: WritePoint) throws in
                },
                copiedIntoTheStore: { (_: URL) in
                },
                tidiesUpAfterAFailure: true
            )
        }
    }

    /// What a whole zip of the course leaves out, so a small backup leaves
    /// out the same: the arguments after `zip -x`, and the names that,
    /// anywhere in a path, put a file out of the zip (`*/name`, `*/name/*`).
    /// `CourseArchiver.archiveRules(forFolderAt:)` builds both from the one
    /// list the whole zip uses.
    struct ArchiveRules: Sendable {

        // MARK: - Stored properties

        let zipExclusions: [String]
        let namesLeftOut: Set<String>
    }

    /// A small backup that was written.
    struct Written: Sendable {

        // MARK: - Stored properties

        let zipURL: URL
        let list: SharedMediaList
        let filesAlreadyKept: Int
        let filesAdded: Int
        let bytesAdded: Int64
    }

    /// What a sweep did.
    struct SweepResult: Equatable, Sendable {

        // MARK: - Stored properties

        let keptEverything: SharedMediaSweepRule.KeptEverything?
        let filesDeleted: Int
        let bytesFreed: Int64
        let listsRemoved: Int
        let filesFoundUnneededForTheFirstTime: Int
        var leftoversRemoved: Int = 0
    }

    /// One file found in Media.
    struct WalkedFile: Sendable {

        // MARK: - Stored properties

        /// From the course folder: `Media/…`, in the listing's own bytes.
        let path: String

        /// From the course's PARENT folder: `<course>/Media/…`.
        let sourcePath: String

        let size: Int64
        let modified: Date
        let mode: Int
    }

    /// Everything in a course's Media folder, and the open folder its
    /// `sourcePath`s are resolved from.
    struct WalkedMedia: Sendable {

        // MARK: - Stored properties

        let parent: SharedMediaFiles.Folder
        let files: [WalkedFile]
        let folders: [SharedMediaList.MediaFolder]
    }

    private enum SweepGatherProblem: Error {
        case couldNotRead(String)
    }

    struct ProgramResult: Sendable {

        // MARK: - Stored properties

        let status: Int32
        let output: Data
        let errors: String
    }

    // MARK: - Stored properties

    /// The working folder's `courses` folder.
    let coursesDirectoryURL: URL

    /// The time, replaceable so a test can make a day pass.
    let clock: @Sendable () -> Date

    /// Which computer this is (`thisComputer`), replaceable so a test can be
    /// two computers sharing one synced folder.
    let computer: String

    /// Whether a process that wrote a pending list is still running:
    /// `ProcessLiveness.ownerIsAlive` in the app.
    let processIsRunning: @Sendable (Int32, String?) -> Bool

    let hooks: Hooks

    /// What every small backup's name ends with, before `.zip`. It is also
    /// what keeps an OLDER Plantoir from listing one: every released parser
    /// (v1.0.0 to v1.9.x on the mac, `BackupItem.From` on Windows) refuses a
    /// name with a fourth `_` piece after `_backup_`, so a version that
    /// cannot restore a small backup's pictures never offers to restore it,
    /// delete it or prune it.
    static let smallBackupEnding: String = "_shared-media"

    static let storeFolderName: String = ".shared-media"

    /// The most files and folders a small backup's walk of Media takes,
    /// links followed. Two links that each lead back to their own parent
    /// would otherwise double the walk at every level until the system's
    /// limit of 32 links in a path; a whole zip of such a course never ends
    /// either.
    static let mostMediaEntries: Int = 200_000

    // MARK: - Computed properties

    var backupsURL: URL {
        return coursesDirectoryURL.appendingPathComponent("_backups")
    }

    var storeURL: URL {
        return backupsURL.appendingPathComponent(SharedMediaStore.storeFolderName)
    }

    var filesURL: URL {
        return storeURL.appendingPathComponent("files")
    }

    var listsURL: URL {
        return storeURL.appendingPathComponent("lists")
    }

    var pendingURL: URL {
        return storeURL.appendingPathComponent("pending")
    }

    var lockURL: URL {
        return storeURL.appendingPathComponent(".lock")
    }

    var sweepRecordURL: URL {
        return storeURL.appendingPathComponent("sweep-\(computer).json")
    }

    /// This Mac's hardware UUID (`gethostuuid`): the same for every account
    /// and every copy of Plantoir on it, and never the same on two Macs.
    /// Windows writes its `MachineGuid`.
    static var thisComputer: String {
        var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var wait: timespec = timespec(tv_sec: 1, tv_nsec: 0)
        if gethostuuid(&bytes, &wait) != 0 {
            return "unknown-mac"
        }
        return UUID(uuid: bytes).uuidString
    }

    // MARK: - Initializer

    init(
        coursesDirectoryURL: URL,
        clock: @escaping @Sendable () -> Date = { Date() },
        computer: String = SharedMediaStore.thisComputer,
        processIsRunning: @escaping @Sendable (Int32, String?) -> Bool = { (pid: Int32, start: String?) -> Bool in
            return ProcessLiveness.ownerIsAlive(pid: pid, recordedName: nil, recordedStart: start)
        },
        hooks: Hooks = Hooks.real
    ) {
        self.coursesDirectoryURL = coursesDirectoryURL
        self.clock = clock
        self.computer = computer
        self.processIsRunning = processIsRunning
        self.hooks = hooks
    }

    // MARK: - Functions: names

    /// True for a small backup's zip name.
    static func isSmallBackupName(_ name: String) -> Bool {
        return name.hasSuffix(smallBackupEnding + ".zip") && !name.hasPrefix(".")
    }

    /// The zip a sync service's placeholder stands for: iCloud Drive before
    /// macOS 14 kept an evicted `X.zip` as `.X.zip.icloud`. Nil for any
    /// other name. (Since macOS 14 an evicted file keeps its own name and
    /// has no data on this disk; reading its list either downloads it or
    /// fails, and a failure keeps everything.)
    static func smallBackupNameBehindPlaceholder(_ name: String) -> String? {
        let ending: String = ".icloud"
        if !name.hasPrefix(".") || !name.hasSuffix(ending) {
            return nil
        }
        let inner: String = String(name.dropFirst().dropLast(ending.count))
        if isSmallBackupName(inner) {
            return inner
        }
        return nil
    }

    /// Where a checksum's bytes are kept.
    func fileURL(forChecksum checksum: String) -> URL {
        return filesURL
            .appendingPathComponent(String(checksum.prefix(2)))
            .appendingPathComponent(checksum)
    }

    // MARK: - Functions: writing a small backup

    /// Saves a small backup of the course at `courseFolderURL` as
    /// `courses/_backups/<courseCode>/<zipName>`: the course as a whole zip
    /// would hold it, minus its top-level `Media` folder, plus the list of
    /// what that folder held; each Media file kept once in the store.
    ///
    /// **The order is the safety.** A crash at any point leaves files in the
    /// store that nothing names (swept later), never a zip whose files are
    /// missing:
    ///
    /// 1. The shared lock, so no sweep runs while this does.
    /// 2. Every Media file is read and its checksum taken, every time. A
    ///    shortcut that trusted an unchanged size and date was measured
    ///    (0.02 s against 0.25 s for 526 MB) and rejected: a picture edited
    ///    by a tool that keeps its date would be restored as the old one.
    /// 3. A pending list names every checksum, before anything is copied.
    /// 4. Each file not already kept is copied into the store under a
    ///    temporary name, checked against its checksum, and only then moved
    ///    to its name. A copy that does not match fails the backup. A kept
    ///    file is checked too, and a damaged one is replaced.
    /// 5. The pages are zipped under a temporary name, the list is added,
    ///    and the zip is tested.
    /// 6. A copy of the list goes in `lists/` (before the zip has its name,
    ///    so an old copy of the same name can never stand for this zip), then
    ///    the zip is moved to `zipName`, refusing a name that is already
    ///    there.
    /// 7. The pending list is marked finished and KEPT for a day: it is the
    ///    first thing a sync service carries to another computer, and it
    ///    names every picture this backup relies on (#785 implementation
    ///    review, W3).
    func writeSmallBackup(
        courseFolderURL: URL,
        courseCode: String,
        zipName: String,
        rules: ArchiveRules
    ) throws -> Written {
        if !SharedMediaStore.isSmallBackupName(zipName) {
            throw Problem.notASmallBackupName(zipName)
        }
        let fileManager: FileManager = FileManager.default
        let courseBackupsURL: URL = backupsURL.appendingPathComponent(courseCode)
        let finalZipURL: URL = courseBackupsURL.appendingPathComponent(zipName)
        if fileManager.fileExists(atPath: finalZipURL.path) {
            throw Problem.nameAlreadyTaken(zipName)
        }
        try createStoreFolders()
        try fileManager.createDirectory(at: courseBackupsURL, withIntermediateDirectories: true)

        // 1.
        let lock: SharedMediaLock = SharedMediaLock.shared(at: lockURL)
        defer {
            lock.release()
        }

        // 2.
        let walked: WalkedMedia? = try SharedMediaStore.walkMedia(
            inCourseAt: courseFolderURL, namesLeftOut: rules.namesLeftOut
        )
        var listedFiles: [SharedMediaList.MediaFile] = []
        var sourceForChecksum: [String: String] = [:]
        var folders: [SharedMediaList.MediaFolder] = []
        if let walked {
            folders = walked.folders
            for file in walked.files {
                guard let checksum = SharedMediaFiles.checksum(in: walked.parent, at: file.sourcePath) else {
                    throw Problem.mediaUnreadable(file.path)
                }
                listedFiles.append(SharedMediaList.MediaFile(
                    path: file.path, sha256: checksum, size: file.size, modified: file.modified, mode: file.mode
                ))
                if sourceForChecksum[checksum] == nil {
                    sourceForChecksum[checksum] = file.sourcePath
                }
            }
        }
        let list: SharedMediaList = SharedMediaList(
            course: courseCode,
            backupName: zipName,
            writtenAt: clock(),
            host: computer,
            media: listedFiles,
            folders: folders
        )

        // 3.
        let pendingID: String = UUID().uuidString
        let pendingFileURL: URL = pendingURL.appendingPathComponent("\(pendingID).json")
        var pending: SharedMediaHold = SharedMediaHold(
            kind: .pending,
            id: pendingID,
            writtenAt: list.writtenAt,
            host: computer,
            pid: getpid(),
            checksums: list.checksums
        )
        try SharedMediaStore.writeWhole(try pending.encoded(), to: pendingFileURL)
        let listCopyURL: URL = listsURL.appendingPathComponent("backup-\(zipName).json")
        var zipIsPublished: Bool = false
        var listIsCopied: Bool = false
        var temporaryZipURL: URL?
        do {
            try hooks.reached(.pendingWritten)

            // 4.
            var alreadyKept: Int = 0
            var added: Int = 0
            var bytesAdded: Int64 = 0
            var checksumsInOrder: [String] = []
            for checksum in sourceForChecksum.keys {
                checksumsInOrder.append(checksum)
            }
            checksumsInOrder.sort()
            for checksum in checksumsInOrder {
                guard let source = sourceForChecksum[checksum], let walked else {
                    continue
                }
                let wasAdded: Int64? = try keep(
                    source, from: walked.parent, as: checksum, pathForWords: pathOf(checksum, in: listedFiles)
                )
                if let bytes = wasAdded {
                    added += 1
                    bytesAdded += bytes
                } else {
                    alreadyKept += 1
                }
            }
            try hooks.reached(.mediaStored)

            // 5.
            let temporary: URL = courseBackupsURL.appendingPathComponent(".writing-\(UUID().uuidString).zip")
            temporaryZipURL = temporary
            let listData: Data = try list.encoded()
            try zipPages(
                ofCourseAt: courseFolderURL,
                to: temporary,
                rules: rules,
                leavingOutMedia: walked != nil,
                list: listData
            )

            // 6.
            try SharedMediaStore.writeWhole(listData, to: listCopyURL)
            listIsCopied = true
            try hooks.reached(.listCopied)
            try SharedMediaStore.moveRefusingAnExistingName(from: temporary, to: finalZipURL)
            zipIsPublished = true
            temporaryZipURL = nil
            try hooks.reached(.zipPublished)

            // 7.
            pending.finishedAt = clock()
            try? SharedMediaStore.writeWhole(try pending.encoded(), to: pendingFileURL)

            ActivityTrail.note(
                .backupKeptItsMediaOnce,
                ActivityTrail.backupKeptItsMediaOnceLine(
                    course: courseCode, backupFileName: zipName,
                    alreadyKept: alreadyKept, added: added, bytesAdded: bytesAdded
                )
            )
            return Written(
                zipURL: finalZipURL, list: list,
                filesAlreadyKept: alreadyKept, filesAdded: added, bytesAdded: bytesAdded
            )
        } catch {
            if hooks.tidiesUpAfterAFailure {
                if let temporaryZipURL {
                    try? fileManager.removeItem(at: temporaryZipURL)
                }
                if !zipIsPublished {
                    // The copy would stand for another zip of the same name
                    // that got there first.
                    if listIsCopied {
                        try? fileManager.removeItem(at: listCopyURL)
                    }
                    try? fileManager.removeItem(at: pendingFileURL)
                }
            }
            throw error
        }
    }

    /// The first Media path a checksum was read from, for the words of an
    /// error.
    private func pathOf(_ checksum: String, in files: [SharedMediaList.MediaFile]) -> String {
        for file in files {
            if file.sha256 == checksum {
                return file.path
            }
        }
        return checksum
    }

    /// Makes sure the store holds `checksum`, copying `sourcePath` in when it
    /// does not or when what it holds does not match. Returns the bytes added,
    /// or nil when a good copy was already kept.
    private func keep(
        _ sourcePath: String,
        from parent: SharedMediaFiles.Folder,
        as checksum: String,
        pathForWords: String
    ) throws -> Int64? {
        let fileManager: FileManager = FileManager.default
        let destination: URL = fileURL(forChecksum: checksum)
        if fileManager.fileExists(atPath: destination.path) {
            if SharedMediaStore.checksum(ofFileAt: destination) == checksum {
                return nil
            }
        }
        let groupURL: URL = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: groupURL, withIntermediateDirectories: true)
        guard let group = SharedMediaFiles.Folder(path: groupURL.path) else {
            throw Problem.zipFailed("the store's folder \(groupURL.lastPathComponent) could not be opened")
        }
        let temporaryName: String = ".incoming-\(UUID().uuidString)"
        let temporary: URL = groupURL.appendingPathComponent(temporaryName)
        do {
            if !SharedMediaFiles.copy(from: parent, at: sourcePath, to: group, at: temporaryName) {
                throw Problem.mediaUnreadable(pathForWords)
            }
            hooks.copiedIntoTheStore(temporary)
            let copied: String? = SharedMediaFiles.checksum(in: group, at: temporaryName)
            if copied != checksum {
                // Either the copy is damaged or the picture changed after it
                // was read. Read the original again to say which.
                if SharedMediaFiles.checksum(in: parent, at: sourcePath) != checksum {
                    throw Problem.mediaChangedWhileBeingSaved(pathForWords)
                }
                throw Problem.storeCopyDidNotMatch(pathForWords)
            }
            SharedMediaFiles.flush(in: group, at: temporaryName)
            if !SharedMediaFiles.rename(in: group, from: temporaryName, to: checksum) {
                throw Problem.zipFailed(String(cString: strerror(errno)))
            }
        } catch {
            if hooks.tidiesUpAfterAFailure {
                SharedMediaFiles.remove(in: group, at: temporaryName)
            }
            throw error
        }
        let attributes: [FileAttributeKey: Any]? = try? fileManager.attributesOfItem(atPath: destination.path)
        let size: Int64 = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return size
    }

    /// Zips the course without its top-level `Media` folder and adds the
    /// list at the zip's root, then tests the zip.
    private func zipPages(
        ofCourseAt courseFolderURL: URL,
        to temporaryZipURL: URL,
        rules: ArchiveRules,
        leavingOutMedia: Bool,
        list: Data
    ) throws {
        let folderName: String = courseFolderURL.lastPathComponent
        var arguments: [String] = ["-r", "-q", "-X", temporaryZipURL.path, folderName]
        var exclusions: [String] = rules.zipExclusions
        if leavingOutMedia {
            let media: String = SharedMediaStore.zipLiteral(folderName) + "/" + SharedMediaList.mediaFolderName
            exclusions.append(media + "/*")
            exclusions.append(media)
        }
        if !exclusions.isEmpty {
            arguments.append("-x")
            arguments.append(contentsOf: exclusions)
        }
        let pages: ProgramResult = SharedMediaStore.run(
            "/usr/bin/zip", arguments, in: courseFolderURL.deletingLastPathComponent()
        )
        if pages.status != 0 {
            throw Problem.zipFailed(pages.errors)
        }

        // The list goes in from a folder of its own, so the zip holds it at
        // its root under its one name.
        let fileManager: FileManager = FileManager.default
        let listFolder: URL = storeURL.appendingPathComponent(".incoming-\(UUID().uuidString)")
        try fileManager.createDirectory(at: listFolder, withIntermediateDirectories: true)
        do {
            try list.write(to: listFolder.appendingPathComponent(SharedMediaList.nameInsideTheZip))
            let adding: ProgramResult = SharedMediaStore.run(
                "/usr/bin/zip", ["-q", "-X", temporaryZipURL.path, SharedMediaList.nameInsideTheZip], in: listFolder
            )
            if adding.status != 0 {
                throw Problem.zipFailed(adding.errors)
            }
            // Tested before it is given its name: a backup that says it was
            // made and cannot be opened is the worst fault there is here.
            let test: ProgramResult = SharedMediaStore.run(
                "/usr/bin/unzip", ["-tqq", temporaryZipURL.path], in: listFolder
            )
            if test.status != 0 {
                throw Problem.zipFailed(test.errors)
            }
            let readBack: Data? = try? SharedMediaStore.listData(insideZipAt: temporaryZipURL)
            if readBack != list {
                throw Problem.zipFailed("the list inside the zip did not read back")
            }
            try hooks.reached(.zipWritten)
        } catch {
            if hooks.tidiesUpAfterAFailure {
                try? fileManager.removeItem(at: listFolder)
            }
            throw error
        }
        try? fileManager.removeItem(at: listFolder)
    }

    // MARK: - Functions: reading a small backup's list

    /// The list inside a small backup's zip.
    static func list(insideZipAt zipURL: URL) throws -> SharedMediaList {
        let data: Data = try listData(insideZipAt: zipURL)
        do {
            return try SharedMediaList.decoded(from: data)
        } catch {
            throw Problem.listUnreadable(zipURL.lastPathComponent)
        }
    }

    /// The list a backup unpacked into `stagingURL` carried at its root, or
    /// nil when it carried none: a whole zip.
    static func list(inUnpackedBackupAt stagingURL: URL) throws -> SharedMediaList? {
        let url: URL = stagingURL.appendingPathComponent(SharedMediaList.nameInsideTheZip)
        if !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            throw Problem.listUnreadable(SharedMediaList.nameInsideTheZip)
        }
        do {
            return try SharedMediaList.decoded(from: data)
        } catch {
            throw Problem.listUnreadable(SharedMediaList.nameInsideTheZip)
        }
    }

    /// **The guard every restore door must call** after unpacking a backup
    /// into `stagingURL` and before swapping anything into the course
    /// (#785 implementation review, I3). A small backup unpacks into its
    /// pages plus `.plantoir-backup.json` at the staging root; swapped in as
    /// it is, it would take the course's whole Media folder away and report
    /// success. The marker stays until `SharedMediaRestore.fill` has put the
    /// Media back, so a door that never called it is refused here, in
    /// words, with nothing changed. A whole zip carries no marker and
    /// passes.
    static func refuseUnlessItsMediaWasPutBack(unpackedAt stagingURL: URL, backupFileName: String) throws {
        let marker: URL = stagingURL.appendingPathComponent(SharedMediaList.nameInsideTheZip)
        var status: stat = stat()
        if lstat(marker.path, &status) == 0 {
            throw Problem.mediaNotPutBack(backupFileName)
        }
    }

    /// The list of a small backup, from its copy in `lists/` when that
    /// reads and names this zip, otherwise from inside the zip.
    func list(ofBackupNamed zipName: String, zipURL: URL?) throws -> SharedMediaList {
        let copyURL: URL = listsURL.appendingPathComponent("backup-\(zipName).json")
        if let data = try? Data(contentsOf: copyURL),
           let copy = try? SharedMediaList.decoded(from: data),
           copy.backupName == zipName {
            return copy
        }
        guard let zipURL else {
            throw Problem.listUnreadable(zipName)
        }
        return try SharedMediaStore.list(insideZipAt: zipURL)
    }

    static func listData(insideZipAt zipURL: URL) throws -> Data {
        let result: ProgramResult = run(
            "/usr/bin/unzip", ["-p", zipURL.path, SharedMediaList.nameInsideTheZip],
            in: zipURL.deletingLastPathComponent()
        )
        if result.status != 0 || result.output.isEmpty {
            throw Problem.listUnreadable(zipURL.lastPathComponent)
        }
        return result.output
    }

    // MARK: - Functions: putting a small backup's Media back

    /// Starts putting a small backup's Media back: takes the shared lock
    /// (so no sweep runs until `end()`), and finds each listed file, in the
    /// store first, then in the course's CURRENT Media folder, checking
    /// every one against its checksum. A file found in neither is MISSING,
    /// and the caller can ask the teacher before anything changes (#785 plan
    /// review, amendment 4): a restore that finishes and then says pictures
    /// are missing has already replaced the course's own copies.
    ///
    /// `currentCourseFolderURL` is the course as it is now, read BEFORE the
    /// restore swaps it out; nil when the course is not there.
    func beginRestore(of list: SharedMediaList, currentCourseFolderURL: URL?) -> SharedMediaRestore {
        let lock: SharedMediaLock = SharedMediaLock.shared(at: lockURL, creatingFolder: false)
        var sources: [String: SharedMediaRestore.Source] = [:]
        var missing: [String] = []
        var takenFromTheCourse: Set<String> = []
        var current: (folder: SharedMediaFiles.Folder, byChecksum: [String: String])? = nil
        var currentWasRead: Bool = false
        for file in list.media {
            if sources[file.sha256] != nil {
                continue
            }
            let kept: URL = fileURL(forChecksum: file.sha256)
            if SharedMediaStore.checksum(ofFileAt: kept) == file.sha256 {
                sources[file.sha256] = SharedMediaRestore.Source(folderPath: kept.deletingLastPathComponent().path, folder: nil, relativePath: file.sha256)
                continue
            }
            if !currentWasRead {
                currentWasRead = true
                current = SharedMediaStore.checksumsOfMedia(inCourseAt: currentCourseFolderURL)
            }
            if let current, let fromTheCourse = current.byChecksum[file.sha256] {
                sources[file.sha256] = SharedMediaRestore.Source(folderPath: nil, folder: current.folder, relativePath: fromTheCourse)
                takenFromTheCourse.insert(file.sha256)
            }
        }
        for file in list.media {
            if sources[file.sha256] == nil {
                missing.append(file.path)
            }
        }
        return SharedMediaRestore(
            list: list,
            sources: sources,
            takenFromTheCourse: takenFromTheCourse,
            missing: missing,
            lock: lock
        )
    }

    /// Every file of a course's Media folder by checksum, as a path from the
    /// course's parent folder, for a restore that cannot find one in the
    /// store.
    static func checksumsOfMedia(inCourseAt courseFolderURL: URL?) -> (folder: SharedMediaFiles.Folder, byChecksum: [String: String])? {
        guard let courseFolderURL,
              let walked = try? walkMedia(inCourseAt: courseFolderURL, namesLeftOut: []) else {
            return nil
        }
        var found: [String: String] = [:]
        for file in walked.files {
            if let checksum = SharedMediaFiles.checksum(in: walked.parent, at: file.sourcePath), found[checksum] == nil {
                found[checksum] = file.sourcePath
            }
        }
        return (walked.parent, found)
    }

    /// Whether the store holds every file of a list, each checked against
    /// its checksum: the paths it does not hold. For a check that must not
    /// trust a zip's listing alone, such as replacing a reference course
    /// only once its backup holds every file (#785 plan review, amendment 2).
    func pathsNotHeld(by list: SharedMediaList) -> [String] {
        var notHeld: [String] = []
        var checked: [String: Bool] = [:]
        for file in list.media {
            var held: Bool
            if let known = checked[file.sha256] {
                held = known
            } else {
                held = SharedMediaStore.checksum(ofFileAt: fileURL(forChecksum: file.sha256)) == file.sha256
                checked[file.sha256] = held
            }
            if !held {
                notHeld.append(file.path)
            }
        }
        return notHeld
    }

    // MARK: - Functions: Undo's seam (#899)

    /// Keeps the store files named by `checksums` for 31 days from
    /// `writtenAt`, for a step on the Undo list (#899 plan 4.5): call it
    /// BEFORE the step deletes or moves a small backup, with the checksums of
    /// that backup's list (`list(ofBackupNamed:zipURL:)`), and
    /// `releaseForUndo(stepID:)` when the step leaves the Undo list.
    ///
    /// Every computer sharing the working folder honours it, by the moment
    /// written here and never by the file's dates. Written whole or not at
    /// all, under the shared lock, so a sweep either sees all of it or runs
    /// before it.
    func keepForUndo(stepID: String, checksums: Set<String>, writtenAt: Date) throws {
        if !SharedMediaStore.isUsableStepID(stepID) {
            throw Problem.badUndoStepID(stepID)
        }
        try createStoreFolders()
        let lock: SharedMediaLock = SharedMediaLock.shared(at: lockURL)
        defer {
            lock.release()
        }
        let hold: SharedMediaHold = SharedMediaHold(
            kind: .undo, id: stepID, writtenAt: writtenAt, host: computer, pid: 0, checksums: checksums
        )
        try SharedMediaStore.writeWhole(try hold.encoded(), to: listsURL.appendingPathComponent("undo-\(stepID).json"))
    }

    /// The step has left the Undo list: its files are kept by nothing of its
    /// own any more (the next sweeps decide, a day apart).
    func releaseForUndo(stepID: String) {
        if !SharedMediaStore.isUsableStepID(stepID) {
            return
        }
        try? FileManager.default.removeItem(at: listsURL.appendingPathComponent("undo-\(stepID).json"))
    }

    /// Letters, digits, `-`, `_` and `.`, not starting with `.`: Undo's
    /// `<computer id>-<seq>`.
    static func isUsableStepID(_ id: String) -> Bool {
        if id.isEmpty || id.hasPrefix(".") || id.utf8.count > 200 {
            return false
        }
        for character in id.unicodeScalars {
            let isLetterOrDigit: Bool = (character >= "a" && character <= "z")
                || (character >= "A" && character <= "Z")
                || (character >= "0" && character <= "9")
            if !isLetterOrDigit && character != "-" && character != "_" && character != "." {
                return false
            }
        }
        return true
    }

    // MARK: - Functions: sweeping

    /// Deletes the store files nothing needs any more, by
    /// `SharedMediaSweepRule`. Never waits: when a backup or a restore holds
    /// the lock, it deletes nothing and says so. Run after a backup is
    /// deleted or pruned; running it more often only finds less to do.
    @discardableResult
    func sweep() -> SweepResult {
        let fileManager: FileManager = FileManager.default
        if !fileManager.fileExists(atPath: storeURL.path) {
            return SweepResult(
                keptEverything: nil, filesDeleted: 0, bytesFreed: 0, listsRemoved: 0,
                filesFoundUnneededForTheFirstTime: 0
            )
        }
        guard let lock = SharedMediaLock.exclusiveIfFree(at: lockURL) else {
            return kept(.theStoreIsBusy)
        }
        defer {
            lock.release()
        }

        let inputs: SharedMediaSweepRule.Inputs
        do {
            inputs = try gatherSweepInputs()
        } catch let SweepGatherProblem.couldNotRead(what) {
            return kept(.theStoreCouldNotBeRead(what))
        } catch {
            return kept(.theStoreCouldNotBeRead(error.localizedDescription))
        }
        let decision: SharedMediaSweepRule.Decision = SharedMediaSweepRule.decide(inputs)
        if let why = decision.keptEverything {
            return kept(why)
        }

        var deleted: Int = 0
        var bytesFreed: Int64 = 0
        for relativePath in decision.entriesToDelete {
            let url: URL = filesURL.appendingPathComponent(relativePath)
            let attributes: [FileAttributeKey: Any]? = try? fileManager.attributesOfItem(atPath: url.path)
            let size: Int64 = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            if unlink(url.path) == 0 {
                deleted += 1
                bytesFreed += size
            }
        }
        var firstTime: Int = 0
        for (relativePath, _) in decision.unneededSince where inputs.unneededSince[relativePath] == nil {
            firstTime += 1
        }
        if let data = try? SharedMediaStore.encodeSweepRecord(decision, computer: computer) {
            try? SharedMediaStore.writeWhole(data, to: sweepRecordURL)
        }
        var removed: Int = 0
        for fileName in decision.listFilesToRemove {
            // "lists/…" or "pending/…", inside the store.
            let url: URL = storeURL.appendingPathComponent(fileName)
            if (try? fileManager.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        var leftoversRemoved: Int = 0
        for path in decision.leftoversToRemove {
            if (try? fileManager.removeItem(at: coursesDirectoryURL.appendingPathComponent(path))) != nil {
                leftoversRemoved += 1
            }
        }
        var result: SweepResult = SweepResult(
            keptEverything: nil, filesDeleted: deleted, bytesFreed: bytesFreed, listsRemoved: removed,
            filesFoundUnneededForTheFirstTime: firstTime
        )
        result.leftoversRemoved = leftoversRemoved
        if deleted > 0 || removed > 0 || leftoversRemoved > 0 {
            ActivityTrail.note(.sharedMediaSwept, ActivityTrail.sharedMediaSweptLine(result))
        }
        return result
    }

    private func kept(_ why: SharedMediaSweepRule.KeptEverything) -> SweepResult {
        let result: SweepResult = SweepResult(
            keptEverything: why, filesDeleted: 0, bytesFreed: 0, listsRemoved: 0,
            filesFoundUnneededForTheFirstTime: 0
        )
        ActivityTrail.note(.sharedMediaSwept, ActivityTrail.sharedMediaSweptLine(result))
        return result
    }

    /// A crash's leftover in `folderURL`, by its path from `courses/`, when
    /// its name is one only this store writes for a moment.
    private func leftover(named name: String, in folderURL: URL, under prefix: String) -> SharedMediaSweepRule.Leftover? {
        if !name.hasPrefix(".writing-") && !name.hasPrefix(".incoming-") {
            return nil
        }
        let url: URL = folderURL.appendingPathComponent(name)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        return SharedMediaSweepRule.Leftover(path: prefix + "/" + name, modified: modified)
    }

    /// Everything the rule needs, read from disk under the exclusive lock.
    private func gatherSweepInputs() throws -> SharedMediaSweepRule.Inputs {
        let fileManager: FileManager = FileManager.default
        let now: Date = clock()
        let storePrefix: String = "_backups/" + SharedMediaStore.storeFolderName
        var leftovers: [SharedMediaSweepRule.Leftover] = []

        // files/<aa>/<entry>
        var entries: [SharedMediaSweepRule.StoreEntry] = []
        if fileManager.fileExists(atPath: filesURL.path) {
            guard let groups = try? fileManager.contentsOfDirectory(atPath: filesURL.path) else {
                throw SweepGatherProblem.couldNotRead("files")
            }
            for group in groups {
                let groupURL: URL = filesURL.appendingPathComponent(group)
                var isFolder: ObjCBool = false
                if !fileManager.fileExists(atPath: groupURL.path, isDirectory: &isFolder) || !isFolder.boolValue {
                    continue
                }
                guard let names = try? fileManager.contentsOfDirectory(atPath: groupURL.path) else {
                    throw SweepGatherProblem.couldNotRead("files/\(group)")
                }
                for name in names {
                    var checksum: String? = nil
                    if SharedMediaList.isChecksum(name) && name.hasPrefix(group) && group.utf8.count == 2 {
                        checksum = name
                    }
                    entries.append(SharedMediaSweepRule.StoreEntry(
                        relativePath: "\(group)/\(name)",
                        checksum: checksum,
                        isUnfinishedCopy: name.hasPrefix(".incoming-")
                    ))
                }
            }
        }

        // The store's own root: unfinished list folders, temporary records,
        // and other computers' sweep records.
        var anotherSweepRecord: Bool = false
        for name in (try? fileManager.contentsOfDirectory(atPath: storeURL.path)) ?? [] {
            if let found = leftover(named: name, in: storeURL, under: storePrefix) {
                leftovers.append(found)
            }
            if name.hasPrefix("sweep-") && name.hasSuffix(".json") && name != sweepRecordURL.lastPathComponent {
                anotherSweepRecord = true
            }
        }

        // Every small backup zip in _backups/<any folder>/, placeholders too.
        guard let courseFolders = try? fileManager.contentsOfDirectory(atPath: backupsURL.path) else {
            throw SweepGatherProblem.couldNotRead("_backups")
        }
        var backups: [SharedMediaSweepRule.BackupSeen] = []
        var zipsPresent: Set<String> = []
        for folder in courseFolders {
            if folder.hasPrefix(".") {
                continue
            }
            let folderURL: URL = backupsURL.appendingPathComponent(folder)
            var isFolder: ObjCBool = false
            if !fileManager.fileExists(atPath: folderURL.path, isDirectory: &isFolder) || !isFolder.boolValue {
                continue
            }
            guard let names = try? fileManager.contentsOfDirectory(atPath: folderURL.path) else {
                throw SweepGatherProblem.couldNotRead("_backups/\(folder)")
            }
            for name in names {
                if name.hasPrefix(".writing-") && name.hasSuffix(".zip"),
                   let found = leftover(named: name, in: folderURL, under: "_backups/\(folder)") {
                    leftovers.append(found)
                    continue
                }
                var zipName: String? = nil
                var zipURL: URL? = nil
                if SharedMediaStore.isSmallBackupName(name) {
                    zipName = name
                    zipURL = folderURL.appendingPathComponent(name)
                } else if let behind = SharedMediaStore.smallBackupNameBehindPlaceholder(name) {
                    zipName = behind
                }
                guard let zipName else {
                    continue
                }
                zipsPresent.insert(zipName)
                let list: SharedMediaList? = try? self.list(ofBackupNamed: zipName, zipURL: zipURL)
                var seen: SharedMediaSweepRule.BackupSeen = SharedMediaSweepRule.BackupSeen(
                    name: zipName, checksums: list?.checksums
                )
                seen.host = list?.host
                backups.append(seen)
            }
        }

        // lists/
        var withoutZips: [SharedMediaSweepRule.ListWithoutItsZip] = []
        var holds: [SharedMediaSweepRule.HoldSeen] = []
        var unreadable: [String] = []
        if fileManager.fileExists(atPath: listsURL.path) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: listsURL.path) else {
                throw SweepGatherProblem.couldNotRead("lists")
            }
            for name in names.sorted() {
                if let found = leftover(named: name, in: listsURL, under: storePrefix + "/lists") {
                    leftovers.append(found)
                    continue
                }
                if name.hasPrefix(".") || !name.hasSuffix(".json") {
                    continue
                }
                let url: URL = listsURL.appendingPathComponent(name)
                if name.hasPrefix("backup-") {
                    let zipName: String = String(name.dropFirst("backup-".count).dropLast(".json".count))
                    if zipsPresent.contains(zipName) {
                        continue
                    }
                    guard let data = try? Data(contentsOf: url),
                          let list = try? SharedMediaList.decoded(from: data) else {
                        unreadable.append("lists/\(name)")
                        continue
                    }
                    var without: SharedMediaSweepRule.ListWithoutItsZip = SharedMediaSweepRule.ListWithoutItsZip(
                        fileName: "lists/\(name)", writtenAt: list.writtenAt, checksums: list.checksums
                    )
                    without.host = list.host
                    withoutZips.append(without)
                } else if name.hasPrefix("undo-") {
                    guard let data = try? Data(contentsOf: url),
                          let hold = try? SharedMediaHold.decoded(from: data),
                          hold.kind == .undo else {
                        unreadable.append("lists/\(name)")
                        continue
                    }
                    holds.append(SharedMediaSweepRule.HoldSeen(
                        fileName: "lists/\(name)", hold: hold, writerIsRunningHere: false
                    ))
                } else {
                    // A list this version does not know: it may protect
                    // anything.
                    unreadable.append("lists/\(name)")
                }
            }
        }

        // pending/
        if fileManager.fileExists(atPath: pendingURL.path) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: pendingURL.path) else {
                throw SweepGatherProblem.couldNotRead("pending")
            }
            for name in names.sorted() {
                if let found = leftover(named: name, in: pendingURL, under: storePrefix + "/pending") {
                    leftovers.append(found)
                    continue
                }
                if name.hasPrefix(".") || !name.hasSuffix(".json") {
                    continue
                }
                let url: URL = pendingURL.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let hold = try? SharedMediaHold.decoded(from: data),
                      hold.kind == .pending else {
                    unreadable.append("pending/\(name)")
                    continue
                }
                var running: Bool = false
                if hold.host == computer {
                    running = processIsRunning(hold.pid, nil)
                }
                holds.append(SharedMediaSweepRule.HoldSeen(
                    fileName: "pending/\(name)", hold: hold, writerIsRunningHere: running
                ))
            }
        }

        let record: SweepRecord = readSweepRecord()
        var inputs: SharedMediaSweepRule.Inputs = SharedMediaSweepRule.Inputs(
            storeEntries: entries,
            backups: backups,
            listsWithoutTheirZips: withoutZips,
            holds: holds,
            unreadableListFiles: unreadable,
            unneededSince: record.unneededSince,
            now: now,
            thisComputer: computer
        )
        inputs.sharedWithAnotherComputer = record.shared
        inputs.anotherComputersSweepRecordIsThere = anotherSweepRecord
        inputs.listsFirstSeen = record.listsFirstSeen
        inputs.leftovers = leftovers
        return inputs
    }

    /// This computer's sweep record.
    private struct SweepRecord {

        // MARK: - Stored properties

        var unneededSince: [String: Date] = [:]
        var shared: Bool = false
        var listsFirstSeen: [String: Date] = [:]
    }

    /// This computer's record. A record that cannot be read is an empty
    /// one: every file starts its wait again, which only ever keeps files
    /// longer. (It would also forget that another computer has written here,
    /// until the next sweep finds that computer's lists or record again.)
    private func readSweepRecord() -> SweepRecord {
        var record: SweepRecord = SweepRecord()
        guard let data = try? Data(contentsOf: sweepRecordURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["format"] as? Int == SharedMediaList.formatNumber else {
            return record
        }
        if let since = object["unneededSince"] as? [String: String] {
            for (path, text) in since {
                if let moment = SharedMediaDates.date(from: text) {
                    record.unneededSince[path] = moment
                }
            }
        }
        if let seen = object["listsFirstSeen"] as? [String: String] {
            for (name, text) in seen {
                if let moment = SharedMediaDates.date(from: text) {
                    record.listsFirstSeen[name] = moment
                }
            }
        }
        record.shared = (object["sharedWithAnotherComputer"] as? Bool) ?? false
        return record
    }

    static func encodeSweepRecord(_ decision: SharedMediaSweepRule.Decision, computer: String) throws -> Data {
        var since: [String: String] = [:]
        for (path, moment) in decision.unneededSince {
            since[path] = SharedMediaDates.text(for: moment)
        }
        var seen: [String: String] = [:]
        for (name, moment) in decision.listsFirstSeen {
            seen[name] = SharedMediaDates.text(for: moment)
        }
        let object: [String: Any] = [
            "format": SharedMediaList.formatNumber,
            "computer": computer,
            "unneededSince": since,
            "sharedWithAnotherComputer": decision.sharedWithAnotherComputer,
            "listsFirstSeen": seen,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Functions: the disk

    private func createStoreFolders() throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: listsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
    }

    /// Everything in the course's top-level `Media` folder as a whole zip
    /// would hold it, walked as `zip -r` walks it (measured, each case
    /// compared byte for byte with the whole zip's restore):
    ///
    /// - hidden files are included; a name in `namesLeftOut` anywhere in the
    ///   path is left out;
    /// - a link to a file is the file's bytes under the link's name;
    /// - a link to a folder, inside the course or outside it, is that
    ///   folder's contents under the link's name, AND the folder itself is
    ///   walked again under its own name (until #785's review the walk
    ///   skipped any folder it had already been through, so a link that
    ///   sorted first made the real folder vanish from the restore);
    /// - a link that leads nowhere is left out, and so is a path through so
    ///   many links that the system refuses it (32 on macOS), which is where
    ///   `zip -r` stops a loop;
    /// - names are carried as the listing's own bytes.
    ///
    /// Nil when there is no folder listed as exactly `Media` (a folder
    /// listed as `media` is kept in the zip, as the whole zip's
    /// case-sensitive `zip -x` keeps it), and then a small backup leaves
    /// nothing out.
    static func walkMedia(inCourseAt courseFolderURL: URL, namesLeftOut: Set<String>) throws -> WalkedMedia? {
        let courseName: String = courseFolderURL.lastPathComponent
        guard let parent = SharedMediaFiles.Folder(path: courseFolderURL.deletingLastPathComponent().path),
              let topNames = SharedMediaFiles.names(in: parent, at: courseName) else {
            return nil
        }
        var listedExactly: Bool = false
        for name in topNames where Array(name.utf8) == Array(SharedMediaList.mediaFolderName.utf8) {
            listedExactly = true
        }
        let mediaSource: String = courseName + "/" + SharedMediaList.mediaFolderName
        guard listedExactly,
              let facts = SharedMediaFiles.facts(in: parent, at: mediaSource),
              facts.isFolder else {
            return nil
        }
        var files: [WalkedFile] = []
        var folders: [SharedMediaList.MediaFolder] = [
            SharedMediaList.MediaFolder(path: SharedMediaList.mediaFolderName, mode: facts.mode)
        ]
        try walk(
            parent: parent,
            sourcePath: mediaSource,
            relativePath: SharedMediaList.mediaFolderName,
            namesLeftOut: namesLeftOut,
            files: &files,
            folders: &folders
        )
        return WalkedMedia(parent: parent, files: files, folders: folders)
    }

    private static func walk(
        parent: SharedMediaFiles.Folder,
        sourcePath: String,
        relativePath: String,
        namesLeftOut: Set<String>,
        files: inout [WalkedFile],
        folders: inout [SharedMediaList.MediaFolder]
    ) throws {
        guard let names = SharedMediaFiles.names(in: parent, at: sourcePath) else {
            throw Problem.mediaUnreadable(relativePath)
        }
        for name in names {
            if namesLeftOut.contains(name) {
                continue
            }
            let childSource: String = sourcePath + "/" + name
            let childPath: String = relativePath + "/" + name
            guard let facts = SharedMediaFiles.facts(in: parent, at: childSource) else {
                // A link that leads nowhere, or one link too many: zip -r
                // leaves it out too.
                continue
            }
            if files.count + folders.count >= mostMediaEntries {
                throw Problem.mediaHasTooManyEntries(mostMediaEntries)
            }
            if facts.isFolder {
                folders.append(SharedMediaList.MediaFolder(path: childPath, mode: facts.mode))
                try walk(
                    parent: parent,
                    sourcePath: childSource,
                    relativePath: childPath,
                    namesLeftOut: namesLeftOut,
                    files: &files,
                    folders: &folders
                )
                continue
            }
            if !facts.isRegularFile {
                continue
            }
            files.append(WalkedFile(
                path: childPath,
                sourcePath: childSource,
                size: facts.size,
                modified: facts.modified,
                mode: facts.mode
            ))
        }
    }

    /// The SHA-256 of a file in the store, read a megabyte at a time; nil
    /// when it cannot be read. (The store's names are hexadecimal, so a URL
    /// is safe here; a course's own files go through `SharedMediaFiles`.)
    static func checksum(ofFileAt url: URL) -> String? {
        let opened: Int32 = open(url.path, O_RDONLY | O_CLOEXEC)
        if opened < 0 {
            return nil
        }
        defer {
            close(opened)
        }
        return SharedMediaFiles.checksum(ofOpenFile: opened)
    }

    static func flushToDisk(_ url: URL) {
        let descriptor: Int32 = open(url.path, O_RDONLY | O_CLOEXEC)
        if descriptor < 0 {
            return
        }
        fsync(descriptor)
        close(descriptor)
    }

    /// Writes data whole or not at all: to a temporary name beside the
    /// destination, flushed, then renamed over it.
    static func writeWhole(_ data: Data, to destination: URL) throws {
        let temporary: URL = destination.deletingLastPathComponent()
            .appendingPathComponent(".writing-\(UUID().uuidString)")
        try data.write(to: temporary)
        flushToDisk(temporary)
        if rename(temporary.path, destination.path) != 0 {
            let reason: String = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw Problem.zipFailed(reason)
        }
    }

    /// Moves a finished zip to its name, refusing one that is there
    /// (`RENAME_EXCL`); on a volume that cannot refuse (some network and
    /// FAT drives answer `ENOTSUP`), it looks first.
    static func moveRefusingAnExistingName(from source: URL, to destination: URL) throws {
        if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
            return
        }
        let failure: Int32 = errno
        if failure == EEXIST {
            throw Problem.nameAlreadyTaken(destination.lastPathComponent)
        }
        if failure == ENOTSUP || failure == EINVAL {
            if FileManager.default.fileExists(atPath: destination.path) {
                throw Problem.nameAlreadyTaken(destination.lastPathComponent)
            }
            if rename(source.path, destination.path) == 0 {
                return
            }
        }
        throw Problem.zipFailed(String(cString: strerror(errno)))
    }

    /// A name as `zip -x` reads it literally (`ObsidianFigureAddOns.zipLiteral`
    /// does the same): `[`, `]`, `*`, `?` and `\` are wildcards to zip.
    static func zipLiteral(_ name: String) -> String {
        var escaped: String = ""
        for character in name {
            if character == "[" || character == "]" || character == "*" || character == "?" || character == "\\" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// Runs a program to the end, its output and errors collected through
    /// files so a long list cannot fill a pipe and stop it.
    static func run(_ executable: String, _ arguments: [String], in folder: URL) -> ProgramResult {
        let fileManager: FileManager = FileManager.default
        let outputURL: URL = fileManager.temporaryDirectory.appendingPathComponent("shared-media-\(UUID().uuidString).out")
        let errorURL: URL = fileManager.temporaryDirectory.appendingPathComponent("shared-media-\(UUID().uuidString).err")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)
        defer {
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.removeItem(at: errorURL)
        }
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            return ProgramResult(status: -1, output: Data(), errors: "could not start \(executable)")
        }
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        do {
            try process.run()
        } catch {
            return ProgramResult(status: -1, output: Data(), errors: error.localizedDescription)
        }
        process.waitUntilExit()
        try? outputHandle.close()
        try? errorHandle.close()
        let output: Data = (try? Data(contentsOf: outputURL)) ?? Data()
        let errorData: Data = (try? Data(contentsOf: errorURL)) ?? Data()
        let errors: String = String(data: errorData, encoding: .utf8) ?? ""
        return ProgramResult(
            status: process.terminationStatus,
            output: output,
            errors: errors.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// A restore of a small backup's Media under way: it holds the store's
/// shared lock from `SharedMediaStore.beginRestore` until `end()`, so no
/// sweep can take a file between being found and being copied.
nonisolated final class SharedMediaRestore: @unchecked Sendable {

    // MARK: - Types

    /// Where one file's bytes come from: a store folder by path (its names
    /// are hexadecimal), or the course's current Media through its open
    /// parent folder.
    struct Source: @unchecked Sendable {

        // MARK: - Stored properties

        let folderPath: String?
        let folder: SharedMediaFiles.Folder?
        let relativePath: String
    }

    struct Filled: Equatable, Sendable {

        // MARK: - Stored properties

        let filesPutBack: Int
        let filesTakenFromTheCourse: Int

        /// Paths inside Media that could not be put back. Shown to the
        /// teacher; never written on the trail, which carries the count
        /// only (#785 plan review, amendment 5: a picture's name can carry a
        /// student's).
        let missing: [String]
    }

    // MARK: - Stored properties

    let list: SharedMediaList

    /// Paths inside Media that neither the store nor the course holds,
    /// found before anything was changed.
    let missing: [String]

    private let sources: [String: Source]
    private let takenFromTheCourse: Set<String>
    private var lock: SharedMediaLock?

    // MARK: - Computed properties

    /// False when the list names files and NONE of them can be found: the
    /// backup was carried away from the working folder its pictures are
    /// kept in, and restoring its pages over the course would take every
    /// picture away. The caller refuses, and changes nothing.
    var canBeRestored: Bool {
        if list.media.isEmpty {
            return true
        }
        return missing.count < list.media.count
    }

    // MARK: - Initializer

    init(
        list: SharedMediaList,
        sources: [String: Source],
        takenFromTheCourse: Set<String>,
        missing: [String],
        lock: SharedMediaLock
    ) {
        self.list = list
        self.sources = sources
        self.takenFromTheCourse = takenFromTheCourse
        self.missing = missing
        self.lock = lock
    }

    deinit {
        lock?.release()
    }

    // MARK: - Functions

    /// Puts the Media folder back inside an unpacked course (`payloadURL`,
    /// the course folder in staging, before it is swapped in): every
    /// folder, then every file, each copied under a temporary name, checked
    /// against its checksum and moved to its name, with its date and
    /// permissions put back, every name in the list's own bytes. A file
    /// whose copy does not match, or whose source has gone since
    /// `beginRestore`, is counted missing, never skipped silently. Then the
    /// marker beside the payload goes, which is what
    /// `refuseUnlessItsMediaWasPutBack` checks.
    func fill(intoCourseAt payloadURL: URL, backupFileName: String) throws -> Filled {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        guard let payload = SharedMediaFiles.Folder(path: payloadURL.path) else {
            throw SharedMediaStore.Problem.zipFailed("the restore's folder could not be opened")
        }
        var folders: [SharedMediaList.MediaFolder] = list.folders
        folders.sort { (first: SharedMediaList.MediaFolder, second: SharedMediaList.MediaFolder) -> Bool in
            return first.path.utf8.count < second.path.utf8.count
        }
        for folder in folders {
            if !SharedMediaFiles.makeFolders(in: payload, at: folder.path) {
                throw SharedMediaStore.Problem.zipFailed("could not make \(folder.path)")
            }
        }
        var putBack: Int = 0
        var fromTheCourse: Int = 0
        var missingNow: [String] = []
        for file in list.media {
            guard let source = sources[file.sha256] else {
                missingNow.append(file.path)
                continue
            }
            let parentPath: String = SharedMediaRestore.folderPart(of: file.path)
            if !SharedMediaFiles.makeFolders(in: payload, at: parentPath) {
                missingNow.append(file.path)
                continue
            }
            let temporary: String = parentPath + "/.incoming-\(UUID().uuidString)"
            var sourceFolder: SharedMediaFiles.Folder? = source.folder
            if sourceFolder == nil, let folderPath = source.folderPath {
                sourceFolder = SharedMediaFiles.Folder(path: folderPath)
            }
            guard let from = sourceFolder,
                  SharedMediaFiles.copy(from: from, at: source.relativePath, to: payload, at: temporary) else {
                missingNow.append(file.path)
                continue
            }
            if SharedMediaFiles.checksum(in: payload, at: temporary) != file.sha256 {
                SharedMediaFiles.remove(in: payload, at: temporary)
                missingNow.append(file.path)
                continue
            }
            SharedMediaFiles.remove(in: payload, at: file.path)
            if !SharedMediaFiles.rename(in: payload, from: temporary, to: file.path) {
                SharedMediaFiles.remove(in: payload, at: temporary)
                missingNow.append(file.path)
                continue
            }
            SharedMediaFiles.setMode(in: payload, at: file.path, file.mode)
            SharedMediaFiles.setModified(in: payload, at: file.path, file.modified)
            putBack += 1
            if takenFromTheCourse.contains(file.sha256) {
                fromTheCourse += 1
            }
        }
        // Folder permissions last, so a folder without write permission
        // could still be filled.
        for folder in folders.reversed() {
            SharedMediaFiles.setMode(in: payload, at: folder.path, folder.mode)
        }
        try? fileManager.removeItem(
            at: payloadURL.deletingLastPathComponent().appendingPathComponent(SharedMediaList.nameInsideTheZip)
        )
        if !missingNow.isEmpty {
            ActivityTrail.note(
                .backupMediaNotFound,
                ActivityTrail.backupMediaNotFoundLine(
                    course: list.course, backupFileName: backupFileName,
                    missing: missingNow.count, listed: list.media.count
                )
            )
        }
        return Filled(filesPutBack: putBack, filesTakenFromTheCourse: fromTheCourse, missing: missingNow)
    }

    /// Everything before a path's last `/`, its bytes untouched.
    static func folderPart(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else {
            return ""
        }
        return String(path[..<slash])
    }

    /// Lets go of the lock. Called when the restore is over, whatever
    /// happened; dropping the last reference does the same.
    func end() {
        lock?.release()
        lock = nil
    }
}

/// The store's lock: `flock` on `.shared-media/.lock`. Shared for a backup
/// or a restore, which may run side by side; exclusive and never waited for,
/// for a sweep. `flock` is held by the open file, not the path, so a working
/// folder reached by two spellings (a symbolic link, another case) is one
/// lock. It is local to this computer: between two computers sharing a
/// synced folder the guards are the lists' own moments and the sweep's wait.
nonisolated final class SharedMediaLock: @unchecked Sendable {

    // MARK: - Stored properties

    private var descriptor: Int32

    // MARK: - Initializer

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    // MARK: - Functions

    /// Waits for any sweep to finish, then holds the lock shared. On a volume
    /// where the lock cannot be taken at all, goes ahead without it: a sweep
    /// there cannot take its lock either, and so never runs.
    static func shared(at lockURL: URL, creatingFolder: Bool = true) -> SharedMediaLock {
        if creatingFolder {
            try? FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        let descriptor: Int32 = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        if descriptor < 0 {
            return SharedMediaLock(descriptor: -1)
        }
        var result: Int32 = flock(descriptor, LOCK_SH)
        while result != 0 && errno == EINTR {
            result = flock(descriptor, LOCK_SH)
        }
        return SharedMediaLock(descriptor: descriptor)
    }

    /// The lock held exclusively, or nil at once when anybody holds it or it
    /// cannot be taken.
    static func exclusiveIfFree(at lockURL: URL) -> SharedMediaLock? {
        let descriptor: Int32 = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        if descriptor < 0 {
            return nil
        }
        var result: Int32 = flock(descriptor, LOCK_EX | LOCK_NB)
        while result != 0 && errno == EINTR {
            result = flock(descriptor, LOCK_EX | LOCK_NB)
        }
        if result != 0 {
            close(descriptor)
            return nil
        }
        return SharedMediaLock(descriptor: descriptor)
    }

    func release() {
        if descriptor < 0 {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
