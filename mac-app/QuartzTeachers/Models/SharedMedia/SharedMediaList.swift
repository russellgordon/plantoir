import Foundation

/// What a small backup records about the Media folder it left out (#785),
/// and the other lists the shared Media store reads when it decides what it
/// may delete.
///
/// A backup Plantoir makes on its own keeps the course's pages in an
/// ordinary zip and keeps each file of the course's `Media` folder ONCE, in
/// the working folder's shared store (`SharedMediaStore`). The list below is
/// what ties the two together: every file the Media folder held, by path,
/// checksum, size, date and permissions, and every folder, so a restore can
/// put the folder back exactly as a whole zip would have.
///
/// **The list inside the zip is the record.** A copy of it is kept in the
/// store's `lists/` folder so the sweep does not have to open every zip, but
/// a zip with no copy beside it is read directly, and a sweep that cannot
/// read one deletes nothing. A note beside a zip can fall out of step with
/// it; the zip itself cannot.
///
/// The format is shared with the Windows app: `contracts/file-formats.json`
/// → `sharedMediaStore`.
nonisolated struct SharedMediaList: Equatable, Sendable {

    // MARK: - Types

    /// One file of the Media folder.
    struct MediaFile: Equatable, Sendable {

        // MARK: - Stored properties

        /// Where it sat, from the course folder: always `Media/…`, with `/`
        /// between the parts on every platform.
        let path: String

        /// Its SHA-256, 64 lower-case hexadecimal digits: also its name in
        /// the store.
        let sha256: String

        /// Its length in bytes.
        let size: Int64

        /// When it was last changed, put back on the restored file.
        let modified: Date

        /// Its permission bits (`0o644` is 420), put back on the restored
        /// file. The Windows app writes 420 and ignores the value it reads.
        let mode: Int
    }

    /// One folder inside Media (Media itself included), so an empty folder
    /// comes back too: a whole zip keeps every folder, empty or not.
    struct MediaFolder: Equatable, Sendable {

        // MARK: - Stored properties

        let path: String
        let mode: Int
    }

    /// Why a list could not be read. Never a reason to guess: a sweep that
    /// meets one deletes nothing, and a restore that meets one refuses.
    enum Problem: Error, Equatable {
        case notJSON
        case wrongFormat(Int)
        case missingField(String)
        case unsafePath(String)
        case badChecksum(String)
    }

    // MARK: - Stored properties

    /// The course code the backup is of.
    let course: String

    /// The backup's zip file name, which is what `lists/` is keyed on.
    let backupName: String

    /// When the backup was written, by the clock of the computer that wrote
    /// it.
    let writtenAt: Date

    /// Which computer wrote it (`SharedMediaStore.thisComputer`).
    let host: String

    let media: [MediaFile]
    let folders: [MediaFolder]

    // MARK: - Computed properties

    /// The format number this version writes and is the only one it reads.
    static let formatNumber: Int = 1

    /// The list's name inside the zip, at the zip's root and beside the
    /// course folder rather than inside it, so a course unpacked from the
    /// zip carries no file the teacher did not make.
    static let nameInsideTheZip: String = ".plantoir-backup.json"

    /// Every checksum the list names, once each.
    var checksums: Set<String> {
        var result: Set<String> = []
        for file in media {
            result.insert(file.sha256)
        }
        return result
    }

    // MARK: - Functions

    /// The list as the JSON both apps write: keys sorted, dates in UTC with
    /// milliseconds.
    func encoded() throws -> Data {
        var mediaObjects: [[String: Any]] = []
        for file in media {
            mediaObjects.append([
                "path": file.path,
                "sha256": file.sha256,
                "size": file.size,
                "modified": SharedMediaDates.text(for: file.modified),
                "mode": file.mode,
            ])
        }
        var folderObjects: [[String: Any]] = []
        for folder in folders {
            folderObjects.append([
                "path": folder.path,
                "mode": folder.mode,
            ])
        }
        let object: [String: Any] = [
            "format": SharedMediaList.formatNumber,
            "kind": "backup",
            "course": course,
            "backup": backupName,
            "writtenAt": SharedMediaDates.text(for: writtenAt),
            "host": host,
            "media": mediaObjects,
            "folders": folderObjects,
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Reads a list, refusing anything that is not exactly what this
    /// version writes: another format number, a missing field, a checksum
    /// that is not one, or a path that could point outside the course's
    /// Media folder (`..`, an absolute path, an empty part). The last is
    /// what stops a damaged or hand-made list from writing a restore's
    /// files anywhere but `Media/`.
    static func decoded(from data: Data) throws -> SharedMediaList {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Problem.notJSON
        }
        guard let format = object["format"] as? Int else {
            throw Problem.missingField("format")
        }
        if format != formatNumber {
            throw Problem.wrongFormat(format)
        }
        if object["kind"] as? String != "backup" {
            throw Problem.missingField("kind")
        }
        guard let course = object["course"] as? String else {
            throw Problem.missingField("course")
        }
        guard let backupName = object["backup"] as? String else {
            throw Problem.missingField("backup")
        }
        guard let writtenText = object["writtenAt"] as? String,
              let writtenAt = SharedMediaDates.date(from: writtenText) else {
            throw Problem.missingField("writtenAt")
        }
        guard let host = object["host"] as? String else {
            throw Problem.missingField("host")
        }
        guard let mediaObjects = object["media"] as? [[String: Any]] else {
            throw Problem.missingField("media")
        }
        guard let folderObjects = object["folders"] as? [[String: Any]] else {
            throw Problem.missingField("folders")
        }

        var media: [MediaFile] = []
        for mediaObject in mediaObjects {
            guard let path = mediaObject["path"] as? String else {
                throw Problem.missingField("media.path")
            }
            if !SharedMediaList.isSafeMediaPath(path) {
                throw Problem.unsafePath(path)
            }
            guard let checksum = mediaObject["sha256"] as? String else {
                throw Problem.missingField("media.sha256")
            }
            if !SharedMediaList.isChecksum(checksum) {
                throw Problem.badChecksum(checksum)
            }
            guard let size = (mediaObject["size"] as? NSNumber)?.int64Value else {
                throw Problem.missingField("media.size")
            }
            guard let modifiedText = mediaObject["modified"] as? String,
                  let modified = SharedMediaDates.date(from: modifiedText) else {
                throw Problem.missingField("media.modified")
            }
            let mode: Int = (mediaObject["mode"] as? Int) ?? 0o644
            media.append(MediaFile(path: path, sha256: checksum, size: size, modified: modified, mode: mode))
        }

        var folders: [MediaFolder] = []
        for folderObject in folderObjects {
            guard let path = folderObject["path"] as? String else {
                throw Problem.missingField("folders.path")
            }
            if path != SharedMediaList.mediaFolderName && !SharedMediaList.isSafeMediaPath(path) {
                throw Problem.unsafePath(path)
            }
            let mode: Int = (folderObject["mode"] as? Int) ?? 0o755
            folders.append(MediaFolder(path: path, mode: mode))
        }

        return SharedMediaList(
            course: course,
            backupName: backupName,
            writtenAt: writtenAt,
            host: host,
            media: media,
            folders: folders
        )
    }

    /// The folder a small backup leaves out, at the top of the course.
    static let mediaFolderName: String = "Media"

    /// `Media/…` with no part that is empty, `.` or `..`, and no backslash
    /// (a Windows separator read on the mac would be one strange name, and
    /// on Windows a way out of the folder).
    static func isSafeMediaPath(_ path: String) -> Bool {
        let parts: [String] = path.components(separatedBy: "/")
        if parts.count < 2 || parts[0] != mediaFolderName {
            return false
        }
        for part in parts {
            if part.isEmpty || part == "." || part == ".." || part.contains("\\") || part.contains("\0") {
                return false
            }
        }
        return true
    }

    /// 64 lower-case hexadecimal digits.
    static func isChecksum(_ text: String) -> Bool {
        if text.utf8.count != 64 {
            return false
        }
        for byte in text.utf8 {
            let isDigit: Bool = byte >= 48 && byte <= 57
            let isLowerHex: Bool = byte >= 97 && byte <= 102
            if !isDigit && !isLowerHex {
                return false
            }
        }
        return true
    }
}

/// A list that keeps store files for something other than a backup zip: a
/// backup being written right now (`pending/`), or a step on the Undo list
/// (#899) that may bring a light backup back from the Trash (`lists/undo-…`).
///
/// It names checksums and the moment it was WRITTEN, by the writer's own
/// clock. That written moment is what decides how long it is honoured,
/// never a file's dates: a copied or synced file keeps or changes its dates
/// for reasons of its own (#785 plan review, amendment 1).
nonisolated struct SharedMediaHold: Equatable, Sendable {

    // MARK: - Types

    enum Kind: String, Sendable {
        /// A backup being written. Honoured for a day from `writtenAt`, and
        /// after that only while the process that wrote it is still running
        /// on this computer.
        case pending
        /// A step on the Undo list. Honoured for 31 days from `writtenAt`,
        /// by every computer that shares the working folder.
        case undo
    }

    // MARK: - Stored properties

    let kind: Kind

    /// The Undo step's id, or the pending backup's own id: also the file's
    /// name, after `undo-` or before `.json`.
    let id: String

    let writtenAt: Date
    let host: String

    /// The writing process, for a pending list; 0 for an Undo list.
    let pid: Int32

    let checksums: Set<String>

    // MARK: - Functions

    func encoded() throws -> Data {
        var sorted: [String] = []
        for checksum in checksums {
            sorted.append(checksum)
        }
        sorted.sort()
        var object: [String: Any] = [
            "format": SharedMediaList.formatNumber,
            "kind": kind.rawValue,
            "id": id,
            "writtenAt": SharedMediaDates.text(for: writtenAt),
            "host": host,
            "sha256": sorted,
        ]
        if kind == .pending {
            object["pid"] = Int(pid)
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func decoded(from data: Data) throws -> SharedMediaHold {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SharedMediaList.Problem.notJSON
        }
        guard let format = object["format"] as? Int else {
            throw SharedMediaList.Problem.missingField("format")
        }
        if format != SharedMediaList.formatNumber {
            throw SharedMediaList.Problem.wrongFormat(format)
        }
        guard let kindText = object["kind"] as? String, let kind = Kind(rawValue: kindText) else {
            throw SharedMediaList.Problem.missingField("kind")
        }
        guard let id = object["id"] as? String else {
            throw SharedMediaList.Problem.missingField("id")
        }
        guard let writtenText = object["writtenAt"] as? String,
              let writtenAt = SharedMediaDates.date(from: writtenText) else {
            throw SharedMediaList.Problem.missingField("writtenAt")
        }
        guard let host = object["host"] as? String else {
            throw SharedMediaList.Problem.missingField("host")
        }
        guard let checksumList = object["sha256"] as? [String] else {
            throw SharedMediaList.Problem.missingField("sha256")
        }
        var checksums: Set<String> = []
        for checksum in checksumList {
            if !SharedMediaList.isChecksum(checksum) {
                throw SharedMediaList.Problem.badChecksum(checksum)
            }
            checksums.insert(checksum)
        }
        var pid: Int32 = 0
        if kind == .pending {
            guard let number = object["pid"] as? Int else {
                throw SharedMediaList.Problem.missingField("pid")
            }
            pid = Int32(truncatingIfNeeded: number)
        }
        return SharedMediaHold(kind: kind, id: id, writtenAt: writtenAt, host: host, pid: pid, checksums: checksums)
    }
}

/// The one spelling of a moment in the store's files: UTC, with
/// milliseconds, `2026-11-13T18:38:00.000Z`. Read without milliseconds too.
nonisolated enum SharedMediaDates {

    // MARK: - Functions

    static func text(for moment: Date) -> String {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: moment)
    }

    static func date(from text: String) -> Date? {
        let withMilliseconds: ISO8601DateFormatter = ISO8601DateFormatter()
        withMilliseconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let moment = withMilliseconds.date(from: text) {
            return moment
        }
        let plain: ISO8601DateFormatter = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
