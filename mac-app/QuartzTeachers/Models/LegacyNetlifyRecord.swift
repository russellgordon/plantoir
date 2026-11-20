import Foundation

/// The legacy Netlify record in a section's built output
/// (`.merged_output/section<N>/.netlify_site.json`), brought into the
/// working folder before a rollover's step (#899 U3b, Russell's rulings of
/// 2026-11-20). Its own file because its writes are NOT a step and never
/// will be (`UndoWriterScanTests`: notAStep): the built output is outside
/// the working folder, where no step can name a place, and the bring-in is
/// the change a deploy's own migration makes (`load_netlify_marker`).
extension DeployCommand {

    // MARK: - Stored properties

    /// A test stops the bring-in right after a record's bytes are written
    /// beside their place and before the rename, as a process that died
    /// there would (the hook may truncate the file, as a death mid-write
    /// leaves it); true stops it. Nil in the app.
    nonisolated(unsafe) static var bringInDiesAfterWriting: ((URL) -> Bool)?

    // MARK: - Types

    /// Why a rollover could not bring the legacy Netlify marker into the
    /// working folder (`moveTheLegacyMarkerIn`): it could not be read,
    /// written in its new place or removed from the old one. The rollover
    /// is refused before anything of it is changed, and this is what is
    /// said after "Nothing was changed:".
    struct LegacyMarkerNotMovedIn: Error, LocalizedError, Equatable {

        // MARK: - Stored properties

        /// The legacy marker, as a teacher would find it.
        let legacyName: String

        /// Where it was to go, as a teacher would find it.
        let placeName: String

        // MARK: - Computed properties

        var errorDescription: String? {
            return "the website record “\(legacyName)” could not be moved to “\(placeName)”."
        }
    }

