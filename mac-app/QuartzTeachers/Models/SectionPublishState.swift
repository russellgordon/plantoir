import CryptoKit
import Foundation

/// Whether a section's pages have been edited since they were last
/// published — the question behind the " — Edited" marker in a section
/// window's title bar.
///
/// The teacher's mental model is the one Pages uses: the title bar tells
/// you, without being asked, that what you are looking at is not what is
/// out there. Plantoir had no way to answer it, because nothing anywhere
/// recorded when a section was last published. This records it.
///
/// Three decisions are worth knowing before changing anything here.
///
/// **The fingerprint is of the file INVENTORY, not the file contents.**
/// Each page contributes its relative path, its size and its modification
/// date; the sorted list is hashed. That is one directory walk asking for
/// two resource values — no page is ever read — so it costs single-digit
/// milliseconds on a course of a few hundred pages, and it can run every
/// time a window comes to the front. Hashing contents would mean reading
/// every byte of every page for a marker nobody asked to be exact. The
/// price is paid in both directions, and the second is the one to know
/// about. Touching a page without changing it reads as an EDIT, which is
/// the same bargain every save indicator makes. And a page restored from a
/// backup that preserved its modification date, whose length happens to be
/// unchanged, reads as UP TO DATE — `cp -p`, `rsync -a`, unzipping and
/// Time Machine all preserve dates. That is a genuine false negative,
/// accepted rather than overlooked: the cure is hashing every byte of
/// every page on every check, and publishing is never blocked by the
/// marker, so a teacher who suspects it can simply publish. It is a
/// contract case (`publishedFreshness.whenShown`) so it is not
/// rediscovered later as a bug.
///
/// A plain "is anything newer than the publish date" check would have been
/// cheaper still, and was rejected: modification dates cannot see a
/// DELETION, and deleting a class page is precisely the edit a teacher
/// would be alarmed to find unpublished. An inventory catches adds,
/// removals, renames and edits in one value.
///
/// **A page shared with other sections marks EVERY section edited.** A
/// course-level page carries `publishForSection<N>` — one key per section
/// — so editing only section 3's key changes only section 3's site, and
/// the marker will nonetheless appear on section 1 too. Being exact would
/// mean parsing the frontmatter of every shared page on every check, to
/// spare a teacher an occasional marker that is early rather than wrong.
/// The wording the teacher reads was chosen to be true either way: a page
/// this section uses, or shares, has changed.
///
/// **The stamp lives in a HIDDEN folder**, which is load-bearing rather
/// than tidy: `fingerprint(...)` skips hidden entries, so a stamp written
/// anywhere visible would itself be content, and publishing would leave
/// the section looking edited the instant it finished.
nonisolated enum SectionPublishState {

    // MARK: - Nested types

    /// What was published, and when.
    struct Stamp: Codable, Equatable {

        // MARK: - Stored properties

        /// The content fingerprint as it stood when the upload began.
        let fingerprint: String

        let publishedAt: Date

        /// Which destinations it went to — `netlify`, `cloudflare_pages`,
        /// `local_folder`. Recorded because a course that has since been
        /// pointed somewhere else has not published THERE, and a later
        /// reader of this file should not have to guess.
        let destinations: [String]
    }

    // MARK: - Stored properties

    /// Entries that are not a teacher's content, however they are named.
    ///
    /// `course_config.backup.json` and the `.json.tmp` beside it are
    /// written by `build_site.py`'s own preflight, at publish time — left
    /// in, every publish that discovered a new folder would end by
    /// declaring the section edited.
    private static let ignoredFileNames: Set<String> = [
        ".DS_Store",
        "Thumbs.db",
        "course_config.backup.json"
    ]

    /// Folders that are output or machinery rather than content.
    /// `.merged_output`, `.obsidian`, `.netlify_sites` and the rest are
    /// hidden and already skipped; these two are not.
    private static let ignoredFolderNames: Set<String> = [
        "merged_output",
        "node_modules"
    ]

    // MARK: - Functions

    /// Where a section's stamp is kept.
    static func stampURL(courseDirectory: URL, sectionNumber: Int) -> URL {
        return courseDirectory
            .appendingPathComponent(".publish_state")
            .appendingPathComponent("section\(sectionNumber).json")
    }

    /// True when a file belongs in a section's fingerprint.
    ///
    /// Named separately from the walk so the contract can be run against
    /// the RULE rather than against a folder full of fixtures.
    static func countsTowardFingerprint(relativePath: String, sectionNumber: Int) -> Bool {
        let parts: [String] = pathParts(relativePath)
        guard let fileName = parts.last else {
            return false
        }
        for part in parts where part.hasPrefix(".") {
            return false
        }
        if ignoredFileNames.contains(fileName) {
            return false
        }
        if fileName.hasSuffix(".tmp") {
            return false
        }
        for part in parts.dropLast() where ignoredFolderNames.contains(part) {
            return false
        }
        // Another section's folder is another section's site. The build
        // copies `section<N>/` into this section and nobody else's.
        if let first = parts.first, isSectionFolderName(first), first != "section\(sectionNumber)" {
            return false
        }
        return true
    }

    /// True when a FOLDER may hold files that count — so a folder that
    /// cannot is never descended into.
    static func folderCountsTowardFingerprint(relativePath: String, sectionNumber: Int) -> Bool {
        let parts: [String] = pathParts(relativePath)
        for part in parts where part.hasPrefix(".") {
            return false
        }
        for part in parts where ignoredFolderNames.contains(part) {
            return false
        }
        if let first = parts.first, isSectionFolderName(first), first != "section\(sectionNumber)" {
            return false
        }
        return true
    }

    /// True for `section3` and not for `sections` or `section3b`.
    static func isSectionFolderName(_ name: String) -> Bool {
        guard name.hasPrefix("section") else {
            return false
        }
        let digits: Substring = name.dropFirst("section".count)
        if digits.isEmpty {
            return false
        }
        for character in digits where !character.isNumber {
            return false
        }
        return true
    }

    /// A single value standing for everything this section's site is built
    /// from, as it stands on disk right now.
    ///
    /// Deliberately derived from what is ON DISK rather than from
    /// `course_config.json`'s `shared_folders` / `per_section_folders`
    /// lists: `build_site.py` DISCOVERS new folders at publish time and
    /// appends them to those lists afterwards, so a folder the teacher
    /// created this morning is a real input to the site and is not in the
    /// configuration yet. Reading the lists would leave that folder
    /// invisible to the marker until the next publish — which is exactly
    /// the publish the marker exists to prompt.
    static func fingerprint(
        courseDirectory: URL,
        sectionNumber: Int,
        excludingRelativePaths: [String] = []
    ) -> String {
        var lines: [String] = []
        let fileManager: FileManager = FileManager.default
        let root: URL = courseDirectory
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(SectionPublishState.wantedKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return digest(of: "")
        }

        for case let fileURL as URL in enumerator {
            let relativePath: String = relativePathOf(fileURL, under: root)
            if relativePath.isEmpty {
                continue
            }
            if isExcluded(relativePath: relativePath, by: excludingRelativePaths) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: SectionPublishState.wantedKeys)

            // A symlink is content the teacher can see and Quartz can
            // read, and `FileManager`'s enumerator neither follows one nor
            // reports it as a regular file. Left as-is, a `Media` folder
            // symlinked into an Obsidian vault — the arrangement
            // `build_site.py`'s own `_ensure_media_symlink` exists for —
            // would contribute NOTHING, and every change inside it would
            // read as "up to date". So links are resolved by hand, once:
            // a link to a file contributes the target's own size and date
            // under the LINK's path, and a link to a folder is walked.
            if values?.isSymbolicLink == true {
                appendLines(
                    &lines,
                    forSymbolicLinkAt: fileURL,
                    relativePath: relativePath,
                    sectionNumber: sectionNumber,
                    excluding: excludingRelativePaths
                )
                continue
            }

            if values?.isRegularFile != true {
                // A folder that cannot contribute is not descended into —
                // this is what keeps the walk off `.merged_output`-sized
                // trees and off eleven other sections' pages.
                if !folderCountsTowardFingerprint(relativePath: relativePath, sectionNumber: sectionNumber) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if !countsTowardFingerprint(relativePath: relativePath, sectionNumber: sectionNumber) {
                continue
            }
            lines.append(line(forRelativePath: relativePath, values: values))
        }

        lines.sort()
        return digest(of: lines.joined(separator: "\n"))
    }

    /// The stamp a section carries, or nil when it has never been
    /// published — or when the file cannot be read, which is treated the
    /// same way on purpose: an unreadable stamp must not be allowed to
    /// claim a section is up to date.
    static func stamp(courseDirectory: URL, sectionNumber: Int) -> Stamp? {
        let url: URL = stampURL(courseDirectory: courseDirectory, sectionNumber: sectionNumber)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Stamp.self, from: data)
    }

    /// Records what just went out. Called only when EVERY configured
    /// destination succeeded: a course publishing to two hosts, one of
    /// which failed, has not published, and its marker should stay up.
    @discardableResult
    static func recordPublish(
        courseDirectory: URL,
        sectionNumber: Int,
        fingerprint: String,
        destinations: [String],
        at moment: Date = Date()
    ) -> Bool {
        let url: URL = stampURL(courseDirectory: courseDirectory, sectionNumber: sectionNumber)
        let stamp: Stamp = Stamp(
            fingerprint: fingerprint,
            publishedAt: moment,
            destinations: destinations
        )
        let encoder: JSONEncoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(stamp).write(to: url, options: .atomic)
            return true
        } catch {
            // A stamp that could not be written costs a marker that stays
            // up. Nothing a teacher is doing should stop for it.
            FileHandle.standardError.write(
                Data("Could not record what was published: \(error)\n".utf8)
            )
            return false
        }
    }

    /// True when this section has pages that have changed since it was
    /// last published.
    ///
    /// **False for a section that has never been published at all.** A
    /// course created this morning has not been edited since anything —
    /// there is nothing to compare it against, and "Edited" on a brand new
    /// course would be a marker that is always on, which is a marker
    /// nobody reads.
    static func hasUnpublishedEdits(
        courseDirectory: URL,
        sectionNumber: Int,
        excludingRelativePaths: [String] = []
    ) -> Bool {
        guard let stamp = stamp(courseDirectory: courseDirectory, sectionNumber: sectionNumber) else {
            return false
        }
        let current: String = fingerprint(
            courseDirectory: courseDirectory,
            sectionNumber: sectionNumber,
            excludingRelativePaths: excludingRelativePaths
        )
        return stamp.fingerprint != current
    }

    /// What a section window's title bar says.
    ///
    /// The em dash and the capital E are Pages', deliberately: a teacher
    /// who has seen one save indicator has seen this one.
    static func windowTitle(base: String, hasUnpublishedEdits: Bool) -> String {
        if !hasUnpublishedEdits {
            return base
        }
        return base + " — Edited"
    }


    /// Whether a path sits inside somewhere the caller has ruled out —
    /// used for a "publish into a folder on this computer" destination the
    /// teacher has pointed INSIDE their own course folder. `deploy.py`
    /// writes the whole built site there, so counting it would leave the
    /// marker on permanently, one publish feeding the next.
    static func isExcluded(relativePath: String, by excluded: [String]) -> Bool {
        for candidate in excluded where !candidate.isEmpty {
            if relativePath == candidate || relativePath.hasPrefix(candidate + "/") {
                return true
            }
        }
        return false
    }

    /// Where a course publishes to that is inside the course folder
    /// itself, as a relative path — nothing, for the overwhelming majority
    /// of courses, which publish to a host or to a folder somewhere else.
    static func selfPublishingSubpaths(
        courseDirectory: URL,
        destinations: [CourseConfiguration.DeployDestination]
    ) -> [String] {
        var result: [String] = []
        for destination in destinations where !destination.path.isEmpty {
            let target: URL = URL(fileURLWithPath: (destination.path as NSString).expandingTildeInPath)
            let relative: String = relativePathOf(target, under: courseDirectory)
            if !relative.isEmpty {
                result.append(relative)
            }
        }
        return result
    }

    // MARK: - Private helpers

    private static let wantedKeys: Set<URLResourceKey> = [
        .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey
    ]

    private static func line(forRelativePath relativePath: String, values: URLResourceValues?) -> String {
        let size: Int = values?.fileSize ?? 0
        let modified: Double = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relativePath)|\(size)|\(Int(modified * 1_000_000))"
    }

    /// Everything a symlink brings in, under the link's own path.
    ///
    /// The target is walked WITHOUT following any further links: one hop
    /// is what a teacher's vault arrangement needs, and refusing the
    /// second is what stops a link pointing at its own parent from
    /// walking forever.
    private static func appendLines(
        _ lines: inout [String],
        forSymbolicLinkAt linkURL: URL,
        relativePath: String,
        sectionNumber: Int,
        excluding: [String]
    ) {
        let resolved: URL = linkURL.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: wantedKeys)
        if values?.isRegularFile == true {
            if countsTowardFingerprint(relativePath: relativePath, sectionNumber: sectionNumber) {
                lines.append(line(forRelativePath: relativePath, values: values))
            }
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              folderCountsTowardFingerprint(relativePath: relativePath, sectionNumber: sectionNumber),
              let inner = FileManager.default.enumerator(
                  at: resolved,
                  includingPropertiesForKeys: Array(wantedKeys),
                  options: [.skipsHiddenFiles]
              ) else {
            // A broken link still contributes its own presence, so that
            // repointing or removing it is not invisible.
            let destination: String = (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) ?? ""
            lines.append(relativePath + "|link|" + destination)
            return
        }
        for case let innerURL as URL in inner {
            let innerRelative: String = relativePath + "/" + relativePathOf(innerURL, under: resolved)
            let innerValues = try? innerURL.resourceValues(forKeys: wantedKeys)
            if innerValues?.isRegularFile != true {
                if !folderCountsTowardFingerprint(relativePath: innerRelative, sectionNumber: sectionNumber) {
                    inner.skipDescendants()
                }
                continue
            }
            if isExcluded(relativePath: innerRelative, by: excluding) {
                continue
            }
            if !countsTowardFingerprint(relativePath: innerRelative, sectionNumber: sectionNumber) {
                continue
            }
            lines.append(line(forRelativePath: innerRelative, values: innerValues))
        }
    }

    private static func pathParts(_ relativePath: String) -> [String] {
        var result: [String] = []
        for part in relativePath.split(separator: "/") {
            result.append(String(part))
        }
        return result
    }

    private static func relativePathOf(_ url: URL, under root: URL) -> String {
        let rootPath: String = root.standardizedFileURL.path
        let path: String = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return ""
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func digest(of text: String) -> String {
        let hashed = SHA256.hash(data: Data(text.utf8))
        var result: String = ""
        for byte in hashed {
            result += String(format: "%02x", byte)
        }
        return result
    }
}
