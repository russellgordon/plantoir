import Foundation

/// A backup or archive zip chosen in Import Courses for Reference… (#572),
/// opened into a folder of its own so the import can read the course inside
/// it exactly as it reads a course folder.
///
/// **Why a zip goes through the import rather than a door of its own.** A
/// backup or an archive holds one course folder at its root, which is the
/// "one course folder" shape `ReferenceImportSource.resolve` already accepts,
/// and `ReferenceImporter` already has everything such a course needs: the
/// shelf rule per row, the claim and staging, the lock cleared, the names left
/// behind, the one dangerous sequence, the year picker, the summary and the
/// trail lines. Russell's ruling of 2026-11-12 is three doors and one path,
/// with no separate restore-as-reference door.
///
/// **The zip is opened OUTSIDE the working folder** (in the system's
/// temporary folder), so the import's "inside the folder you already have
/// open" refusal does not catch it, and it is never written to: it is read
/// once by the system's own unzipper.
///
/// **A zip is someone else's file, so it is checked before it is opened and
/// again after.** Measured on macOS 26 with `/usr/bin/ditto -x -k`: a name
/// beginning `/` and a name holding `..` are both written INSIDE the folder
/// given (ditto drops the leading slash and the dots), so neither escapes;
/// but a link stored in the zip is made as a real link, pointing wherever the
/// zip says. A course never needs any of the three, so all three refuse the
/// whole zip, before anything is unpacked (from the zip's own listing) and
/// after (every entry unpacked is looked at without following links), and
/// what was unpacked is removed.
nonisolated enum ReferenceZipSource {

    // MARK: - Types

    /// What opening a zip came to.
    enum Outcome: Equatable, Sendable {
        /// The course folder inside it, and the folder it was opened into,
        /// which the caller removes once the import is over.
        case opened(courseFolderURL: URL, openedIntoURL: URL)

        /// Why not, in the sentence the teacher reads.
        case refused(String)
    }

    /// What a zip's listing says it holds: `zipinfo`'s closing line,
    /// "3 files, 1073741827 bytes uncompressed, 1043643 bytes compressed".
    struct ListingTotals: Equatable, Sendable {
        let files: Int
        let uncompressedBytes: Int64
        let compressedBytes: Int64
    }

    /// Why a zip is refused on its size alone, before anything is unpacked.
    enum SizeTrouble: Equatable, Sendable {
        /// More entries than any course holds.
        case tooManyFiles

        /// Unpacks to far more than any course, by its total or by how much
        /// it grows: the shape of a zip made to fill a disk.
        case farLargerThanACourse

        /// Real enough, but this Mac has not the room to unpack it and then
        /// copy it into the working folder.
        case needsMoreRoom
    }

    // MARK: - Stored properties

    /// The most entries a zip may hold. The largest course folder measured
    /// for #206 held 44,532 entries WITH its built website, which a backup
    /// leaves out; the real ICS4U a backup holds is 943 files.
    static let mostFiles: Int = 100_000

    /// The most a zip may unpack to: forty times the 489 MB of the largest
    /// real course measured (`09-mac-app.md` → "What the copy costs").
    static let mostBytes: Int64 = 20 * 1_073_741_824

    /// How much a zip may grow when unpacked, once it is big enough to
    /// matter. Measured: the ICS4U payload zipped by `ditto` grows 2.1
    /// times (299,963 bytes to 630,380), and a course with pictures and PDFs,
    /// which are already compressed, grows less. A gigabyte of zeros zipped
    /// grows 1,029 times.
    static let mostGrowth: Int64 = 100

    /// Below this a zip's growth is not asked about: a small course of plain
    /// pages can grow a lot and still be nothing.
    static let growthAskedAbove: Int64 = 256 * 1_048_576

    /// Room kept free on a disk after unpacking and copying.
    static let roomToSpare: Int64 = 1_073_741_824

    /// What the folders a zip is opened into are called, in the temporary
    /// folder.
    static let openedFolderPrefix: String = "Plantoir-reference-zip-"

    /// What Finder's own Compress leaves beside the folder: the resource
    /// forks, which `ditto` folds back into the files they belong to.
    static let finderResourceFolder: String = "__MACOSX"

    // MARK: - Functions

    /// Whether the chosen file is a zip rather than a folder.
    static func isAZip(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() != "zip" {
            return false
        }
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Whether every name in a zip's listing stays inside the folder it is
    /// opened into: not absolute, no `..` part, no backslash (which another
    /// system reads as a folder), and not empty.
    static func namesStayInside(_ names: [String]) -> Bool {
        if names.isEmpty {
            return false
        }
        for name in names {
            if name.isEmpty || name.hasPrefix("/") || name.hasPrefix("~") || name.contains("\\") {
                return false
            }
            for part in name.split(separator: "/", omittingEmptySubsequences: false) {
                if part == ".." {
                    return false
                }
            }
        }
        return true
    }

    /// Whether a zip's long listing (`zipinfo`'s default lines) names a link:
    /// an entry whose permissions begin with `l`.
    static func listingHoldsALink(_ lines: [String]) -> Bool {
        for line in lines {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.split(separator: " ").first else {
                continue
            }
            // Ten characters of permissions, as `ls -l` writes them.
            if first.count == 10 && first.hasPrefix("l") {
                return true
            }
        }
        return false
    }

    /// The totals from `zipinfo`'s closing line, or nil when it is not one.
    static func totals(fromSummaryLine line: String) -> ListingTotals? {
        let parts: [Substring] = line.split(separator: ",")
        guard parts.count >= 3 else {
            return nil
        }
        let fileWords: [Substring] = parts[0].split(separator: " ")
        let uncompressedWords: [Substring] = parts[1].split(separator: " ")
        let compressedWords: [Substring] = parts[2].split(separator: " ")
        guard fileWords.count == 2, fileWords[1].hasPrefix("file"),
              uncompressedWords.count >= 3, uncompressedWords[2] == "uncompressed",
              compressedWords.count >= 3, compressedWords[2].hasPrefix("compressed"),
              let files = Int(fileWords[0]),
              let uncompressed = Int64(uncompressedWords[0]),
              let compressed = Int64(compressedWords[0]) else {
            return nil
        }
        return ListingTotals(files: files, uncompressedBytes: uncompressed, compressedBytes: compressed)
    }

    /// Whether a zip of these totals is refused on its size, given the room
    /// on the disk it is opened on and the one it is copied to.
    static func sizeTrouble(
        _ totals: ListingTotals,
        freeWhereOpened: Int64,
        freeWhereCopied: Int64,
        sameDisk: Bool
    ) -> SizeTrouble? {
        if totals.files > ReferenceZipSource.mostFiles {
            return .tooManyFiles
        }
        let unpacked: Int64 = totals.uncompressedBytes
        if unpacked > ReferenceZipSource.mostBytes {
            return .farLargerThanACourse
        }
        if unpacked > ReferenceZipSource.growthAskedAbove {
            let compressed: Int64 = max(totals.compressedBytes, 1)
            if unpacked / compressed > ReferenceZipSource.mostGrowth {
                return .farLargerThanACourse
            }
        }
        if sameDisk {
            if freeWhereOpened < unpacked * 2 + ReferenceZipSource.roomToSpare {
                return .needsMoreRoom
            }
        } else {
            if freeWhereOpened < unpacked + ReferenceZipSource.roomToSpare {
                return .needsMoreRoom
            }
            if freeWhereCopied < unpacked + ReferenceZipSource.roomToSpare {
                return .needsMoreRoom
            }
        }
        return nil
    }

    /// The sentence for a size refusal.
    static func sentence(for trouble: SizeTrouble, zip zipName: String, unpackedBytes: Int64) -> String {
        switch trouble {
        case .tooManyFiles, .farLargerThanACourse:
            return ReferenceImportWording.zipIsFarLargerThanACourse(zip: zipName)
        case .needsMoreRoom:
            return ReferenceImportWording.zipNeedsMoreRoom(
                zip: zipName, size: ReferenceImportWording.size(unpackedBytes)
            )
        }
    }

    /// Opens a zip into a new folder of its own and finds the course in it.
    ///
    /// `@concurrent` so the unzipping runs off the main actor and the sheet's
    /// spinner keeps spinning (`ReferenceImportSource.read` says why the
    /// attribute is needed in this project).
    @concurrent
    static func open(
        _ zipURL: URL,
        into parentURL: URL = FileManager.default.temporaryDirectory,
        copyingInto coursesDirectoryURL: URL? = nil
    ) async -> Outcome {
        return ReferenceZipSource.openNow(zipURL, into: parentURL, copyingInto: coursesDirectoryURL)
    }

    /// The same, where the caller is already off the main actor.
    static func openNow(
        _ zipURL: URL,
        into parentURL: URL = FileManager.default.temporaryDirectory,
        copyingInto coursesDirectoryURL: URL? = nil,
        freeSpace: ((URL) -> Int64?)? = nil
    ) -> Outcome {
        let zipName: String = zipURL.lastPathComponent

        // Its size first, from the listing's closing line alone, so a zip
        // of a million entries is refused before a million names are read.
        guard let summary = ReferenceZipSource.run("/usr/bin/zipinfo", ["-t", zipURL.path]),
              let lastLine = summary.last,
              let totals = ReferenceZipSource.totals(fromSummaryLine: lastLine) else {
            return .refused(ReferenceImportWording.zipCouldNotBeOpened(zip: zipName))
        }
        let measureRoom: (URL) -> Int64? = freeSpace ?? { url in
            return ReferenceZipSource.freeBytes(on: url)
        }
        let copiedTo: URL = coursesDirectoryURL ?? parentURL
        let freeWhereOpened: Int64 = measureRoom(parentURL) ?? 0
        let freeWhereCopied: Int64 = measureRoom(copiedTo) ?? 0
        if let trouble = ReferenceZipSource.sizeTrouble(
            totals,
            freeWhereOpened: freeWhereOpened,
            freeWhereCopied: freeWhereCopied,
            sameDisk: ReferenceZipSource.areOnTheSameDisk(parentURL, copiedTo)
        ) {
            return .refused(ReferenceZipSource.sentence(
                for: trouble, zip: zipName, unpackedBytes: totals.uncompressedBytes
            ))
        }

        guard let names = ReferenceZipSource.run("/usr/bin/zipinfo", ["-1", zipURL.path]) else {
            return .refused(ReferenceImportWording.zipCouldNotBeOpened(zip: zipName))
        }
        guard let longListing = ReferenceZipSource.run("/usr/bin/zipinfo", [zipURL.path]) else {
            return .refused(ReferenceImportWording.zipCouldNotBeOpened(zip: zipName))
        }
        if names.isEmpty {
            return .refused(ReferenceImportWording.zipHoldsNoCourse(zip: zipName))
        }
        if !ReferenceZipSource.namesStayInside(names) || ReferenceZipSource.listingHoldsALink(longListing) {
            return .refused(ReferenceImportWording.zipIsNotSafeToOpen(zip: zipName))
        }

        let openedURL: URL = parentURL.appendingPathComponent(
            ReferenceZipSource.openedFolderPrefix + UUID().uuidString
        )
        do {
            try FileManager.default.createDirectory(at: openedURL, withIntermediateDirectories: true)
        } catch {
            return .refused(ReferenceImportWording.zipCouldNotBeOpened(zip: zipName))
        }

        if ReferenceZipSource.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, openedURL.path]) == nil {
            ReferenceZipSource.remove(openedURL)
            return .refused(ReferenceImportWording.zipCouldNotBeOpened(zip: zipName))
        }

        // Every folder made readable and searchable by this account before
        // anything is looked at. A zip can give a folder a mode with no x
        // bit, and a walk cannot see inside one, so a link in it went unseen
        // (#572 implementation review M1, measured: a link stored by an
        // MS-DOS host, which `zipinfo` lists as an ordinary file, inside a
        // folder given mode 0600 after the link was written).
        _ = ReferenceZipSource.run("/bin/chmod", ["-R", "u+rwX", openedURL.path])

        // The second look: nothing unpacked may be a link, whatever the
        // listing said. The listing catches a link only when the zip says it
        // came from Unix or macOS.
        if ReferenceZipSource.holdsALink(openedURL) {
            ReferenceZipSource.remove(openedURL)
            return .refused(ReferenceImportWording.zipIsNotSafeToOpen(zip: zipName))
        }

        if ReferenceZipSource.courseFolderCount(in: openedURL) > 1 {
            ReferenceZipSource.remove(openedURL)
            return .refused(ReferenceImportWording.zipHoldsSeveralCourses(zip: zipName))
        }
        guard let courseFolderURL = ReferenceZipSource.theOneCourseFolder(in: openedURL) else {
            ReferenceZipSource.remove(openedURL)
            return .refused(ReferenceImportWording.zipHoldsNoCourse(zip: zipName))
        }
        return .opened(courseFolderURL: courseFolderURL, openedIntoURL: openedURL)
    }

    /// The one course folder at the top of what was unpacked, or nil.
    ///
    /// A backup and an archive hold exactly one folder at their root, the
    /// course itself (`CourseRestorer.unpack` relies on the same shape).
    /// Hidden entries and Finder's resource folder are not counted.
    static func theOneCourseFolder(in openedURL: URL) -> URL? {
        let fileManager: FileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: openedURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var folders: [URL] = []
        for entry in entries {
            if entry.lastPathComponent == ReferenceZipSource.finderResourceFolder {
                continue
            }
            folders.append(entry)
        }
        guard folders.count == 1, let only = folders.first else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: only.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let config: URL = only.appendingPathComponent(ReferenceImportSource.configFileName)
        guard fileManager.fileExists(atPath: config.path) else {
            return nil
        }
        return only
    }

    /// How many folders at the top of what was unpacked hold a course's
    /// settings, so a zip of two courses is told so rather than told it
    /// holds none.
    static func courseFolderCount(in openedURL: URL) -> Int {
        let fileManager: FileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: openedURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count: Int = 0
        for entry in entries {
            let config: URL = entry.appendingPathComponent(ReferenceImportSource.configFileName)
            if fileManager.fileExists(atPath: config.path) {
                count += 1
            }
        }
        return count
    }

    /// Takes away a folder a zip was opened into, whatever the unpacking
    /// left: unlocked first (a backup of a course kept for reference can
    /// carry its locked files), and every folder given back its read, write
    /// and search bits (a zip can leave a folder with none, which
    /// `removeItem` cannot empty). Returns whether it is gone.
    @discardableResult
    static func remove(_ openedURL: URL) -> Bool {
        guard openedURL.lastPathComponent.hasPrefix(ReferenceZipSource.openedFolderPrefix) else {
            return false
        }
        _ = ReferenceZipSource.run("/usr/bin/chflags", ["-R", "nouchg", openedURL.path])
        _ = ReferenceZipSource.run("/bin/chmod", ["-R", "u+rwX", openedURL.path])
        try? FileManager.default.removeItem(at: openedURL)
        return !FileManager.default.fileExists(atPath: openedURL.path)
    }

    /// Free bytes on the disk a folder is on, or nil when it cannot be read.
    static func freeBytes(on folderURL: URL) -> Int64? {
        let values: URLResourceValues? = try? folderURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Whether two folders are on one disk, so unpacking and copying share
    /// its room.
    static func areOnTheSameDisk(_ first: URL, _ second: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let one = try? first.resourceValues(forKeys: keys).volumeIdentifier as? NSObject,
              let other = try? second.resourceValues(forKeys: keys).volumeIdentifier as? NSObject else {
            return true
        }
        return one.isEqual(other)
    }

    // MARK: - Private helpers

    /// Whether anything under a folder is a link, asked without following any.
    /// A folder the walk could not look inside counts as holding one: the
    /// answer this check cannot give is never "no".
    private static func holdsALink(_ folderURL: URL) -> Bool {
        var couldNotLook: Bool = false
        guard let walker = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
                couldNotLook = true
                return true
            }
        ) else {
            return true
        }
        for case let entryURL as URL in walker {
            let values: URLResourceValues? = try? entryURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                return true
            }
        }
        return couldNotLook
    }

    /// Runs a system tool and returns its output's lines, or nil when it did
    /// not succeed.
    private static func run(_ executable: String, _ arguments: [String]) -> [String]? {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            return nil
        }
        let text: String = String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lines.append(String(line))
        }
        return lines
    }
}