    /// What `moveTheLegacyMarkerIn` did, so a rollover whose step is then
    /// refused can put it back and "Nothing was changed" stays true
    /// (`putBack`), or, when that cannot be done, say what moved.
    nonisolated struct LegacyMarkerBroughtIn: Equatable, Sendable {

        // MARK: - Stored properties

        /// Where the legacy marker was, in the built output.
        let legacyURL: URL

        /// Where its bytes are now, in `.netlify_sites`.
        let placeURL: URL

        /// Its bytes.
        let bytes: Data

        /// True when the place already held these same bytes, so the legacy
        /// marker was only removed (a migration that stopped before its
        /// removal, finished).
        let removedADuplicate: Bool

        // MARK: - Computed properties

        /// The legacy marker, as a teacher would find it.
        var legacyName: String {
            return ".merged_output/" + DeployCommand.nameForTeacher(legacyURL)
        }

        /// Its place now, as a teacher would find it.
        var placeName: String {
            return DeployCommand.nameForTeacher(placeURL)
        }

        // MARK: - Functions

        /// Puts the legacy marker back in the built output, for a step that
        /// was then REFUSED (nothing of it made). Never over anything, and
        /// only while its new place still holds exactly these bytes. False
        /// when it could not be put back.
        func putBack() -> Bool {
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                return false
            }
            if !DeployCommand.placeWhole(bytes, at: legacyURL) {
                return false
            }
            if removedADuplicate {
                return true
            }
            guard let there = try? Data(contentsOf: placeURL), there == bytes,
                  (try? FileManager.default.removeItem(at: placeURL)) != nil else {
                try? FileManager.default.removeItem(at: legacyURL)
                return false
            }
            return true
        }
    }

    // MARK: - Functions

    /// Where a stale legacy marker is brought in: beside the current
    /// record, `.netlify_sites/section<N>.from-built-output.json`, a name
    /// deploy.py never reads.
    static func broughtInLeftoverURL(forSection sectionNumber: Int, in course: Course) -> URL {
        return course.directoryURL
            .appendingPathComponent(".netlify_sites")
            .appendingPathComponent("section\(sectionNumber).from-built-output.json")
    }

    /// Brings the LEGACY Netlify marker out of the built output into the
    /// working folder, before a rollover's step is planned (#899 U3b,
    /// Russell's rulings of 2026-11-20), so the step can name it like any
    /// other marker and an Undo puts it back whole. The legacy marker lives
    /// in the built output (`.merged_output`, a link out of the working
    /// folder), where no step can name it.
    ///
    /// deploy.py's rule, reused (`load_netlify_marker`, `scripts/deploy.py`):
    /// a current marker (`.netlify_sites/section<N>.json`) is the one read,
    /// and only when there is none is a legacy marker that reads as JSON
    /// written there (mode 0600) and then removed. Then:
    /// - a legacy marker a deploy would NOT read (a current one is there and
    ///   holds other bytes, or it is not JSON) is a stale leftover, and the
    ///   rollover is never stopped by it (Russell, 2026-11-20, evening): it
    ///   is brought in beside the current record
    ///   (`broughtInLeftoverURL`), which `planSiteRelease` then sets aside
    ///   in the step, so a later deploy cannot migrate it back in;
    /// - beside a place that already holds the SAME bytes, it is what a
    ///   migration that stopped before its removal leaves, and it is only
    ///   removed (the migration finished).
    ///
    /// The record is placed WHOLE (`placeWhole`: written beside its place
    /// under a name of its own, then renamed in, never over anything), so a
    /// death part way through the write leaves no partial record where a
    /// deploy reads one, only a hidden file the next bring-in removes (the
    /// re-review of U3b, LOW 1: a partial current record would have made the
    /// next rollover set the GOOD legacy record aside as stale).
    ///
    /// Refused only when it cannot be read, written or removed: the place
    /// this call wrote, and a `.netlify_sites` folder it made, are removed
    /// again first, so the folder is as it was. A crash between the rename
    /// and the removal leaves the same bytes in both places: a deploy reads
    /// the current record, and the next rollover finishes the removal. Nil
    /// when there is no legacy marker.
    static func moveTheLegacyMarkerIn(
        forSection sectionNumber: Int, in course: Course
    ) throws(LegacyMarkerNotMovedIn) -> LegacyMarkerBroughtIn? {
        let legacyURL: URL = legacyMarkerURL(forSection: sectionNumber, in: course)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        let currentURL: URL = course.directoryURL
            .appendingPathComponent(".netlify_sites")
            .appendingPathComponent("section\(sectionNumber).json")
        let legacyName: String = ".merged_output/" + nameForTeacher(legacyURL)
        guard let legacyData = try? Data(contentsOf: legacyURL) else {
            throw LegacyMarkerNotMovedIn(legacyName: legacyName, placeName: nameForTeacher(currentURL))
        }
        let readsAsJSON: Bool = (try? JSONSerialization.jsonObject(with: legacyData)) != nil
        var placeURL: URL = currentURL
        if FileManager.default.fileExists(atPath: currentURL.path) || !readsAsJSON {
            placeURL = broughtInLeftoverURL(forSection: sectionNumber, in: course)
            if let current = try? Data(contentsOf: currentURL), current == legacyData {
                placeURL = currentURL
            }
        }
        let refusal: LegacyMarkerNotMovedIn = LegacyMarkerNotMovedIn(legacyName: legacyName, placeName: nameForTeacher(placeURL))
        removeHalfWrittenCopies(of: placeURL)
        if FileManager.default.fileExists(atPath: placeURL.path) {
            guard let there = try? Data(contentsOf: placeURL), there == legacyData else {
                throw refusal
            }
            if (try? FileManager.default.removeItem(at: legacyURL)) == nil {
                throw refusal
            }
            return LegacyMarkerBroughtIn(legacyURL: legacyURL, placeURL: placeURL, bytes: legacyData, removedADuplicate: true)
        }
        let folder: URL = placeURL.deletingLastPathComponent()
        let madeTheFolder: Bool = !FileManager.default.fileExists(atPath: folder.path)
        if !placeWhole(legacyData, at: placeURL, mode: 0o600) {
            if madeTheFolder {
                DeployCommand.removeIfEmpty(folder)
            }
            throw refusal
        }
        if (try? FileManager.default.removeItem(at: legacyURL)) == nil {
            try? FileManager.default.removeItem(at: placeURL)
            if madeTheFolder {
                DeployCommand.removeIfEmpty(folder)
            }
            throw refusal
        }
        return LegacyMarkerBroughtIn(legacyURL: legacyURL, placeURL: placeURL, bytes: legacyData, removedADuplicate: false)
    }

    // MARK: - Functions: placing a record whole

    /// The start of the name a record is written under beside its place.
    nonisolated static func halfWrittenPrefix(for placeURL: URL) -> String {
        return "." + placeURL.lastPathComponent + ".bringing-in-"
    }

    /// Writes `data` beside `url` under a name of its own (mode `mode`),
    /// then renames it in, never over anything: the place holds the whole
    /// record or nothing. Makes the folder when it is missing. False, with
    /// the written copy removed, when any part fails.
    nonisolated static func placeWhole(_ data: Data, at url: URL, mode: Int = 0o644) -> Bool {
        let folder: URL = url.deletingLastPathComponent()
        let id: String = String(UUID().uuidString.prefix(8)).lowercased()
        let besideURL: URL = folder.appendingPathComponent(halfWrittenPrefix(for: url) + id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: besideURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: besideURL.path)
        } catch {
            try? FileManager.default.removeItem(at: besideURL)
            return false
        }
        if let dies = bringInDiesAfterWriting, dies(besideURL) {
            return false
        }
        if !UndoSwap.renameExclusively(besideURL, onto: url) {
            try? FileManager.default.removeItem(at: besideURL)
            return false
        }
        return true
    }

    /// Removes every copy of a record left half written beside its place by
    /// a bring-in that died, each by its own path.
    nonisolated static func removeHalfWrittenCopies(of placeURL: URL) {
        let folder: URL = placeURL.deletingLastPathComponent()
        let prefix: String = halfWrittenPrefix(for: placeURL)
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for entry in entries where entry.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry))
        }
    }

    /// Removes a folder only when it is empty (`rmdir`).
    nonisolated static func removeIfEmpty(_ folder: URL) {
        _ = folder.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return rmdir(path)
        }
    }
}
