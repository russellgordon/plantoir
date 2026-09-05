import CryptoKit
import Foundation

/// Where a section's built website is kept — outside the working folder.
///
/// A built site is derived: every file in it comes from the teacher's notes
/// and can be produced again. It used to live at
/// `courses/<CODE>/.merged_output`, INSIDE the working folder, and Plantoir's
/// own backups already knew to skip it by name. Everything outside Plantoir
/// did not. A synced folder uploads every build to the cloud and charges it
/// against the teacher's quota; Time Machine backs it up; Finder's Get Info
/// counts it; a teacher who zips their folder to hand to a colleague carries
/// it. Windows moved its build output out for exactly this reason
/// (`PLANTOIR_BUILD_ROOT`), and this is the mac's half.
///
/// **It is done for EVERY working folder, not only synced ones.** The benefit
/// is not confined to syncing — a backup, a copy and a folder size are all
/// smaller for it — and one code path is one code path: a rule that applied
/// only to folders Plantoir believes are synced would be a rule tested in one
/// case and running in another.
///
/// **`.merged_output` becomes a SYMLINK** to `<builds root>/<folder id>/<CODE>`
/// rather than the path being computed everywhere. Three launchers, three Swift
/// readers, a launchd deploy and a teacher at the command line all name that
/// path today; the link means every one of them keeps working, resolves to the
/// same place, and cannot disagree about where the build went. The launchers
/// bind-mount the builds folder into the container at the SAME absolute path,
/// so the link resolves identically inside and out.
///
/// The rule is pinned by `contracts/shared-rules.json` → `buildOutputLocation`,
/// and the launchers carry the same rule in shell for the command line and for
/// launchd, which have no app to ask.
nonisolated enum BuildOutputLocation {

    // MARK: - Types

    /// What ensuring the link actually did, so a caller can say so on the
    /// trail — and so a test can tell "nothing needed doing" apart from
    /// "a teacher's built site was moved".
    enum Outcome: Equatable {
        /// The link was already pointing where it should.
        case alreadyLinked
        /// A real `.merged_output` folder was moved out of the working folder.
        case migrated
        /// There was nothing to move: a fresh link over a fresh folder.
        case linked
        /// A link pointing somewhere else — a renamed course, or a folder
        /// synced from another Mac where that path does not exist — was
        /// replaced, and any build sitting at the new place was cleared
        /// because nothing says it belongs to this course.
        case relinked
    }

    // MARK: - Stored properties

    /// The name the link has inside a course folder. Unchanged from the folder
    /// it replaces, because every reader already knows it.
    static let linkName: String = ".merged_output"

    /// Names the working folder a builds folder belongs to, so a sweep can
    /// tell an abandoned one from a live one — the hash cannot be reversed.
    static let workingFolderMarkerName: String = "working-folder.txt"

    /// Where builds go. Replaceable so a test can point it somewhere of its
    /// own rather than writing into the teacher's real Application Support.
    nonisolated(unsafe) static var buildsRootOverride: URL?

    /// True inside the test bundle.
    static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    /// One temporary builds root for the whole test run, so a test that goes
    /// through `CourseArchiver` or `CourseRenamer` without setting an override
    /// still cannot touch the real one.
    static let buildsRootWhileTesting: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("plantoir-builds-under-test-\(ProcessInfo.processInfo.processIdentifier)")

    // MARK: - Computed properties

    /// `~/Library/Application Support/Plantoir/builds`.
    ///
    /// Under the home folder deliberately: the Colima VM mounts only `$HOME`,
    /// so a builds folder anywhere else would bind-mount into the container as
    /// an empty folder and every build would appear to vanish.
    ///
    /// **Under tests this answers a temporary folder instead**, and that is
    /// not tidiness. Archiving and renaming a course now reach in here, and
    /// their own tests do those things to fixtures with made-up paths — so
    /// without this, running the suite would scatter folders through the
    /// teacher's real Application Support and delete things out of it. The
    /// real answer stays testable as `buildsRoot(inHomeFolder:)`.
    static var buildsRoot: URL {
        if let buildsRootOverride {
            return buildsRootOverride
        }
        if isRunningTests {
            return buildsRootWhileTesting
        }
        return buildsRoot(inHomeFolder: FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: - Functions

    /// Where builds live for a given home folder — the real rule, as a pure
    /// function so it can be checked without writing anything anywhere.
    static func buildsRoot(inHomeFolder home: URL) -> URL {
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("builds")
    }

    /// The eight hex characters that stand for one working folder.
    ///
    /// The launchers derive the same value with `pwd -P | shasum -a 256`, so
    /// the trailing newline is part of the hashed input here too, and the path
    /// is resolved with POSIX `realpath` rather than Foundation's
    /// `resolvingSymlinksInPath()` — the latter strips the `/private` prefix
    /// from `/var` and `/tmp` paths where `pwd -P` keeps it, and the two sides
    /// would hash different strings.
    static func folderIdentifier(forWorkingFolder path: String) -> String {
        var physical: String = path
        if let resolved = realpath(path, nil) {
            physical = String(cString: resolved)
            free(resolved)
        }
        let hashed: SHA256.Digest = SHA256.hash(data: Data((physical + "\n").utf8))
        var hex: String = ""
        for byte in hashed {
            hex += String(format: "%02x", byte)
        }
        return String(hex.prefix(8))
    }

    /// Every build belonging to one working folder.
    static func buildsFolder(forWorkingFolder workingFolderURL: URL) -> URL {
        let identifier: String = folderIdentifier(forWorkingFolder: workingFolderURL.path)
        return buildsRoot.appendingPathComponent(identifier)
    }

    /// Where one course's built sites live.
    static func buildFolder(forWorkingFolder workingFolderURL: URL, courseCode: String) -> URL {
        return buildsFolder(forWorkingFolder: workingFolderURL).appendingPathComponent(courseCode)
    }

    /// The link inside a course folder.
    static func linkURL(courseDirectory: URL) -> URL {
        return courseDirectory.appendingPathComponent(linkName)
    }

    /// Points `courses/<CODE>/.merged_output` at this course's builds folder,
    /// moving an existing built site out of the working folder on the way.
    ///
    /// Safe to call as often as you like: when the link is already right it
    /// touches nothing and answers `.alreadyLinked`.
    ///
    /// **A course with no link is a course whose build cannot be trusted.**
    /// Archiving a course, restoring one from a backup and replacing a
    /// course's contents all remove the link along with everything else in the
    /// folder — and each of them leaves content whose timestamps may be OLDER
    /// than the built site standing outside. Reusing that build would let a
    /// restored course publish last month's pages while every check said it
    /// was up to date, which is the silent wrong answer this codebase exists
    /// to refuse. So a build folder found with no link pointing at it is
    /// cleared rather than adopted.
    @discardableResult
    static func ensureLink(courseDirectory: URL, workingFolderURL: URL) throws -> Outcome {
        let fileManager: FileManager = FileManager.default
        let link: URL = linkURL(courseDirectory: courseDirectory)
        let target: URL = buildFolder(
            forWorkingFolder: workingFolderURL,
            courseCode: courseDirectory.lastPathComponent
        )

        let existingTarget: String? = try? fileManager.destinationOfSymbolicLink(atPath: link.path)
        if let existingTarget {
            if existingTarget == target.path && directoryExists(target) {
                return .alreadyLinked
            }
            try fileManager.removeItem(at: link)
            try linkFreshly(target: target, at: link, workingFolderURL: workingFolderURL)
            return .relinked
        }

        if directoryExists(link) {
            // A real folder: the teacher's current built site, and the one
            // thing here that is authoritative. Anything already standing at
            // the target belongs to an earlier life of this course code.
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: target)
            }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: link, to: target)
            try writeWorkingFolderMarker(workingFolderURL: workingFolderURL)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
            return .migrated
        }

        if fileManager.fileExists(atPath: link.path) {
            // Neither a link nor a folder — a stray file wearing the name.
            try fileManager.removeItem(at: link)
        }
        try linkFreshly(target: target, at: link, workingFolderURL: workingFolderURL)
        return .linked
    }

    /// Throws away a course's built sites, because the course itself has gone
    /// or its contents have been replaced.
    static func discardBuild(forWorkingFolder workingFolderURL: URL, courseCode: String) {
        let target: URL = buildFolder(forWorkingFolder: workingFolderURL, courseCode: courseCode)
        try? FileManager.default.removeItem(at: target)
    }

    /// Throws away ONE section's built site, for a section that has been
    /// archived out of a course that stays.
    static func discardSectionBuild(
        forWorkingFolder workingFolderURL: URL,
        courseCode: String,
        sectionNumber: Int
    ) {
        let section: URL = buildFolder(forWorkingFolder: workingFolderURL, courseCode: courseCode)
            .appendingPathComponent("section\(sectionNumber)")
        try? FileManager.default.removeItem(at: section)
    }

    /// Carries a course's built sites across a rename, so renaming a course
    /// does not silently throw its website away — which is what happened
    /// before the output moved, since the folder travelled with the course.
    ///
    /// The link inside the renamed folder still names the old target; it is
    /// re-pointed here rather than left for `ensureLink` to notice, because
    /// `ensureLink`'s answer to a link pointing elsewhere is to start again
    /// from nothing.
    static func moveBuild(
        forWorkingFolder workingFolderURL: URL,
        fromCourseCode oldCode: String,
        toCourseCode newCode: String,
        renamedCourseDirectory: URL
    ) {
        let fileManager: FileManager = FileManager.default
        let oldTarget: URL = buildFolder(forWorkingFolder: workingFolderURL, courseCode: oldCode)
        let newTarget: URL = buildFolder(forWorkingFolder: workingFolderURL, courseCode: newCode)
        if directoryExists(oldTarget) {
            try? fileManager.removeItem(at: newTarget)
            try? fileManager.moveItem(at: oldTarget, to: newTarget)
        }
        // Re-pointed by hand rather than by calling `ensureLink`, and this is
        // the whole reason this function exists: `ensureLink`'s answer to a
        // link pointing somewhere else is to clear the target and start from
        // nothing, which would throw away the site that has just been carried
        // across.
        let link: URL = linkURL(courseDirectory: renamedCourseDirectory)
        if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try? fileManager.removeItem(at: link)
        }
        try? fileManager.createDirectory(at: newTarget, withIntermediateDirectories: true)
        try? writeWorkingFolderMarker(workingFolderURL: workingFolderURL)
        try? fileManager.createSymbolicLink(at: link, withDestinationURL: newTarget)
    }

    /// Removes builds belonging to courses this working folder no longer has.
    ///
    /// Archiving a course removes its folder and its link in one step, and the
    /// build standing outside would otherwise sit in Application Support for
    /// ever, invisible. Only ever touches this folder's own builds folder, and
    /// only entries whose course is genuinely absent.
    static func discardBuildsForMissingCourses(
        workingFolderURL: URL,
        courseCodesPresent: [String]
    ) {
        let fileManager: FileManager = FileManager.default
        let builds: URL = buildsFolder(forWorkingFolder: workingFolderURL)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: builds, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else {
            return
        }
        for entry in entries {
            let name: String = entry.lastPathComponent
            if name == workingFolderMarkerName {
                continue
            }
            if courseCodesPresent.contains(name) {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    /// Removes the builds of working folders that no longer exist.
    ///
    /// A teacher who throws a working folder away leaves its builds behind,
    /// and the folder's identifier is a hash that cannot be turned back into a
    /// path — so each builds folder writes down which working folder it serves
    /// and this reads it. A builds folder with no marker is left alone: it was
    /// written by a version that did not record one, and guessing is not worth
    /// deleting somebody's site over.
    ///
    /// **Only folders under the home folder are ever swept**, and that is the
    /// guard that makes this safe rather than a way to lose work. "The folder
    /// is not there" and "the disk it is on is not plugged in" look exactly
    /// alike from here; the home volume is always mounted, so a path under it
    /// that does not exist is genuinely gone, while a path on `/Volumes` might
    /// be back tomorrow. Builds for those simply accumulate, which is the
    /// cheaper mistake.
    static func discardBuildsForMissingWorkingFolders(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let fileManager: FileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: buildsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else {
            return
        }
        let homePrefix: String = homeDirectory.path.hasSuffix("/")
            ? homeDirectory.path
            : homeDirectory.path + "/"
        for entry in entries {
            let marker: URL = entry.appendingPathComponent(workingFolderMarkerName)
            guard let recorded = try? String(contentsOf: marker, encoding: .utf8) else {
                continue
            }
            let path: String = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty || !path.hasPrefix(homePrefix) {
                continue
            }
            if fileManager.fileExists(atPath: path) {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Private functions

    /// A fresh target and a fresh link, clearing whatever was standing at the
    /// target: see `ensureLink`'s note on why an unclaimed build is not
    /// adopted.
    private static func linkFreshly(target: URL, at link: URL, workingFolderURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try writeWorkingFolderMarker(workingFolderURL: workingFolderURL)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// Writes which working folder this builds folder serves.
    private static func writeWorkingFolderMarker(workingFolderURL: URL) throws {
        let builds: URL = buildsFolder(forWorkingFolder: workingFolderURL)
        try FileManager.default.createDirectory(at: builds, withIntermediateDirectories: true)
        let marker: URL = builds.appendingPathComponent(workingFolderMarkerName)
        var physical: String = workingFolderURL.path
        if let resolved = realpath(workingFolderURL.path, nil) {
            physical = String(cString: resolved)
            free(resolved)
        }
        try (physical + "\n").write(to: marker, atomically: true, encoding: .utf8)
    }

    /// True for a real directory, or a symlink that resolves to one.
    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
