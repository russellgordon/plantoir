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

    // MARK: - Stored properties

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

    /// Opens a zip into a new folder of its own and finds the course in it.
    ///
    /// `@concurrent` so the unzipping runs off the main actor and the sheet's
    /// spinner keeps spinning (`ReferenceImportSource.read` says why the
    /// attribute is needed in this project).
    @concurrent
    static func open(
        _ zipURL: URL,
        into parentURL: URL = FileManager.default.temporaryDirectory
    ) async -> Outcome {
        return ReferenceZipSource.openNow(zipURL, into: parentURL)
    }

    /// The same, where the caller is already off the main actor.
    static func openNow(
        _ zipURL: URL,
        into parentURL: URL = FileManager.default.temporaryDirectory
    ) -> Outcome {
        let zipName: String = zipURL.lastPathComponent

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

        // The second look: nothing unpacked may be a link, whatever the
        // listing said.
        if ReferenceZipSource.holdsALink(openedURL) {
            ReferenceZipSource.remove(openedURL)
            return .refused(ReferenceImportWording.zipIsNotSafeToOpen(zip: zipName))
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

    /// Takes away a folder a zip was opened into. Unlocked first: a backup of
    /// a course kept for reference can carry its locked files.
    static func remove(_ openedURL: URL) {
        guard openedURL.lastPathComponent.hasPrefix(ReferenceZipSource.openedFolderPrefix) else {
            return
        }
        let unlock: Process = Process()
        unlock.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        unlock.arguments = ["-R", "nouchg", openedURL.path]
        try? unlock.run()
        unlock.waitUntilExit()
        try? FileManager.default.removeItem(at: openedURL)
    }

    // MARK: - Private helpers

    /// Whether anything under a folder is a link, asked without following any.
    private static func holdsALink(_ folderURL: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(
            at: folderURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ) else {
            return true
        }
        for case let entryURL as URL in walker {
            let values: URLResourceValues? = try? entryURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                return true
            }
        }
        return false
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
